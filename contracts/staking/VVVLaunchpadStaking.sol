///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

/**
    @title VVVLaunchpadStaking
    @notice Handles native and ERC20 staking for launchpad
 */

contract VVVLaunchpadStaking is VVVAuthorizationRegistryChecker {
    ///@notice the array of staking durations for each pool
    uint256[] public stakingDurations;

    ///@notice emitted when the staking durations are set
    event StakingDurationsSet(uint256[] indexed stakingDurations);

    constructor(
        uint256[] memory _stakingDurations,
        address _authorizationRegistry
    ) VVVAuthorizationRegistryChecker(_authorizationRegistry) {
        stakingDurations = _stakingDurations;
    }

    ///@notice allows an admin to set the full array of staking durations
    function setStakingDurations(uint256[] memory _stakingDurations) external onlyAuthorized {
        stakingDurations = _stakingDurations;
        emit StakingDurationsSet(_stakingDurations);
    }
}
