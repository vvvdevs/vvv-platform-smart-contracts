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
        NodesInstance = new VVVNodes(address(VVVTokenInstance));
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

    //tests claim, entire amount accrued during vesting period should be claimable by a user. utilizes placeholder logic in mint() to set TokenData
    function testClaim() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints token of ID 1
        uint256 userTokenId = 1;

        //wait for tokens to vest to the active node
        advanceBlockNumberAndTimestampInSeconds(105 weeks); //>2 years

        //check pre-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPreClaim, , , ) = NodesInstance.tokenData(userTokenId);
        uint256 balancePreClaim = VVVTokenInstance.balanceOf(sampleUser);

        NodesInstance.claim(userTokenId);

        //check post-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPostClaim, , , ) = NodesInstance.tokenData(userTokenId);
        uint256 balancePostClaim = VVVTokenInstance.balanceOf(sampleUser);

        vm.stopPrank();

        //the vested tokens (which become claimable during the claim() call), become the users balance
        assertEq(unvestedAmountPreClaim, balancePostClaim);
    }

    //tests claim with a tokenId that is not owned by the caller
    function testClaimNotOwned() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        vm.stopPrank();

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVNodes.CallerIsNotTokenOwner.selector);
        NodesInstance.claim(1);
        vm.stopPrank();
    }

    //tests claim of zero $VVV (can't be defined as a claim amount, but if a user claims with a token they own the instant after activating, this error will be thrown)
    function testClaimZero() public {
        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints tokenId 1
        vm.expectRevert(VVVNodes.NoClaimableTokens.selector);
        NodesInstance.claim(1);
        vm.stopPrank();
    }
}
