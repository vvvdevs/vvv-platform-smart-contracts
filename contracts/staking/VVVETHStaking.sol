///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract VVVETHStaking {
    uint256 public stakeId;

    enum StakingDuration {
        ThreeMonths,
        SixMonths,
        OneYear
    }

    struct StakeData {
        uint256 stakedEthAmount;
        uint256 stakeStartTimestamp;
        bool stakeIsWithdrawn;
        StakingDuration stakeDuration;
    }

    mapping(StakingDuration => uint256) public durationToSeconds;
    mapping(address => mapping(uint256 => StakeData)) public userStakes;
    mapping(address => uint256[]) private _userStakeIds;

    event Stake(
        address indexed staker,
        uint256 indexed stakeId,
        uint256 stakedEthAmount,
        uint256 stakeStartTimestamp,
        StakingDuration duration
    );
    event Withdraw(
        address indexed staker,
        uint256 indexed stakeId,
        uint256 stakedEthAmount,
        uint256 stakeStartTimestamp,
        StakingDuration duration
    );

    error CantStakeZeroEth();
    error CantWithdrawBeforeStakeDuration();
    error InvalidStakeId();
    error InvalidStakingDuration();
    error StakeIsWithdrawn();
    error WithdrawFailed();

    constructor() {
        durationToSeconds[StakingDuration.ThreeMonths] = 90 days;
        durationToSeconds[StakingDuration.SixMonths] = 180 days;
        durationToSeconds[StakingDuration.OneYear] = 360 days;
    }

    function stakeEth(StakingDuration _stakeDuration) external payable {
        if (msg.value == 0) revert CantStakeZeroEth();
        if (!_isValidDuration(_stakeDuration)) revert InvalidStakingDuration();
        ++stakeId;

        userStakes[msg.sender][stakeId] = StakeData({
            stakedEthAmount: msg.value,
            stakeStartTimestamp: block.timestamp,
            stakeIsWithdrawn: false,
            stakeDuration: _stakeDuration
        });

        _userStakeIds[msg.sender].push(stakeId);

        emit Stake(msg.sender, stakeId, msg.value, block.timestamp, _stakeDuration);
    }

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

    function _isValidDuration(StakingDuration _stakeDuration) private pure returns (bool) {
        return (_stakeDuration == StakingDuration.ThreeMonths ||
            _stakeDuration == StakingDuration.SixMonths ||
            _stakeDuration == StakingDuration.OneYear);
    }

    function userStakeIds(address _user) external view returns (uint256[] memory) {
        return _userStakeIds[_user];
    }
}
