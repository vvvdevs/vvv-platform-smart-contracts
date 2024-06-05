//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVToken } from "contracts/tokens/VvvToken.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
import { VVVStakingTestBase } from "test/staking/VVVStakingTestBase.sol";
import { VVVLaunchpadStaking } from "contracts/staking/VVVLaunchpadStaking.sol";

/**
 * @title VVVLaunchpadStaking Unit Tests
 * @dev use "forge test --match-contract VVVLaunchpadStakingUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVLaunchpadStaking" to run coverage
 */
contract VVVLaunchpadStakingUnitTests is VVVStakingTestBase {
    // Sets up project and payment tokens, and an instance of the ETH staking contract
    function setUp() public {
        vm.startPrank(deployer, deployer);

        //set default staking durations
        setDefaultLaunchpadStakingDurations();

        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        LaunchpadStakingInstance = new VVVLaunchpadStaking(stakingDurations, address(AuthRegistry));
        VvvTokenInstance = new VVVToken(type(uint256).max, 0, address(AuthRegistry));

        //set auth registry permissions
        AuthRegistry.grantRole(launchpadStakingManagerRole, launchpadStakingManager);
        bytes4 setStakingDurationsSelector = LaunchpadStakingInstance.setStakingDurations.selector;
        AuthRegistry.setPermission(
            address(LaunchpadStakingInstance),
            setStakingDurationsSelector,
            launchpadStakingManagerRole
        );

        vm.stopPrank();
    }

    function testDeployment() public {
        assertTrue(address(LaunchpadStakingInstance) != address(0));
    }

    //tests that the admin can set the array of staking durations
    function testAdminSetStakingDurations() public {
        vm.startPrank(launchpadStakingManager, launchpadStakingManager);
        LaunchpadStakingInstance.setStakingDurations(stakingDurations);
        vm.stopPrank();

        for (uint256 i = 0; i < stakingDurations.length; i++) {
            assertEq(LaunchpadStakingInstance.stakingDurations(i), stakingDurations[i]);
        }
    }

    //tests that a non-admin cannot set the array of staking durations
    function testNonAdminCannotSetStakingDurations() public {
        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        LaunchpadStakingInstance.setStakingDurations(stakingDurations);
        vm.stopPrank();
    }
}
