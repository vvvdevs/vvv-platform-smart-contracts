//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
import { VVVNodes } from "contracts/nodes/VVVNodes.sol";
import { VVVNodesTestBase } from "./VVVNodesTestBase.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";

contract VVVNodesUnitTest is VVVNodesTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        NodesInstance = new VVVNodes(address(AuthRegistry), activationThreshold);
        vm.stopPrank();
    }

    function testDeployment() public {
        assertNotEq(address(NodesInstance), address(0));
    }

    //tests that mint works
    function testMint() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser);
        vm.stopPrank();
        assertEq(NodesInstance.balanceOf(sampleUser), 1);
    }

    //tests setting tokenURI for a tokenId
    function testSetTokenURI() public {
        vm.startPrank(deployer, deployer);
        NodesInstance.mint(deployer);
        vm.stopPrank();
        vm.startPrank(deployer, deployer);
        NodesInstance.setTokenURI(1, "https://example.com/token/1");
        vm.stopPrank();
        assertEq(NodesInstance.tokenURI(1), "https://example.com/token/1");
    }

    //tests that an admin cannot set the tokenURI
    function testNonAdminCannotSetTokenURI() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(deployer);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.setTokenURI(1, "https://example.com/token/1");
        vm.stopPrank();
    }

    //tests that a node owner can stake $VVV via their node s.t. the node is activated
    function testStakeActivate() public {
        vm.deal(sampleUser, activationThreshold);

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold }(1);
        vm.stopPrank();

        bool isActive = NodesInstance.isNodeActive(1);
        (, , , , uint256 stakedAmount) = NodesInstance.tokenData(1);
        assertTrue(isActive);
        assertEq(stakedAmount, activationThreshold);
        assertEq(address(NodesInstance).balance, activationThreshold);
    }

    //tests that a node owner can stake sub-activation threshold amount
    function testStakeSubActivationThreshold() public {
        vm.deal(sampleUser, activationThreshold);

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold - 1 }(1);
        vm.stopPrank();

        bool isActive = NodesInstance.isNodeActive(1);
        assertFalse(isActive);
    }

    //tests that an attempt to stake 0 $VVV will revert
    function testStakeZeroMsgValue() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        vm.expectRevert(VVVNodes.ZeroTokenTransfer.selector);
        NodesInstance.stake{ value: 0 }(1);
        vm.stopPrank();
    }

    //test that a user's attempt to stake in an unowned node reverts
    function testStakeUnownedToken() public {
        vm.deal(sampleUser, activationThreshold);

        vm.startPrank(deployer, deployer);
        NodesInstance.mint(deployer); //mints tokenId 1
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 2
        vm.expectRevert(VVVNodes.CallerIsNotTokenOwner.selector);
        NodesInstance.stake{ value: activationThreshold }(1);
        vm.stopPrank();
    }

    //tests that a node owner can unstake $VVV via their node
    function testUnstake() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold }(tokenId);

        bool isActiveBeforeUnstake = NodesInstance.isNodeActive(tokenId);

        uint256 userBalanceBeforeUnstake = sampleUser.balance;
        NodesInstance.unstake(tokenId, activationThreshold);
        vm.stopPrank();

        bool isActiveAfterUnstake = NodesInstance.isNodeActive(tokenId);

        //the node is active after staking and inactive after unstaking
        assertTrue(isActiveBeforeUnstake);
        assertFalse(isActiveAfterUnstake);

        //the same staked amount is now back in the user's wallet + some dust due to 1s of vesting
        assertGt(sampleUser.balance, userBalanceBeforeUnstake);
    }

    //test that a user's attempt to unstake from an unowned node reverts
    function testUnstakeUnownedToken() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold }(tokenId);
        vm.stopPrank();

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVNodes.CallerIsNotTokenOwner.selector);
        NodesInstance.unstake(tokenId, activationThreshold);
        vm.stopPrank();
    }

    //tests that unstaking s.t. the node is below the activation threshold triggers the actions associated with deactivation
    function testUnstakeDeactivatesNode() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold }(tokenId);

        //full unvested amount
        (
            uint256 unvestedAmountPreDeactivation,
            uint256 vestingSince,
            ,
            uint256 amountToVestPerSecond,

        ) = NodesInstance.tokenData(tokenId);

        //advance enough to accrue some vested tokens
        advanceBlockNumberAndTimestampInSeconds(2 weeks);

        //unstaking 1 token should deactivate the node
        NodesInstance.unstake(tokenId, 1);
        vm.stopPrank();

        //post-deactivation unvested amount is slightly less, the difference has become claimable
        (uint256 unvestedAmountPostDeactivation, , uint256 claimableAmount, , ) = NodesInstance.tokenData(
            tokenId
        );

        uint256 expectedVestedAmount = (block.timestamp - vestingSince) * amountToVestPerSecond; //2 weeks of vesting

        //change in unvested amount is same as amount made claimable during deactivation
        assertEq(unvestedAmountPreDeactivation - unvestedAmountPostDeactivation, claimableAmount);

        //assert that the claimable amount is the amount expected to be vested after 2 weeks
        assertEq(expectedVestedAmount, claimableAmount);
    }

    //tests claim, entire amount accrued during vesting period should be claimable by a user. utilizes placeholder logic in mint() to set TokenData
    function testClaim() public {
        vm.deal(sampleUser, activationThreshold);
        vm.deal(address(NodesInstance), type(uint128).max);

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints token of ID 1
        uint256 userTokenId = 1;

        //sample vesting setup assuming 1 token/second for 2 years
        uint256 vestingDuration = 63_113_904; //2 years
        uint256 refTotalVestedTokens = vestingDuration * 1e18;

        //check pre-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPreClaim, , , , ) = NodesInstance.tokenData(userTokenId);

        //stake the activation threshold to activate the node
        NodesInstance.stake{ value: activationThreshold }(userTokenId);

        advanceBlockNumberAndTimestampInSeconds(vestingDuration * 2);

        NodesInstance.claim(userTokenId);

        //check post-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPostClaim, , , , ) = NodesInstance.tokenData(userTokenId);
        uint256 balancePostClaim = sampleUser.balance;
        vm.stopPrank();

        assertEq(unvestedAmountPreClaim, refTotalVestedTokens);
        assertEq(unvestedAmountPostClaim, 0);
        assertEq(refTotalVestedTokens, balancePostClaim);
    }

    //tests claim with a tokenId that is not owned by the caller
    function testClaimNotOwned() public {
        vm.deal(sampleUser, activationThreshold);
        vm.deal(address(NodesInstance), type(uint128).max);

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints token of ID 1
        uint256 userTokenId = 1;

        //sample vesting setup assuming 1 token/second for 2 years
        uint256 vestingDuration = 63_113_904; //2 years

        //stake the activation threshold to activate the node
        NodesInstance.stake{ value: activationThreshold }(userTokenId);
        vm.stopPrank();

        advanceBlockNumberAndTimestampInSeconds(vestingDuration * 2);

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVNodes.CallerIsNotTokenOwner.selector);
        NodesInstance.claim(userTokenId);
        vm.stopPrank();
    }

    //tests claim of zero $VVV (can't be defined as a claim amount, but if a user claims with a token they own the instant after activating, this error will be thrown)
    function testClaimZero() public {
        vm.deal(sampleUser, activationThreshold);
        vm.deal(address(NodesInstance), type(uint128).max);

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints token of ID 1
        uint256 userTokenId = 1;

        //stake the activation threshold to activate the node
        NodesInstance.stake{ value: activationThreshold }(userTokenId);

        vm.expectRevert(VVVNodes.NoClaimableTokens.selector);
        NodesInstance.claim(userTokenId);
        vm.stopPrank();
    }

    //tests that a view function can output whether a token of tokenId is active
    function testCheckNodeIsActive() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        NodesInstance.stake{ value: activationThreshold }(tokenId);
        vm.stopPrank();

        assertTrue(NodesInstance.isNodeActive(tokenId));
    }

    //tests that minting works, but transfers do not when tokens are soulbound
    function testTransferFailsWhenSoulbound() public {
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1

        vm.expectRevert(VVVNodes.NodesAreSoulbound.selector);
        NodesInstance.transferFrom(sampleUser, deployer, tokenId);
        vm.stopPrank();
    }

    //tests that after setting soulbound=false, transfers work normally
    function testTransferSucceedsAfterSoulboundSetToFalse() public {
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        vm.expectRevert(VVVNodes.NodesAreSoulbound.selector);
        NodesInstance.transferFrom(sampleUser, deployer, tokenId);
        vm.stopPrank();

        vm.startPrank(deployer, deployer);
        NodesInstance.setSoulbound(false);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.transferFrom(sampleUser, deployer, tokenId);
        vm.stopPrank();

        assertEq(NodesInstance.balanceOf(deployer), 1);
    }

    //tests that an admin can set activationThreshold
    function testSetActivationThreshold() public {
        uint256 currentActivationThreshold = NodesInstance.activationThreshold();
        uint256 newActivationThreshold = currentActivationThreshold + 1;

        vm.startPrank(deployer, deployer);
        NodesInstance.setActivationThreshold(newActivationThreshold);
        vm.stopPrank();
        assertEq(NodesInstance.activationThreshold(), newActivationThreshold);
    }

    //tests that a non-admin cannot set activation threshold
    function testNonAdminCannotSetActivationThreshold() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.setActivationThreshold(activationThreshold + 1);
        vm.stopPrank();
    }

    //tests that an active node becomes inactive when an admin increases activationThreshold
    function testNodeInactivationOnThresholdIncrease() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        bool isActiveBeforeStake = NodesInstance.isNodeActive(tokenId);
        NodesInstance.stake{ value: activationThreshold }(tokenId);
        bool isActiveAfterStake = NodesInstance.isNodeActive(tokenId);
        vm.stopPrank();

        vm.startPrank(deployer, deployer);
        NodesInstance.setActivationThreshold(activationThreshold + 1);
        vm.stopPrank();

        bool isActiveAfterThresholdChange = NodesInstance.isNodeActive(tokenId);

        assertFalse(isActiveBeforeStake);
        assertTrue(isActiveAfterStake);
        assertFalse(isActiveAfterThresholdChange);
    }

    //tests that a threshold decrease which would activate a previously inactive node
    function testNodeActivationOnThresholdDecrease() public {
        vm.deal(sampleUser, activationThreshold);
        uint256 tokenId = 1;
        uint256 newThreshold = activationThreshold - 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        bool isActiveBeforeStake = NodesInstance.isNodeActive(tokenId);

        //stake one less than the activation threshold so the node does not activate
        NodesInstance.stake{ value: newThreshold }(tokenId);
        bool isActiveAfterStake = NodesInstance.isNodeActive(tokenId);
        vm.stopPrank();

        vm.startPrank(deployer, deployer);
        NodesInstance.setActivationThreshold(newThreshold);
        vm.stopPrank();

        bool isActiveAfterThresholdChange = NodesInstance.isNodeActive(tokenId);

        assertFalse(isActiveBeforeStake);
        assertFalse(isActiveAfterStake);
        assertTrue(isActiveAfterThresholdChange);
    }

    //tests that a defined gas limit is not exceeded when calling setActivationThreshold in the worst possible conditions
    function testGasConsumedBySetActivationThreshold() public {
        uint256 vestingDuration = 63_113_904; //2 years
        uint256 totalGasLimit = type(uint256).max;
        vm.deal(sampleUser, type(uint256).max);

        //mint 5000 nodes
        uint256 nodesToMint = 5000;
        for (uint256 i = 0; i < nodesToMint; i++) {
            NodesInstance.mint(sampleUser);
        }

        //activate all nodes
        vm.startPrank(sampleUser);
        for (uint256 i = 0; i < nodesToMint; i++) {
            NodesInstance.stake{ value: activationThreshold }(i + 1);
        }
        vm.stopPrank();

        //wait for all tokens to vest
        advanceBlockNumberAndTimestampInSeconds(vestingDuration * 2);

        vm.startPrank(deployer, deployer);
        uint256 gasLeftBeforeThresholdChange = gasleft();
        NodesInstance.setActivationThreshold(type(uint256).max);
        uint256 gasLeftAfterThresholdChange = gasleft();
        vm.stopPrank();

        uint256 gasUsed = gasLeftBeforeThresholdChange - gasLeftAfterThresholdChange;
        uint256 gasUsedPerNode = gasUsed / nodesToMint;

        assertLt(gasUsed, totalGasLimit);
    }

    //tests that an admin can set maxLaunchpadStakeAmount
    function testSetMaxLaunchpadStakeAmount() public {
        uint256 currentMaxLaunchpadStakeAmount = NodesInstance.maxLaunchpadStakeAmount();
        uint256 newMaxLaunchpadStakeAmount = currentMaxLaunchpadStakeAmount + 1;

        vm.startPrank(deployer, deployer);
        NodesInstance.setMaxLaunchpadStakeAmount(newMaxLaunchpadStakeAmount);
        vm.stopPrank();
        assertEq(NodesInstance.maxLaunchpadStakeAmount(), newMaxLaunchpadStakeAmount);
    }

    //tests that a non-admin cannot set maxLaunchpadStakeAmount
    function testNonAdminCannotSetMaxLaunchpadStakeAmount() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.setMaxLaunchpadStakeAmount(activationThreshold + 1);
        vm.stopPrank();
    }

    //tests that an admin can set soulbound
    function testSetSoulbound() public {
        bool currentSoulbound = NodesInstance.soulbound();
        bool newSoulbound = !currentSoulbound;

        vm.startPrank(deployer, deployer);
        NodesInstance.setSoulbound(newSoulbound);
        vm.stopPrank();
        assertEq(NodesInstance.soulbound(), newSoulbound);
    }

    //tests that a non-admin cannot set soulbound
    function testNonAdminCannotSetSoulbound() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.setSoulbound(true);
        vm.stopPrank();
    }

    //tests that an admin can set transactionProcessingReward
    function testSetTransactionProcessingReward() public {
        uint256 currentTransactionProcessingReward = NodesInstance.transactionProcessingReward();
        uint256 newTransactionProcessingReward = currentTransactionProcessingReward + 1;

        vm.startPrank(deployer, deployer);
        NodesInstance.setTransactionProcessingReward(newTransactionProcessingReward);
        vm.stopPrank();
        assertEq(NodesInstance.transactionProcessingReward(), newTransactionProcessingReward);
    }

    //tests than a non-admin cannot set transactionProcessingReward
    function testNonAdminCannotSetTransactionProcessingReward() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.setTransactionProcessingReward(1);
        vm.stopPrank();
    }

    //tests that an admin can withdraw $VVV from the contract
    function testWithdrawVVVVNative() public {
        uint256 amountToWithdraw = 100 * 1e18;
        vm.deal(address(NodesInstance), amountToWithdraw);

        vm.startPrank(deployer, deployer);
        NodesInstance.withdraw(amountToWithdraw);
        vm.stopPrank();

        assertEq(address(NodesInstance).balance, 0);
    }

    //tests that a non-admin cannot withdraw $VVV
    function testNonAdminCannotWithdrawVVV() public {
        uint256 amountToWithdraw = 100 * 1e18;
        vm.deal(address(NodesInstance), amountToWithdraw);

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        NodesInstance.withdraw(1);
        vm.stopPrank();
    }
}
