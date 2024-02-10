//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
        VvvTokenInstance = new VVVToken(type(uint256).max, 0);
        EthStakingInstance = new VVVETHStaking(address(VvvTokenInstance), deployer);

        //mint 1,000,000 $VVV tokens to the staking contract
        VvvTokenInstance.mint(address(EthStakingInstance), 1_000_000 * 1e18);

        vm.deal(sampleUser, 10 ether);
        vm.stopPrank();
    }

    // Test that contract correctly stores the StakeData and stakeIds for any valid input combination
    function testFuzz_stakeEth(uint256 _callerKey, uint256 _stakeAmount, uint256 _duration) public {
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
            uint256 stakedEthAmount,
            uint256 stakedTimestamp,
            bool stakeIsWithdrawn,
            VVVETHStaking.StakingDuration stakedDuration
        ) = EthStakingInstance.userStakes(caller, stakeId);

        assert(stakedEthAmount == _stakeAmount);
        assert(stakedTimestamp == block.timestamp);
        assert(stakeIsWithdrawn == false);
        assert(stakedDuration == stakeDuration);

        vm.stopPrank();
    }

    // Test that any valid stake is withdrawable
    function testFuzz_withdrawStake(uint256 _callerKey, uint256 _stakeAmount, uint256 _duration) public {
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

    // Incoming Test Cases
    // function testFuzz_claimVvv() public {}
    // function testFuzz_calculateAccruedVvvAmount() public {}
    // function testFuzz_calculateClaimableVvvAmount() public {}
}
