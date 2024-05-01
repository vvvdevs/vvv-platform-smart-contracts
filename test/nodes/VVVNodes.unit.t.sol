//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVNodes } from "contracts/nodes/VVVNodes.sol";
import { VVVNodesTestBase } from "./VVVNodesTestBase.sol";

contract VVVNodesUnitTest is VVVNodesTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        NodesInstance = new VVVNodes();
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

    //tests correct calculation of vested amount with a given activation date and unvestedAmount. This function uses placeholder logic in the mint() and placeholderUpdateClaimable() functions, to be updated in later issues.
    function testUpdateClaimableFromVesting() public {
        uint256 sampleTokensVestedInTwoYears = 63_113_904 * 1e18;
        uint256 tokenId = 1;

        vm.startPrank(sampleUser, sampleUser);
        NodesInstance.mint(sampleUser);

        //surpass 104 weeks or about 2 years
        advanceBlockNumberAndTimestampInSeconds(105 weeks);

        //the full amount should be vested after > 2 years
        NodesInstance.placeholderUpdateClaimable(tokenId);
        vm.stopPrank();

        (uint256 unvestedAmount, , uint256 claimableAmount, ) = NodesInstance.tokenData(tokenId);

        assertEq(unvestedAmount, 0);
        assertEq(claimableAmount, sampleTokensVestedInTwoYears);
    }
}
