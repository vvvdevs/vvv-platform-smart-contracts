//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
        EthStakingInstance = new VVVETHStaking();
        vm.deal(sampleUser, 10 ether);
        vm.stopPrank();
    }

    // Test that contract correctly stores the StakeData and stakeIds for any valid input combination
    function testFuzz_stakeEth(address _caller, uint256 _stakeAmount, uint256 _duration) public {
        uint8 duration = uint8(bound(_duration, 0, 2));
        vm.assume(_caller != address(0));
        vm.assume(_stakeAmount != 0);

        vm.deal(_caller, _stakeAmount);
        vm.startPrank(_caller, _caller);

        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration(duration);
        uint256 stakeId = EthStakingInstance.stakeEth{ value: _stakeAmount }(stakeDuration);

        (
            uint256 stakedEthAmount,
            uint256 stakedTimestamp,
            bool stakeIsWithdrawn,
            VVVETHStaking.StakingDuration stakedDuration
        ) = EthStakingInstance.userStakes(_caller, stakeId);

        assert(stakedEthAmount == _stakeAmount);
        assert(stakedTimestamp == block.timestamp);
        assert(stakeIsWithdrawn == false);
        assert(stakedDuration == stakeDuration);

        vm.stopPrank();
    }

    // Test that any valid stake is withdrawable
    function testFuzz_withdrawStake(address _caller, uint256 _stakeAmount, uint256 _duration) public {
        address payable caller = payable(_caller);
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
}
