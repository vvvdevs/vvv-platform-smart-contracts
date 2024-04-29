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
        NodesInstance = new VVVNodes(
            address(AuthRegistry),
            address(VVVTokenInstance),
            activationThreshold
        );
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

    //tests claim
    function testClaim() public {
        vm.startPrank(deployer, deployer);
        VVVTokenInstance.mint(sampleUser, activationThreshold);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser); //mints token of ID 1
        uint256 userTokenId = 1;

        //sample vesting setup assuming 1 token/second for 2 years
        uint256 vestingDuration = 63_113_904; //2 years
        uint256 refTotalVestedTokens = vestingDuration * 1e18;

        //check pre-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPreClaim, , , , ) = NodesInstance.tokenData(userTokenId);
        uint256 balancePreClaim = VVVTokenInstance.balanceOf(sampleUser);

        //wait for tokens to vest to the active node
        VVVTokenInstance.approve(address(NodesInstance), type(uint256).max);
        NodesInstance.stake(userTokenId, activationThreshold);
        advanceBlockNumberAndTimestampInSeconds(vestingDuration * 2); //temp holdover since mint placeholder currently sets vesting timestmp earlier than activation...
        NodesInstance.claim(userTokenId);

        //check post-vesting unvested tokens and owner wallet balance for userTokenId
        (uint256 unvestedAmountPostClaim, , , , ) = NodesInstance.tokenData(userTokenId);
        uint256 balancePostClaim = VVVTokenInstance.balanceOf(sampleUser);

        vm.stopPrank();

        assertEq(unvestedAmountPreClaim, refTotalVestedTokens);
        assertEq(unvestedAmountPostClaim, 0);
        assertEq(refTotalVestedTokens, balancePostClaim);
    }

    //function testStake() public {}
    //function testStakeUnownedToken() public {}
    //function testUnstake() public {}
    //function testUnstakeUnownedToken() public {}
    //function testTransferFailsWhenSoulbound() public {}
    //function testTransferSucceedsWhenNotSoulbound() public {}
    //function test*admin setter functions*() public {}
}
