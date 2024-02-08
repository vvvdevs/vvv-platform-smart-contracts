//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVETHStakingTestBase } from "test/staking/VVVETHStakingTestBase.sol";
import { VVVETHStaking } from "contracts/staking/VVVETHStaking.sol";

/**
 * @title VVVETHStaking Unit Tests
 * @dev use "forge test --match-contract VVVETHStakingUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVETHStaking" to run coverage
 */
contract VVVETHStakingUnitTests is VVVETHStakingTestBase {
    // Sets up project and payment tokens, and an instance of the ETH staking contract
    function setUp() public {
        vm.startPrank(deployer, deployer);
        EthStakingInstance = new VVVETHStaking();
        generateUserAddressListAndDealEther();
        vm.stopPrank();
    }

    // Tests deployment of VVVETHStaking
    function testDeployment() public {
        assertTrue(address(EthStakingInstance) != address(0));
    }

    // Test that durationToSeconds mappping is correctly populated
    // ThreeMonths --> 90 days, and so on...
    function testInitialization() public {
        assertTrue(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) == 90 days
        );
        assertTrue(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.SixMonths) == 180 days
        );
        assertTrue(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.OneYear) == 360 days
        );
    }

    // Testing of stakeEth() function
    // Tests staking ETH, if stakeId is incremented, if the user's stake Ids are stored correctly,
    // and if the StakeData is stored correctly
    function testStakeEth() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeIdBefore = EthStakingInstance.stakeId();
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.OneYear);
        uint256 stakeIdAfter = EthStakingInstance.stakeId();

        //get user's stakeIds
        uint256[] memory stakeIds = EthStakingInstance.userStakeIds(sampleUser);

        //index latest stakeId (length - 1)
        uint256 userStakeIdIndex = stakeIds.length - 1;

        //it's known I can use stakeIds[userStakeIdIndex] because the user has only staked once
        (
            uint256 stakedEthAmount,
            uint256 stakedTimestamp,
            bool stakeIsWithdrawn,
            VVVETHStaking.StakingDuration stakedDuration
        ) = EthStakingInstance.userStakes(sampleUser, stakeIds[userStakeIdIndex]);

        assertTrue(stakeIdAfter == stakeIdBefore + 1);
        assertTrue(stakeIds.length == 1);
        assertTrue(stakeIds[userStakeIdIndex] == stakeIdAfter);
        assertTrue(stakedEthAmount == stakeEthAmount);
        assertTrue(stakedTimestamp == block.timestamp);
        assertTrue(stakeIsWithdrawn == false);
        assertTrue(stakedDuration == VVVETHStaking.StakingDuration.OneYear);
        vm.stopPrank();
    }

    // // Tests that a user can stake multiple times, that StakeData is stored correctly, and that their stake Ids are stored correctly
    // function testStakeEthMultiple() public {}
    // function testFailStakeZeroEth() public {}
    // function testFailInvalidStakingDuration() public {}

    // // Testing of withdraw() function
    // // Tests that a user can withdraw their stake after the duration has passed
    // function testWithdraw() public {}
    // function testWithdrawRandomOrderMultiple() public {}
    // function testFailAlreadyWithdrawn() public {}
    // function testFailWithdrawBeforeDuration() public {}
    // function testFailInvalidStakeId() public {}
    // function testFailWithdrawFailed() public {}
}
