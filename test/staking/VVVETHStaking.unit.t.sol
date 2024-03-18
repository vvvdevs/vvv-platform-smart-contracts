//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVToken } from "contracts/tokens/VvvToken.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
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
        EthStakingInstance.stakeEth{ value: 1 ether }(VVVETHStaking.StakingDuration(uint8(3)));
        vm.stopPrank();
    }

    // tests that a user cannot stake when newStakesPermitted is false
    function testStakeWhenNewStakesPermittedFalse() public {
        vm.startPrank(ethStakingManager, ethStakingManager);
        EthStakingInstance.setNewStakesPermitted(false);
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVETHStaking.NewStakesNotPermitted.selector);
        EthStakingInstance.stakeEth{ value: 1 ether }(VVVETHStaking.StakingDuration.ThreeMonths);
        vm.stopPrank();
    }

    // Testing of restakeEth() function
    // Tests that a user can restake their ETH
    function testRestakeETH() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        // restake
        VVVETHStaking.StakingDuration restakeDuration = VVVETHStaking.StakingDuration.SixMonths;
        uint256 restakeId = EthStakingInstance.restakeEth(stakeId, restakeDuration);
        vm.stopPrank();

        (uint256 stakedEthAmount, , bool stakeIsWithdrawn, ) = EthStakingInstance.userStakes(
            sampleUser,
            stakeId
        );
        (
            uint256 restakedEthAmount,
            uint256 restakeStartTimestamp,
            bool restakeIsWithdrawn,
            VVVETHStaking.StakingDuration restakeDurationRead
        ) = EthStakingInstance.userStakes(sampleUser, restakeId);

        assertTrue(restakeId == stakeId + 1);
        assertTrue(stakedEthAmount == restakedEthAmount);
        assertTrue(restakeStartTimestamp == block.timestamp);
        assertTrue(stakeIsWithdrawn == true);
        assertTrue(restakeIsWithdrawn == false);
        assertTrue(restakeDuration == restakeDurationRead);
    }

    // Tests that a user can withdraw their new stake (from restakeETH() call) when the new duration has passed
    function testUserCanWithdrawRestake() public {
        //restake
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        // restake
        VVVETHStaking.StakingDuration restakeDuration = VVVETHStaking.StakingDuration.SixMonths;
        uint256 restakeId = EthStakingInstance.restakeEth(stakeId, restakeDuration);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(EthStakingInstance.durationToSeconds(restakeDuration) + 1);

        uint256 balanceBefore = address(sampleUser).balance;
        EthStakingInstance.withdrawStake(restakeId);
        uint256 balanceAfter = address(sampleUser).balance;

        vm.stopPrank();

        assertTrue(balanceAfter == balanceBefore + stakeEthAmount);
    }

    // Tests that a user cannot restake before the first stake duration has passed
    function testUserCannotRestakeBeforePreviousStakeIsComplete() public {
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
        EthStakingInstance.restakeEth(stakeId, VVVETHStaking.StakingDuration.SixMonths);
        vm.stopPrank();
    }

    // Tests that a user cannot restake on behalf of another user
    function testUserCannotRestakeForAnotherUser() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        //fast forward the staking duration to be 1 second short of the release timestamp
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );
        vm.stopPrank();

        vm.startPrank(ethStakingManager, ethStakingManager);
        //will revert because deployer does not have a stake with the given stakeId, which will yield an empty StakeData which trigger the InvalidStakeId error
        vm.expectRevert(VVVETHStaking.InvalidStakeId.selector);
        EthStakingInstance.restakeEth(stakeId, VVVETHStaking.StakingDuration.SixMonths);
        vm.stopPrank();
    }

    // Tests that a user cannot withdraw the previous stake after restaking
    function testUserCannotWithdrawPreviousStakeAfterRestake() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        // restake
        VVVETHStaking.StakingDuration restakeDuration = VVVETHStaking.StakingDuration.SixMonths;
        EthStakingInstance.restakeEth(stakeId, restakeDuration);

        // attempt to withdraw previous stake
        vm.expectRevert(VVVETHStaking.StakeIsWithdrawn.selector);
        EthStakingInstance.withdrawStake(stakeId);

        vm.stopPrank();
    }

    // Tests that a user cannot withdraw a restaked stake before the new duration has passed
    function testUserCannotWithdrawRestakeBeforeDuration() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakeEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        // restake
        VVVETHStaking.StakingDuration restakeDuration = VVVETHStaking.StakingDuration.SixMonths;
        uint256 restakeId = EthStakingInstance.restakeEth(stakeId, restakeDuration);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(EthStakingInstance.durationToSeconds(restakeDuration) - 1);

        // attempt to withdraw previous stake
        vm.expectRevert(VVVETHStaking.CantWithdrawBeforeStakeDuration.selector);
        EthStakingInstance.withdrawStake(restakeId);

        vm.stopPrank();
    }

    // tests that a user cannot restake when newStakesPermitted is false
    function testRestakeWhenNewStakesPermittedFalse() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration.OneYear;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(stakeDuration);
        // forward to first timestamp with released stake, which would allow restaking
        advanceBlockNumberAndTimestampInSeconds(EthStakingInstance.durationToSeconds(stakeDuration) + 1);
        vm.stopPrank();

        vm.startPrank(ethStakingManager, ethStakingManager);
        EthStakingInstance.setNewStakesPermitted(false);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVETHStaking.NewStakesNotPermitted.selector);
        EthStakingInstance.stakeEth{ value: 1 ether }(VVVETHStaking.StakingDuration.ThreeMonths);

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
    // Claimed $VVV tokens should be equal to staked ETH * duration multiplier * exchange rate
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
        vm.stopPrank();
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
            stakedEthAmount: uint224(1 ether),
            stakeStartTimestamp: uint32(block.timestamp),
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

    // Test that the admin (ethStakingManager) can properly set the duration multipliers
    function testsetDurationMultipliers() public {
        vm.startPrank(ethStakingManager, ethStakingManager);
        VVVETHStaking.StakingDuration[] memory durations = new VVVETHStaking.StakingDuration[](3);
        durations[0] = VVVETHStaking.StakingDuration.ThreeMonths;
        durations[1] = VVVETHStaking.StakingDuration.SixMonths;
        durations[2] = VVVETHStaking.StakingDuration.OneYear;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 20_000;
        multipliers[1] = 27_000;
        multipliers[2] = 33_000;

        EthStakingInstance.setDurationMultipliers(durations, multipliers);

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

    // test that addresses other than admin (ethStakingManager) cannot set the duration multipliers
    function testsetDurationMultipliersNotAdmin() public {
        vm.startPrank(sampleUser, sampleUser);

        VVVETHStaking.StakingDuration[] memory durations = new VVVETHStaking.StakingDuration[](3);
        durations[0] = VVVETHStaking.StakingDuration.ThreeMonths;
        durations[1] = VVVETHStaking.StakingDuration.SixMonths;
        durations[2] = VVVETHStaking.StakingDuration.OneYear;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 20_000;
        multipliers[1] = 27_000;
        multipliers[2] = 33_000;

        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        EthStakingInstance.setDurationMultipliers(durations, multipliers);
        vm.stopPrank();
    }

    // Test that the admin (ethStakingManager) can properly set the VvvToken address
    function testSetVvvToken() public {
        vm.startPrank(ethStakingManager, ethStakingManager);
        VVVToken newVvvToken = new VVVToken(type(uint256).max, 0, address(AuthRegistry));
        EthStakingInstance.setVvvToken(address(newVvvToken));
        assertTrue(address(EthStakingInstance.vvvToken()) == address(newVvvToken));
        vm.stopPrank();
    }

    // Test that addresses other than ethStakingManager cannot set the VvvToken address
    function testSetVvvTokenNotAdmin() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        EthStakingInstance.setVvvToken(address(0));
        vm.stopPrank();
    }

    //test that even though the user has accrued $VVV, that they can't claim it without the VvvToken address being set
    function testCantClaimVvvWithoutVvvAddressSet() public {
        vm.startPrank(ethStakingManager, ethStakingManager);
        EthStakingInstance.setVvvToken(address(0));
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);

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

    // tests that the EtherReceived event is emitted when the receive function is called
    function testEmitEtherReceived() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.deal(sampleUser, 1 ether);

        vm.expectEmit(address(EthStakingInstance));
        emit VVVETHStaking.EtherReceived();
        (bool success, ) = address(EthStakingInstance).call{ value: 1 ether }("");
        assertTrue(success);

        vm.stopPrank();
    }

    // Tests that admin (ethStakingManager) can withdraw eth that was sent by staker
    function testWithdrawStakedEth() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakeEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);
        vm.stopPrank();

        uint256 contractBalanceBefore = address(EthStakingInstance).balance;
        uint256 userBalanceBefore = address(ethStakingManager).balance;

        vm.startPrank(ethStakingManager, ethStakingManager);
        EthStakingInstance.withdrawEth(stakeEthAmount);
        vm.stopPrank();

        uint256 contractBalanceAfter = address(EthStakingInstance).balance;
        uint256 userBalanceAfter = address(ethStakingManager).balance;

        assertTrue(contractBalanceAfter == contractBalanceBefore - stakeEthAmount);
        assertTrue(userBalanceAfter == userBalanceBefore + stakeEthAmount);
    }

    // Tests that addresses other than admin (ethStakingManager) cannot withdraw eth that was sent by staker
    function testWithdrawStakedEthNotAdmin() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        EthStakingInstance.withdrawEth(1 ether);
        vm.stopPrank();
    }

    // Tests that the Stake event is emitted correctly on new stakes
    function testEmitStakeNewStake() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeId = 1;
        uint256 stakedEthAmount = 1 ether;
        uint256 stakeStartTimestamp = block.timestamp;
        VVVETHStaking.StakingDuration stakedDuration = VVVETHStaking.StakingDuration.ThreeMonths;
        vm.expectEmit(address(EthStakingInstance));
        emit VVVETHStaking.Stake(
            sampleUser,
            stakeId,
            uint224(stakedEthAmount),
            uint32(stakeStartTimestamp),
            stakedDuration
        );
        EthStakingInstance.stakeEth{ value: 1 ether }(VVVETHStaking.StakingDuration.ThreeMonths);
        vm.stopPrank();
    }

    // Tests that the Stake event is emitted correctly on restakes
    function testEmitStakeRestake() public {
        vm.startPrank(sampleUser, sampleUser);
        uint256 stakeId = 1;
        uint256 restakeId = stakeId + 1;
        uint256 stakedEthAmount = 1 ether;
        VVVETHStaking.StakingDuration stakeDuration = VVVETHStaking.StakingDuration.ThreeMonths;
        EthStakingInstance.stakeEth{ value: 1 ether }(stakeDuration);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );
        uint256 restakeStartTimestamp = block.timestamp;

        vm.expectEmit(address(EthStakingInstance));
        emit VVVETHStaking.Stake(
            sampleUser,
            restakeId,
            uint224(stakedEthAmount),
            uint32(restakeStartTimestamp),
            stakeDuration
        );
        EthStakingInstance.restakeEth(stakeId, VVVETHStaking.StakingDuration.ThreeMonths);

        vm.stopPrank();
    }

    // Tests that the Withdraw event is emitted correctly on withdrawal of stake
    function testEmitWithdrawStake() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.deal(sampleUser, 1 ether);
        uint256 stakedEthAmount = 1 ether;
        uint256 stakeStartTimestamp = 1; //start time of the stake
        uint256 stakeId = EthStakingInstance.stakeEth{ value: stakedEthAmount }(
            VVVETHStaking.StakingDuration.ThreeMonths
        );

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        vm.expectEmit(address(EthStakingInstance));
        emit VVVETHStaking.Withdraw(
            sampleUser,
            stakeId,
            uint224(stakedEthAmount),
            uint32(stakeStartTimestamp),
            VVVETHStaking.StakingDuration.ThreeMonths
        );
        EthStakingInstance.withdrawStake(stakeId);
        vm.stopPrank();
    }

    // Tests that the VvvClaim event is emitted correctly on claim of $VVV
    function testEmitVvvClaim() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.deal(sampleUser, 1 ether);
        uint256 stakedEthAmount = 1 ether;
        EthStakingInstance.stakeEth{ value: stakedEthAmount }(VVVETHStaking.StakingDuration.ThreeMonths);

        // forward to first timestamp with released stake
        advanceBlockNumberAndTimestampInSeconds(
            EthStakingInstance.durationToSeconds(VVVETHStaking.StakingDuration.ThreeMonths) + 1
        );

        uint256 claimableVvv = EthStakingInstance.calculateClaimableVvvAmount();
        vm.expectEmit(address(EthStakingInstance));
        emit VVVETHStaking.VvvClaim(sampleUser, claimableVvv);
        EthStakingInstance.claimVvv(claimableVvv);
    }
}
