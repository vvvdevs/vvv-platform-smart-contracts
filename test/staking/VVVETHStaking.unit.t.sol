//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVToken } from "contracts/tokens/VvvToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
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
        VvvTokenInstance = new VVVToken(type(uint256).max, 0);
        EthStakingInstance = new VVVETHStaking(deployer);
        EthStakingInstance.setVvvToken(address(VvvTokenInstance));

        //mint 1,000,000 $VVV tokens to the staking contract
        VvvTokenInstance.mint(address(EthStakingInstance), 1_000_000 * 1e18);

        vm.deal(sampleUser, 10 ether);
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

        //get user's latest userStakeIds index
        uint256[] memory stakeIds = EthStakingInstance.userStakeIds(sampleUser);
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

    // Tests that a user can stake multiple times, that StakeData is stored correctly, and that their stake Ids are stored correctly
    function testStakeEthMultiple() public {
        vm.startPrank(sampleUser, sampleUser);

        uint256[] memory stakeEthAmounts = new uint256[](3);
        stakeEthAmounts[0] = 1 ether;
        stakeEthAmounts[1] = 2 ether;
        stakeEthAmounts[2] = 3 ether;

        uint256 stakeIdBefore = EthStakingInstance.stakeId();
        EthStakingInstance.stakeEth{ value: stakeEthAmounts[0] }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );
        EthStakingInstance.stakeEth{ value: stakeEthAmounts[1] }(VVVETHStaking.StakingDuration.SixMonths);
        EthStakingInstance.stakeEth{ value: stakeEthAmounts[2] }(VVVETHStaking.StakingDuration.OneYear);
        uint256 stakeIdAfter = EthStakingInstance.stakeId();

        uint256[] memory stakeIds = EthStakingInstance.userStakeIds(sampleUser);

        assertTrue(stakeIdAfter == stakeIdBefore + stakeIds.length);
        assertTrue(stakeIds.length == stakeEthAmounts.length);

        for (uint256 i = 0; i < stakeIds.length; i++) {
            (
                uint256 stakedEthAmount,
                uint256 stakedTimestamp,
                bool stakeIsWithdrawn,
                VVVETHStaking.StakingDuration stakedDuration
            ) = EthStakingInstance.userStakes(sampleUser, stakeIds[i]);

            assertTrue(stakedEthAmount == stakeEthAmounts[i]);
            //this should only be true because the test is running in the same block
            assertTrue(stakedTimestamp == block.timestamp);
            assertTrue(stakeIsWithdrawn == false);
            //this should only be true because the StakingDuration assignment is consecutive above
            assertTrue(stakedDuration == VVVETHStaking.StakingDuration(i));
        }

        vm.stopPrank();
    }

    // Tests that a user cannot stake 0 ETH
    function testStakeZeroEth() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVETHStaking.CantStakeZeroEth.selector);
        EthStakingInstance.stakeEth{ value: 0 }(VVVETHStaking.StakingDuration.ThreeMonths);
        vm.stopPrank();
    }

    // Tests that a user cannot stake with a duration that is not ThreeMonths, SixMonths, or OneYear
    // This array has a max index of 2, so use 3 to test for invalid duration
    // Summons the "Conversion into non-existent enum type" error which afaik is a feature of >0.8.0
    function testInvalidStakingDuration() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        EthStakingInstance.stakeEth{ value: 1 ether }(VVVETHStaking.StakingDuration(uint(3)));
        vm.stopPrank();
    }

    // Testing of withdraw() function
    // Tests that a user can withdraw their stake after the duration has passed
    function testWithdraw() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 balanceBefore = address(sampleUser).balance;
        EthStakingInstance.withdrawStake(stakeId);
        uint256 balanceAfter = address(sampleUser).balance;

        //read the stake data after withdrawal
        (, , bool stakeIsWithdrawn, ) = EthStakingInstance.userStakes(sampleUser, stakeId);

        assertTrue(balanceAfter == balanceBefore + stakeEthAmount);
        assertTrue(stakeIsWithdrawn == true);
        vm.stopPrank();
    }

    // Tests that a user can withdraw multiple stakes in another order than they were staked
    function testWithdrawDifferentOrderMultiple() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 numStakes = 10;
        uint256 stakeAmount = 1 ether;
        uint256[] memory stakeEthAmounts = new uint256[](numStakes);
        for (uint256 i = 0; i < stakeEthAmounts.length; i++) {
            stakeEthAmounts[i] = stakeAmount;
            EthStakingInstance.stakeEth{ value: stakeEthAmounts[i] }(
                VVVETHStaking.StakingDuration.OneYear
            );
        }

        uint256[] memory stakeIds = EthStakingInstance.userStakeIds(sampleUser);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.OneYear) + 1
        );

        uint256 balanceBefore = address(sampleUser).balance;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 thisStakeIdIndex = stakeIds.length - 1 - i;
            EthStakingInstance.withdrawStake(stakeIds[thisStakeIdIndex]);
            (, , bool stakeIsWithdrawn, ) = EthStakingInstance.userStakes(
                sampleUser,
                stakeIds[thisStakeIdIndex]
            );
            assertTrue(stakeIsWithdrawn == true);
        }
        uint256 balanceAfter = address(sampleUser).balance;

        assertTrue(balanceAfter == balanceBefore + (stakeAmount * numStakes));
    }

    // Tests that a user cannot withdraw a stake that has already been withdrawn
    function testWithdrawAlreadyWithdrawn() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        EthStakingInstance.withdrawStake(stakeId);
        vm.expectRevert(VVVETHStaking.StakeIsWithdrawn.selector);
        EthStakingInstance.withdrawStake(stakeId);
        vm.stopPrank();
    }

    // Tests that a user cannot withdraw a stake before the duration has passed
    function testWithdrawBeforeDuration() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        //fast forward the staking duration to be 1 second short of the release timestamp
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths)
        );

        vm.expectRevert(VVVETHStaking.CantWithdrawBeforeStakeDuration.selector);
        EthStakingInstance.withdrawStake(stakeId);
        vm.stopPrank();
    }

    // Tests that a user cannot withdraw a stake that does not exist or is not theirs
    function testWithdrawInvalidStakeId() public {
        //attempt to withdraw stake of uninitialized StakeData
        //stakeId starts at 1, so 0 is invalid
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVETHStaking.InvalidStakeId.selector);
        EthStakingInstance.withdrawStake(0);
        vm.stopPrank();
    }

    // Tests that a user can stake ETH, withdraw the stake, then claim $VVV tokens
    // Claimed $VVV toknens should be equal to staked ETH * duration multiplier * exchange rate
    function testClaimVvv() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();

        uint256 vvvBalanceBefore = VvvTokenInstance.balanceOf(sampleUser);

        EthStakingInstance.claimVvv(claimableVvv);
        uint256 vvvBalanceAfter = VvvTokenInstance.balanceOf(sampleUser);

        uint256 expectedClaimedVvv = (stakeEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths)) /
            EthStakingInstance.DENOMINATOR();

        assertTrue(vvvBalanceAfter == vvvBalanceBefore + expectedClaimedVvv);
        vm.stopPrank();
    }

    // Tests that a user can stake ETH, withdraw the stake, then claim $VVV tokens afterwards
    function testClaimVvvAfterWithdrawStake() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();
        uint256 vvvBalanceBefore = VvvTokenInstance.balanceOf(sampleUser);

        EthStakingInstance.withdrawStake(stakeId);
        EthStakingInstance.claimVvv(claimableVvv);

        uint256 vvvBalanceAfter = VvvTokenInstance.balanceOf(sampleUser);

        uint256 expectedClaimedVvv = (stakeEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths)) /
            EthStakingInstance.DENOMINATOR();

        assertTrue(vvvBalanceAfter == vvvBalanceBefore + expectedClaimedVvv);
        vm.stopPrank();
    }

    // Tests that a user can stake ETH, claim $VVV, then withdraw the stake, then claim $VVV again, and that the two claims add up to the expected total
    function testClaimVvvBeforeAndAfterWithdrawStakeMultipleClaims() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakingDurationDivisor = 2;
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        //forward staking duration / stakingDurationDivisor
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) /
                stakingDurationDivisor
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();
        uint256 vvvBalanceBefore = VvvTokenInstance.balanceOf(sampleUser);

        EthStakingInstance.claimVvv(claimableVvv);

        //forward (staking duration / stakingDurationDivisor)  + 1 to release stake
        advanceBlockNumberAndTimestampInSeconds(
            (EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) /
                stakingDurationDivisor) + 1
        );

        EthStakingInstance.withdrawStake(stakeId);

        uint256 claimableVvv2 = EthStakingInstance.calculateClaimableVvvAmount();

        EthStakingInstance.claimVvv(claimableVvv2);

        uint256 vvvBalanceAfter = VvvTokenInstance.balanceOf(sampleUser);

        uint256 expectedClaimedVvv = (stakeEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths)) /
            EthStakingInstance.DENOMINATOR();

        assertTrue(vvvBalanceAfter == vvvBalanceBefore + expectedClaimedVvv);
        vm.stopPrank();
    }

    // Tests that a user cannot claim 0 $VVV
    // It's the first error to be checked in the contract, so no staking necessary
    function testClaimVvvZero() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVETHStaking.CantClaimZeroVvv.selector);
        EthStakingInstance.claimVvv(0);
        vm.stopPrank();
    }

    // Tests that a user cannot claim more $VVV than they have accrued
    function testClaimVvvInsufficient() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakingDurationDivisor = 2;
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);

        //forward staking duration / stakingDurationDivisor
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) /
                stakingDurationDivisor
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();

        vm.expectRevert(VVVETHStaking.InsufficientClaimableVvv.selector);
        EthStakingInstance.claimVvv(claimableVvv + 1);
    }

    // These are tested in the above tests as well, but I'm adding them here for showing explicit testing of these functions by name

    // Tests the calculation of the accrued $VVV amount
    function testCalculateAccruedVvvAmount() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakingDurationDivisor = 2;
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);

        //forward (staking duration / 2) + 1 --> half of the total-to-be-accrued is claimable at this point (not at only staking duration / 2)
        advanceBlockNumberAndTimestampInSeconds(
            (EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) /
                stakingDurationDivisor) + 1
        );

        uint256 accruedVvv = EthStakingInstance.calculateAccruedVvvAmount();

        uint256 expectedAccruedVvv = (stakeEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths)) /
            EthStakingInstance.DENOMINATOR() /
            stakingDurationDivisor;

        assertTrue(accruedVvv == expectedAccruedVvv);
        vm.stopPrank();
    }

    // Tests the calculation of the accrued $VVV amount for a single stake
    function testCalculateAccruedVvvAmountSingleStake() public {
        VVVETHStaking.StakeData memory stake = VVVETHStaking.StakeData({
            stakedEthAmount: 1 ether,
            stakeStartTimestamp: block.timestamp,
            stakeIsWithdrawn: false,
            stakeDuration: VVVETHStaking.StakingDuration.ThreeMonths
        });

        //forward staking duration + 1
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 expectedAccruedVvv = (stake.stakedEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths)) /
            EthStakingInstance.DENOMINATOR();

        uint256 accruedVvv = EthStakingInstance.calculateAccruedVvvAmount(stake);

        assertTrue(accruedVvv == expectedAccruedVvv);
    }

    // Tests that an empty stake array returns 0 accrued $VVV
    function testCalculateAccruedVvvAmountNoStakes() public {
        VVVETHStaking.StakeData memory stake;

        uint256 expectedAccruedVvv = 0;
        uint256 accruedVvv = EthStakingInstance.calculateAccruedVvvAmount(stake);

        assertTrue(accruedVvv == expectedAccruedVvv);
    }

    // Tests that the claimable $VVV amount is calculated correctly
    function testCalculateClaimableVvvAmount() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakingDurationDivisor = 3;
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.OneYear);

        //forward (staking duration / 2) + 1 --> half of the total-to-be-accrued is claimable at this point (not at only staking duration / 2)
        advanceBlockNumberAndTimestampInSeconds(
            (EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.OneYear) /
                stakingDurationDivisor) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();

        EthStakingInstance.claimVvv(claimableVvv);

        //forward past end of staking duration, user forgets about this for a while lol
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.OneYear)
        );

        uint256 claimableVvv2 = EthStakingInstance.calculateClaimableVvvAmount();

        uint256 expectedClaimableVvv = (stakeEthAmount *
            EthStakingInstance.ethToVvvExchangeRate() *
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.OneYear)) /
            EthStakingInstance.DENOMINATOR();

        assertTrue(claimableVvv + claimableVvv2 == expectedClaimableVvv);
        vm.stopPrank();
    }

    // Testing admin functions

    // Test that the owner can properly set the duration multipliers
    function testSetDurationMultiplier() public {
        vm.startPrank(deployer, deployer);
        VVVETHStaking.StakingDuration[] memory durations = new VVVETHStaking.StakingDuration[](3);
        durations[0] = VVVETHStaking.StakingDuration.ThreeMonths;
        durations[1] = VVVETHStaking.StakingDuration.SixMonths;
        durations[2] = VVVETHStaking.StakingDuration.OneYear;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 20_000;
        multipliers[1] = 27_000;
        multipliers[2] = 33_000;

        EthStakingInstance.setDurationMultiplier(durations, multipliers);

        assertTrue(
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.ThreeMonths) == 20_000
        );
        assertTrue(
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.SixMonths) == 27_000
        );
        assertTrue(
            EthStakingInstance.durationToMultiplier(VVVETHStaking.StakingDuration.OneYear) == 33_000
        );
    }

    // Test that the owner can properly set the VvvToken address
    function testSetVvvToken() public {
        vm.startPrank(deployer, deployer);
        VVVToken newVvvToken = new VVVToken(type(uint256).max, 0);
        EthStakingInstance.setVvvToken(address(newVvvToken));
        assertTrue(address(EthStakingInstance.vvvToken()) == address(newVvvToken));
        vm.stopPrank();
    }

    //test that even though the user has accrued $VVV, that they can't claim it without the VvvToken address being set
    function testCantWithdrawWithoutVvvAddressSet() public {
        vm.startPrank(deployer, deployer);
        EthStakingInstance.setVvvToken(address(0));
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();

        //should revert because trying to transfer tokens from address(0), which indicates token address is not yet set (pre-TGE)
        vm.expectRevert();
        EthStakingInstance.claimVvv(claimableVvv);

        vm.stopPrank();
    }
}
