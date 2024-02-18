///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVETHStaking is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10_000;

    ///@notice the interface to the $VVV token
    IERC20 public vvvToken;

    ///@notice The id of the last stake
    uint256 public stakeId;

    ///@notice The options for staking duration
    enum StakingDuration {
        ThreeMonths,
        SixMonths,
        OneYear
    }

    /**
        @notice The data stored for each stake
        @param stakedEthAmount The amount of ETH staked
        @param stakeStartTimestamp The timestamp when the stake was made
        @param stakeIsWithdrawn Whether the stake has been withdrawn
        @param stakeDuration The duration of the stake
     */
    struct StakeData {
        uint256 stakedEthAmount;
        uint256 stakeStartTimestamp;
        bool stakeIsWithdrawn;
        StakingDuration stakeDuration;
    }

    ///@notice maps the duration enum entry to the number of seconds in that duration
    mapping(StakingDuration => uint256) public durationToSeconds;

    ///@notice maps the duration enum entry to the $VVV accrual multiplier for that duration
    mapping(StakingDuration => uint256) public durationToMultiplier;

    ///@notice maps user to their stakes by stakeId
    mapping(address => mapping(uint256 => StakeData)) public userStakes;

    ///@notice maps user to their stakeIds
    mapping(address => uint256[]) private _userStakeIds;

    ///@notice maps user to the amount of $VVV claimed
    mapping(address => uint256) public userVvvClaimed;

    ///@notice emitted when a user stakes
    event Stake(
        address indexed staker,
        uint256 indexed stakeId,
        uint256 stakedEthAmount,
        uint256 stakeStartTimestamp,
        StakingDuration stakeDuration
    );

    ///@notice emitted when a user withdraws
    event Withdraw(
        address indexed staker,
        uint256 indexed stakeId,
        uint256 stakedEthAmount,
        uint256 stakeStartTimestamp,
        StakingDuration stakeDuration
    );

    ///@notice emitted when a user claims $VVV
    event VvvClaim(address indexed staker, uint256 vvvAmount);

    ///@notice thrown when a user tries to claim 0 $VVV
    error CantClaimZeroVvv();

    ///@notice thrown when a user tries to stake 0 eth
    error CantStakeZeroEth();

    ///@notice thrown when a user tries to withdraw before the stake duration has elapsed
    error CantWithdrawBeforeStakeDuration();

    ///@notice thrown when a user tries to claim more $VVV than they have accrued
    error InsufficientClaimableVvv();

    ///@notice thrown when a user tries to withdraw a stake that hasn't been initialized
    error InvalidStakeId();

    ///@notice thrown when a user tries to withdraw a stake that has already been withdrawn
    error StakeIsWithdrawn();

    ///@notice thrown when a user tries to withdraw and the transfer fails
    error WithdrawFailed();

    ///@notice initializes the second values corresponding to each duration enum entry
    constructor(address _vvvToken, address _owner) Ownable(_owner) {
        durationToSeconds[StakingDuration.ThreeMonths] = 90 days;
        durationToSeconds[StakingDuration.SixMonths] = 180 days;
        durationToSeconds[StakingDuration.OneYear] = 360 days;

        durationToMultiplier[StakingDuration.ThreeMonths] = 10_000;
        durationToMultiplier[StakingDuration.SixMonths] = 15_000;
        durationToMultiplier[StakingDuration.OneYear] = 30_000;

        vvvToken = IERC20(_vvvToken);
    }

    /**
        @notice Stakes ETH for a given duration
        @param _stakeDuration The duration of the stake
        @return The id of the stake
     */
    function stakeEth(StakingDuration _stakeDuration) external payable returns (uint256) {
        if (msg.value == 0) revert CantStakeZeroEth();
        ++stakeId;

        userStakes[msg.sender][stakeId] = StakeData({
            stakedEthAmount: msg.value,
            stakeStartTimestamp: block.timestamp,
            stakeIsWithdrawn: false,
            stakeDuration: _stakeDuration
        });

        _userStakeIds[msg.sender].push(stakeId);

        emit Stake(msg.sender, stakeId, msg.value, block.timestamp, _stakeDuration);
        return stakeId;
    }

    /**
        @notice Withdraws a stake
        @param _stakeId The id of the stake
     */
    function withdrawStake(uint256 _stakeId) external {
        StakeData storage stake = userStakes[msg.sender][_stakeId];

        if (stake.stakedEthAmount == 0) revert InvalidStakeId();
        if (stake.stakeIsWithdrawn) revert StakeIsWithdrawn();
        if (block.timestamp < stake.stakeStartTimestamp + durationToSeconds[stake.stakeDuration]) {
            revert CantWithdrawBeforeStakeDuration();
        }

        stake.stakeIsWithdrawn = true;
        (bool withdrawSuccess, ) = payable(msg.sender).call{ value: stake.stakedEthAmount }("");
        if (!withdrawSuccess) revert WithdrawFailed();

        emit Withdraw(
            msg.sender,
            _stakeId,
            stake.stakedEthAmount,
            stake.stakeStartTimestamp,
            stake.stakeDuration
        );
    }

    /**
        @notice Claims $VVV for a user
        @param _vvvAmount The amount of $VVV to claim
     */
    function claimVvv(uint256 _vvvAmount) external {
        if (_vvvAmount == 0) revert CantClaimZeroVvv();

        uint256 claimableVvv = calculateClaimableVvvAmount();
        if (_vvvAmount > claimableVvv) revert InsufficientClaimableVvv();

        userVvvClaimed[msg.sender] += _vvvAmount;

        vvvToken.safeTransfer(msg.sender, _vvvAmount);

        emit VvvClaim(msg.sender, _vvvAmount);
    }

    /**
        @notice Returns accrued $VVV for a user based on their staking activity
        @dev Does not account for any claimed tokens
        @return $VVV accrued
     */
    function calculateAccruedVvvAmount() public view returns (uint256) {
        uint256[] memory stakeIds = _userStakeIds[msg.sender];
        if (stakeIds.length == 0) return 0;

        uint256 totalVvvAccrued;
        for (uint256 i = 0; i < stakeIds.length; ++i) {
            StakeData memory stake = userStakes[msg.sender][stakeIds[i]];
            totalVvvAccrued += calculateAccruedVvvAmount(stake);
        }

        return totalVvvAccrued;
    }

    /**
        @notice Returns the total amount of $VVV accrued by a single stake
        @dev considers the "nominalAccruedEth" and multiplies by the exchange rate and duration multiplier to obtain the total $VVV accrued
        @param _stake A StakeData struct representing the stake for which the accrued $VVV is to be calculated
        @return $VVV accrued
     */
    function calculateAccruedVvvAmount(StakeData memory _stake) public view returns (uint256) {
        uint256 stakeDuration = durationToSeconds[_stake.stakeDuration];

        uint256 secondsStaked = block.timestamp - _stake.stakeStartTimestamp >= stakeDuration
            ? stakeDuration
            : block.timestamp - _stake.stakeStartTimestamp;

        uint256 nominalAccruedEth = (secondsStaked * _stake.stakedEthAmount) / stakeDuration;

        uint256 accruedVvv = (nominalAccruedEth *
            ethToVvvExchangeRate() *
            durationToMultiplier[_stake.stakeDuration]) / DENOMINATOR;

        return accruedVvv;
    }

    /**
        @notice Returns the remaining claimable amount of $VVV
        @dev where claimable = accrued - claimed
        @return $VVV claimable
     */
    function calculateClaimableVvvAmount() public view returns (uint256) {
        return calculateAccruedVvvAmount() - userVvvClaimed[msg.sender];
    }

    ///@notice Returns the exchange rate of ETH to $VVV for staking reward accrual
    function ethToVvvExchangeRate() public pure returns (uint256) {
        return 1;
    }

    ///@notice Returns the array of stake IDs for a user externally
    function userStakeIds(address _user) external view returns (uint256[] memory) {
        return _userStakeIds[_user];
    }

    ///@notice sets the duration multipliers for a duration enum entry
    function setDurationMultiplier(
        StakingDuration[] memory _duration,
        uint256[] memory _multipliers
    ) external onlyOwner {
        for (uint256 i = 0; i < _duration.length; ++i) {
            durationToMultiplier[_duration[i]] = _multipliers[i];
        }
    }

    ///@notice Sets the address of the $VVV token
    function setVvvToken(address _vvvTokenAddress) external onlyOwner {
        vvvToken = IERC20(_vvvTokenAddress);
    }
}
