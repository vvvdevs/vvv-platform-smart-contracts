///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

/**
    @title VVVLaunchpadStaking
    @notice Handles native and ERC20 staking for launchpad
 */

contract VVVLaunchpadStaking is VVVAuthorizationRegistryChecker {
    ///@notice denominator for calculating early unstake penalties
    uint256 public constant PENALTY_DENOMINATOR = 1e18;

    ///@notice contains details for each stake action made by a user
    struct Stake {
        uint256 durationIndex;
        uint256 amount;
        uint256 startTimestamp;
    }

    ///@notice numerator for calculating early unstake penalties
    uint256 public penaltyNumerator = 5e17;

    ///@notice the array of staking durations for each pool
    uint256[] public stakingDurations;

    ///@notice maps users and pools (durations) to their stake details
    mapping(address => mapping(uint256 => Stake)) public userStakes;

    ///@notice emitted when the penalty numerator is set
    event PenaltyNumeratorSet(uint256 indexed newNumerator);

    ///@notice emitted when the staking durations are set
    event StakingDurationsSet(uint256[] indexed stakingDurations);

    ///@notice thrown when an invalid poolId is provided
    error InvalidPoolId();

    ///@notice thrown when the penalty numerator is set to a value greater than the denominator
    error NumeratorCannotExceedDenominator();

    ///@notice thrown when a transfer fails
    error TransferFailed();

    ///@notice thrown when a stake msg.value of zero is provided
    error ZeroStakeAmount();

    constructor(
        uint256[] memory _stakingDurations,
        address _authorizationRegistry
    ) VVVAuthorizationRegistryChecker(_authorizationRegistry) {
        stakingDurations = _stakingDurations;
    }

    ///@notice allows user to stake native $VVV in one pool
    function stake(uint256 _poolId) external payable {
        if (_poolId >= stakingDurations.length) revert InvalidPoolId();
        if (msg.value == 0) revert ZeroStakeAmount();

        //read in the current mapping entry for the user and pool which may or may not be initialized
        Stake storage thisStake = userStakes[msg.sender][_poolId];

        //if the default values is not set, a prior stake exists. update to new amount and startTimestamp
        //if the default values is set, a prior stake does not exist. set the amount and startTimestamp
        if (thisStake.amount > 0) {
            thisStake.amount += msg.value;
            thisStake.startTimestamp = block.timestamp;
        } else {
            thisStake.amount = msg.value;
            thisStake.startTimestamp = block.timestamp;
            thisStake.durationIndex = _poolId;
        }
    }

    ///@notice unstakes the user's stake for a given pool and applies an early withdraw penalty if applicable
    function unstake(uint256 _poolId) external {
        if (_poolId >= stakingDurations.length) revert InvalidPoolId();

        //read in the current mapping entry for the user and pool which may or may not be initialized
        Stake memory thisStake = userStakes[msg.sender][_poolId];
        uint256 penaltyAmount = calculatePenalty(thisStake);

        (bool burnSuccess, ) = address(0).call{ value: penaltyAmount }("");
        (bool transferSuccess, ) = msg.sender.call{ value: thisStake.amount - penaltyAmount }("");

        if (!burnSuccess || !transferSuccess) revert TransferFailed();
    }

    ///@notice allows an admin to set the full array of staking durations
    function setStakingDurations(uint256[] memory _stakingDurations) external onlyAuthorized {
        stakingDurations = _stakingDurations;
        emit StakingDurationsSet(_stakingDurations);
    }

    ///@notice allows an admin to set the penalty numerator
    function setPenaltyNumerator(uint256 _newNumerator) external onlyAuthorized {
        if (_newNumerator > penaltyNumerator) revert NumeratorCannotExceedDenominator();
        penaltyNumerator = _newNumerator;
        emit PenaltyNumeratorSet(_newNumerator);
    }

    ///@notice returns the penalty amount for an early withdraw based on 50% penalty for immediate withdraw and 0% penalty for withdraw at full duration
    function calculatePenalty(Stake memory _stake) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - _stake.startTimestamp;
        uint256 duration = stakingDurations[_stake.durationIndex];

        if (timeElapsed >= duration) {
            return 0;
        } else {
            uint256 remainingTime = duration - timeElapsed;
            return (_stake.amount * penaltyNumerator * remainingTime) / (duration * PENALTY_DENOMINATOR);
        }
    }

    ///@notice returns an array of a staker's active (amount > 0) stakes
    function getStakesByAddress(address _staker) public view returns (Stake[] memory) {
        uint256 stakesLength;
        for (uint256 i = 0; i < stakingDurations.length; i++) {
            if (userStakes[_staker][i].amount > 0) {
                ++stakesLength;
            }
        }
        Stake[] memory stakes = new Stake[](stakesLength);
        uint256 j = 0;
        for (uint256 i = 0; i < stakingDurations.length; i++) {
            if (userStakes[_staker][i].amount > 0) {
                stakes[j] = userStakes[_staker][i];
                ++j;
            }
        }
        return stakes;
    }
}
