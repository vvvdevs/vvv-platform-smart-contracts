//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVNodes } from "contracts/nodes/VVVNodes.sol";
import { VVVNodesTestBase } from "./VVVNodesTestBase.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";

contract VVVNodesUnitTest is VVVNodesTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        VVVTokenInstance = new VVVToken(type(uint256).max, 0, address(AuthRegistry));
        NodesInstance = new VVVNodes(activationThreshold);
        VVVTokenInstance.mint(address(NodesInstance), 100_000_000 * 1e18);
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
        uint256 timestampAtStake = block.timestamp;

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
}
