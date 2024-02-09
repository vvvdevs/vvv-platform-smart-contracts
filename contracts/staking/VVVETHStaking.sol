///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract VVVETHStaking {
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

    ///@notice maps user to their stakes by stakeId
    mapping(address => mapping(uint256 => StakeData)) public userStakes;

    ///@notice maps user to their stakeIds
    mapping(address => uint256[]) private _userStakeIds;

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

    ///@notice thrown when a user tries to stake 0 eth
    error CantStakeZeroEth();

    ///@notice thrown when a user tries to withdraw before the stake duration has elapsed
    error CantWithdrawBeforeStakeDuration();

    ///@notice thrown when a user tries to withdraw a stake that hasn't been initialized
    error InvalidStakeId();

    ///@notice thrown when a user tries to withdraw a stake that has already been withdrawn
    error StakeIsWithdrawn();

    ///@notice thrown when a user tries to withdraw and the transfer fails
    error WithdrawFailed();

    ///@notice initializes the second values corresponding to each duration enum entry
    constructor() {
        durationToSeconds[StakingDuration.ThreeMonths] = 90 days;
        durationToSeconds[StakingDuration.SixMonths] = 180 days;
        durationToSeconds[StakingDuration.OneYear] = 360 days;
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

    ///@notice Returns the array of stake IDs for a user
    function userStakeIds(address _user) external view returns (uint256[] memory) {
        return _userStakeIds[_user];
    }
}
