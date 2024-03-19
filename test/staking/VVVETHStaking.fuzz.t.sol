//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";
import { VVVETHStakingTestBase } from "test/staking/VVVETHStakingTestBase.sol";
import { VVVETHStaking } from "contracts/staking/VVVETHStaking.sol";

/**
 * @title VVVETHStaking Fuzz Tests
 * @dev use "forge test --match-contract VVVETHStakingUnitFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVETHStaking" to run coverage
 */
contract VVVETHStakingUnitFuzzTests is VVVETHStakingTestBase {
    // Sets up project and payment tokens, and an instance of the ETH staking contract
    function setUp() public {
        vm.startPrank(deployer, deployer);

        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        EthStakingInstance = new VVVETHStaking(address(AuthRegistry));
        VvvTokenInstance = new VVVToken(type(uint256).max, 0, address(AuthRegistry));

        //set auth registry permissions for ethStakingManager (ETH_STAKING_MANAGER_ROLE)
        AuthRegistry.grantRole(ethStakingManagerRole, ethStakingManager);
        bytes4 setDurationMultipliersSelector = EthStakingInstance.setDurationMultipliers.selector;
        bytes4 setNewStakesPermittedSelector = EthStakingInstance.setNewStakesPermitted.selector;
        bytes4 setVvvTokenSelector = EthStakingInstance.setVvvToken.selector;
        bytes4 withdrawEthSelector = EthStakingInstance.withdrawEth.selector;
        AuthRegistry.setPermission(
            address(EthStakingInstance),
            setDurationMultipliersSelector,
            ethStakingManagerRole
        );
        AuthRegistry.setPermission(
            address(EthStakingInstance),
            setNewStakesPermittedSelector,
            ethStakingManagerRole
        );
        AuthRegistry.setPermission(
            address(EthStakingInstance),
            setVvvTokenSelector,
            ethStakingManagerRole
        );
        AuthRegistry.setPermission(
            address(EthStakingInstance),
            withdrawEthSelector,
            ethStakingManagerRole
        );

        //mint 1,000,000 $VVV tokens to the staking contract
        VvvTokenInstance.mint(address(EthStakingInstance), 1_000_000 * 1e18);

        vm.deal(sampleUser, 10 ether);
        vm.stopPrank();

        //now that ethStakingManager has been granted the ETH_STAKING_MANAGER_ROLE, it can call setVvvToken and setNewStakesPermitted
        vm.startPrank(ethStakingManager, ethStakingManager);
        EthStakingInstance.setVvvToken(address(VvvTokenInstance));
        EthStakingInstance.setNewStakesPermitted(true);
        vm.stopPrank();
    }

    // Test that contract correctly stores the StakeData and stakeIds for any valid input combination
    function testFuzz_stakeEth(uint256 _callerKey, uint224 _stakeAmount, uint32 _duration) public {
        uint256 callerKey = bound(_callerKey, 1, 100000);
        address caller = vm.addr(callerKey);
        uint8 duration = uint8(bound(_duration, 0, 2));
        vm.assume(caller != address(0));
        vm.assume(_stakeAmount != 0);

        vm.deal(caller, _stakeAmount);
        vm.startPrank(caller, caller);

        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration(duration);
        uint256 stakeId = EthStakingInstance.stakeEth{ value: _stakeAmount }(stakeDuration);

        (
            uint224 stakedEthAmount,
            uint32 stakedTimestamp,
            bool stakeIsWithdrawn,
            VVVETHStaking.StakingDuration stakedDuration
        ) = EthStakingInstance.userStakes(caller, stakeId);

        assert(stakedEthAmount == _stakeAmount);
        assert(stakedTimestamp == block.timestamp);
        assert(stakeIsWithdrawn == false);
        assert(stakedDuration == stakeDuration);

        vm.stopPrank();
    }

    // test that contract correctly stores the StakeData and stakeIds for any restake
    function testFuzz_restakeEth(
        uint256 _callerKey,
        uint224 _stakeAmount,
        uint8 _duration,
        uint8 _newDuration
    ) public {
        uint256 callerKey = bound(_callerKey, 1, 100000);
        address caller = vm.addr(callerKey);
        uint8 duration = uint8(bound(_duration, 0, 2));
        uint8 newDuration = uint8(bound(_newDuration, 0, 2));
        vm.assume(caller != address(0));
        vm.assume(_stakeAmount != 0);

        vm.deal(caller, _stakeAmount);
        vm.startPrank(caller, caller);

        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration(duration);
        uint256 stakeId = EthStakingInstance.stakeEth{ value: _stakeAmount }(stakeDuration);

        // Advance time to allow for restaking
        advanceBlockNumberAndTimestampInSeconds(EthStakingInstance.durationToSeconds(stakeDuration) + 1);

        // Attempt to restake with a new duration
        VVVETHStaking.StakingDuration newStakeDuration = VVVETHStaking.StakingDuration(newDuration);
        uint256 newStakeId = EthStakingInstance.restakeEth(stakeId, newStakeDuration);

        // Verify the restake
        (
            uint224 restakedEthAmount,
            uint32 restakedTimestamp,
            bool restakeIsWithdrawn,
            VVVETHStaking.StakingDuration restakedDuration
        ) = EthStakingInstance.userStakes(caller, newStakeId);

        assert(restakedEthAmount == _stakeAmount);
        assert(restakedTimestamp >= block.timestamp);
        assert(restakeIsWithdrawn == false);
        assert(restakedDuration == newStakeDuration);

        vm.stopPrank();
    }

    // Test that any valid stake is withdrawable
    function testFuzz_withdrawStake(uint256 _callerKey, uint224 _stakeAmount, uint8 _duration) public {
        uint256 callerKey = bound(_callerKey, 1, 100000);
        address payable caller = payable(vm.addr(callerKey));
        uint8 duration = uint8(bound(_duration, 0, 2));
        vm.assume(caller != address(0));
        vm.assume(_stakeAmount != 0);
        vm.deal(caller, _stakeAmount);
        vm.startPrank(caller, caller);

        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration(duration);
        uint256 stakeId = EthStakingInstance.stakeEth{ value: _stakeAmount }(stakeDuration);

        advanceBlockNumberAndTimestampInSeconds(EthStakingInstance.durationToSeconds(stakeDuration) + 1);

        EthStakingInstance.withdrawStake(stakeId);

        (, , bool stakeIsWithdrawn, ) = EthStakingInstance.userStakes(caller, stakeId);

        assert(stakeIsWithdrawn == true);

        vm.stopPrank();
    }

    // Test that any amount < claimableVvv is claimable by the user after the stake duration elapses
    // also tests that the claimed + remaining claimable add up to originally claimable amount
    function testFuzz_claimVvv(
        uint256 _callerKey,
        uint224 _stakeAmount,
        uint8 _stakeDuration,
        uint256 _claimAmount
    ) public {
        uint256 callerKey = bound(_callerKey, 1, 100000);
        address caller = vm.addr(callerKey);
        uint8 stakeDuration = uint8(bound(_stakeDuration, 0, 2));
        vm.assume(caller != address(0));
        vm.assume(_stakeAmount != 0);
        vm.assume(_claimAmount != 0);
        uint256 stakeAmount = bound(_stakeAmount, 1, 100 ether);

        vm.deal(caller, _stakeAmount);
        vm.startPrank(caller, caller);

        VVVETHStaking.StakingDuration stakeDurationEnum = VVVETHStaking.StakingDuration(stakeDuration);
        EthStakingInstance.stakeEth{ value: stakeAmount }(stakeDurationEnum);

        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(stakeDurationEnum) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();

        // Ensure the claim amount is not more than what's available
        vm.assume(_claimAmount <= claimableVvv);

        uint256 vvvBalanceBefore = VvvTokenInstance.balanceOf(caller);
        EthStakingInstance.claimVvv(_claimAmount);
        uint256 vvvBalanceAfter = VvvTokenInstance.balanceOf(caller);

        uint256 claimableVvv2 = EthStakingInstance.calculateClaimableVvvAmount();

        assertTrue(vvvBalanceAfter == vvvBalanceBefore + _claimAmount);
        assertTrue(claimableVvv2 == claimableVvv - _claimAmount);

        vm.stopPrank();
    }
}
