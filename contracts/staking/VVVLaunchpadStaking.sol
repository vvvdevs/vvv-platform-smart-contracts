///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

/**
    @title VVVLaunchpadStaking
    @notice Handles native and ERC20 staking for launchpad
 */

contract VVVLaunchpadStaking is VVVAuthorizationRegistryChecker {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10_000;

    uint256[] public stakingDurations;

    constructor(
        uint256[] memory _stakingDurations,
        address _authorizationRegistry
    ) VVVAuthorizationRegistryChecker(_authorizationRegistry) {
        stakingDurations = _stakingDurations;
    }

    function setStakingDurations(uint256[] memory _stakingDurations) external onlyAuthorized {
        stakingDurations = _stakingDurations;
    }
}
