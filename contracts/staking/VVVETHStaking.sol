///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

contract VVVETHStaking is VVVAuthorizationRegistryChecker {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10_000;

    ///@notice the interface to the $VVV token
    IERC20 public vvvToken;

    ///@notice flag for whether new stakes are allowed
    bool public newStakesPermitted;

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
        @param staker The address of the staker
        @param stakedEthAmount The amount of ETH staked
        @param stakeStartTimestamp The timestamp when the stake was made
        @param secondsClaimed The number of seconds claimed
        @param stakeIsWithdrawn Whether the stake has been withdrawn
        @param stakeDuration The duration of the stake
     */
    struct StakeData {
        address staker;
        uint224 stakedEthAmount;
        uint32 stakeStartTimestamp;
        uint256 secondsClaimed;
        bool stakeIsWithdrawn;
        StakingDuration stakeDuration;
    }

    ///@notice maps the duration enum entry to the number of seconds in that duration
    mapping(StakingDuration => uint256) public durationToSeconds;

    ///@notice maps the duration enum entry to the $VVV accrual multiplier for that duration
    mapping(StakingDuration => uint256) public durationToMultiplier;

    ///@notice maps stakeId to the corresponding StakeData entry
    mapping(uint256 => StakeData) public stakes;

    ///@notice emitted when ETH is received
    event EtherReceived();

    ///@notice emitted when a user stakes
    event Stake(
        address indexed staker,
        uint256 indexed stakeId,
        uint224 stakedEthAmount,
        uint32 stakeStartTimestamp,
        StakingDuration stakeDuration
    );

    ///@notice emitted when a user withdraws
    event Withdraw(
        address indexed staker,
        uint256 indexed stakeId,
        uint224 stakedEthAmount,
        uint32 stakeStartTimestamp,
        StakingDuration stakeDuration
    );

    ///@notice emitted when a user claims $VVV
    event VvvClaim(address indexed staker, uint256 vvvAmount);

    ///@notice emitted when a user who is not a stake owner attemps to operate on the stake
    error CallerIsNotStakeOwner();

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

    ///@notice thrown when a user attempts to staken when new stakes are not permitted
    error NewStakesNotPermitted();

    ///@notice thrown when a user tries to withdraw a stake that has already been withdrawn
    error StakeIsWithdrawn();

    ///@notice thrown when a user tries to withdraw and the transfer fails
    error WithdrawFailed();

    ///@notice initializes the second values corresponding to each duration enum entry
    constructor(
        address _authorizationRegistryAddress
    ) VVVAuthorizationRegistryChecker(_authorizationRegistryAddress) {
        durationToSeconds[StakingDuration.ThreeMonths] = 90 days;
        durationToSeconds[StakingDuration.SixMonths] = 180 days;
        durationToSeconds[StakingDuration.OneYear] = 360 days;

        durationToMultiplier[StakingDuration.ThreeMonths] = 10_000;
        durationToMultiplier[StakingDuration.SixMonths] = 15_000;
        durationToMultiplier[StakingDuration.OneYear] = 30_000;
    }

    ///@notice Fallback function to receive ETH
    receive() external payable {
        emit EtherReceived();
    }

    ///@notice enforces that newStakesPermitted is true before allowing a stake
    modifier whenStakingIsPermitted() {
        if (!newStakesPermitted) revert NewStakesNotPermitted();
        _;
    }

    /**
        @notice Stakes ETH for a given duration
        @param _stakeDuration The duration of the stake
        @return The id of the stake
     */
    function stakeEth(
        StakingDuration _stakeDuration
    ) external payable whenStakingIsPermitted returns (uint256) {
        _stakeEth(_stakeDuration, uint224(msg.value));
        return stakeId;
    }

    /**
        @notice Restakes ETH for a given duration, marks previous stake as withdrawn but does not transfer the ETH
        @param _stakeId The id of the stake to restake
        @param _stakeDuration The duration of the new stake
     */
    function restakeEth(
        uint256 _stakeId,
        StakingDuration _stakeDuration
    ) external whenStakingIsPermitted returns (uint256) {
        StakeData storage stake = stakes[_stakeId];
        _withdrawChecks(stake);
        stake.stakeIsWithdrawn = true;
        _stakeEth(_stakeDuration, stake.stakedEthAmount);
        return stakeId;
    }

    /**
        @notice Withdraws a stake
        @param _stakeId The id of the stake
     */
    function withdrawStake(uint256 _stakeId) external {
        StakeData storage stake = stakes[_stakeId];
        _withdrawChecks(stake);

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
        @param _stakeId The stake ID for which to claim $VVV
     */
    function claimVvv(uint256 _stakeId) external {
        StakeData storage stake = stakes[_stakeId];
        if (stake.staker != msg.sender) revert CallerIsNotStakeOwner();

        uint256 unclaimedSeconds = _calculateUnclaimedSeconds(stake);
        if (unclaimedSeconds == 0) revert CantClaimZeroVvv();

        uint256 claimableVvv = _calculateClaimableVvvAmount(stake, unclaimedSeconds);

        stake.secondsClaimed += unclaimedSeconds;

        vvvToken.safeTransfer(msg.sender, claimableVvv);

        emit VvvClaim(msg.sender, claimableVvv);
    }

    function _calculateUnclaimedSeconds(StakeData memory _stake) private view returns (uint256) {
        uint256 stakeDuration = durationToSeconds[_stake.stakeDuration];
        uint256 secondsSinceStakingStarted;
        uint256 secondsStaked;
        uint256 unclaimedSeconds;

        unchecked {
            secondsSinceStakingStarted = block.timestamp - _stake.stakeStartTimestamp;
            secondsStaked = secondsSinceStakingStarted >= stakeDuration
                ? stakeDuration
                : secondsSinceStakingStarted;
            unclaimedSeconds = secondsStaked - _stake.secondsClaimed;
        }

        return unclaimedSeconds;
    }

    /**
        @notice Returns the total amount of $VVV claimable by a single stake for a given amount of unclaimed seconds
        @dev considers the "nominalAccruedEth" and multiplies by the exchange rate and duration multiplier to obtain the total $VVV accrued
        @param _stake A StakeData struct representing the stake for which the accrued $VVV is to be calculated
        @return $VVV accrued
     */
    function _calculateClaimableVvvAmount(
        StakeData memory _stake,
        uint256 _unclaimedSeconds
    ) private view returns (uint256) {
        uint256 stakeDuration = durationToSeconds[_stake.stakeDuration];
        uint256 nominalAccruedEth;
        uint256 accruedVvv;

        unchecked {
            nominalAccruedEth = (_unclaimedSeconds * _stake.stakedEthAmount) / stakeDuration;
            accruedVvv =
                (nominalAccruedEth * ethToVvvExchangeRate() * durationToMultiplier[_stake.stakeDuration]) /
                DENOMINATOR;
        }

        return accruedVvv;
    }

    ///@dev allows private versions to avoid repeated reads of stakes[] internally
    function calculateClaimableVvvAmount(uint256 _stakeId) public view returns (uint256) {
        return
            _calculateClaimableVvvAmount(stakes[_stakeId], _calculateUnclaimedSeconds(stakes[_stakeId]));
    }

    ///@notice Returns the exchange rate of ETH to $VVV for staking reward accrual
    function ethToVvvExchangeRate() public pure returns (uint256) {
        return 1;
    }

    ///@notice sets the duration multipliers for a duration enum entry
    function setDurationMultipliers(
        StakingDuration[] memory _duration,
        uint256[] memory _multipliers
    ) external onlyAuthorized {
        for (uint256 i = 0; i < _duration.length; ++i) {
            durationToMultiplier[_duration[i]] = _multipliers[i];
        }
    }

    ///@notice sets newStakesPermitted
    function setNewStakesPermitted(bool _newStakesPermitted) external onlyAuthorized {
        newStakesPermitted = _newStakesPermitted;
    }

    ///@notice Sets the address of the $VVV token
    function setVvvToken(address _vvvTokenAddress) external onlyAuthorized {
        vvvToken = IERC20(_vvvTokenAddress);
    }

    ///@notice allows admin to withdraw ETH
    function withdrawEth(uint256 _amount) external onlyAuthorized {
        (bool success, ) = payable(msg.sender).call{ value: _amount }("");
        if (!success) revert WithdrawFailed();
    }

    ///@notice withdraws VVV tokens from the contract
    function withdrawVvv(uint256 _amount) external onlyAuthorized {
        vvvToken.safeTransfer(msg.sender, _amount);
    }

    ///@notice Private function to stake ETH, used by both stakeEth and restakeEth
    function _stakeEth(StakingDuration _stakeDuration, uint224 _stakedEthAmount) private {
        if (_stakedEthAmount == 0) revert CantStakeZeroEth();
        ++stakeId;

        stakes[stakeId] = StakeData({
            staker: msg.sender,
            stakedEthAmount: _stakedEthAmount,
            stakeStartTimestamp: uint32(block.timestamp),
            secondsClaimed: 0,
            stakeIsWithdrawn: false,
            stakeDuration: _stakeDuration
        });

        emit Stake(
            msg.sender,
            stakeId,
            uint224(_stakedEthAmount),
            uint32(block.timestamp),
            _stakeDuration
        );
    }

    ///@notice checks permissions for withdrawing a stake based on stake owner, eth amount, stake start time, and whether the stake has been withdrawn
    function _withdrawChecks(StakeData memory _stake) private view {
        if (_stake.staker != msg.sender) revert CallerIsNotStakeOwner();
        if (_stake.stakedEthAmount == 0) revert InvalidStakeId();
        if (_stake.stakeIsWithdrawn) revert StakeIsWithdrawn();
        if (block.timestamp < _stake.stakeStartTimestamp + durationToSeconds[_stake.stakeDuration]) {
            revert CantWithdrawBeforeStakeDuration();
        }
    }
}
