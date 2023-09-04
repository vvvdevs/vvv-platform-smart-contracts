//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {VVVTokenTestBase} from "./VvvTokenTestBase.sol";

contract VVVTokenUInitTests {

    function setUp() public {
        vm.startPrank(deployer, deployer);
        vvvToken = new VvvToken(cap, initialSupply);
        vm.stopPrank();

        targetContract(address(vvvToken));
    }
    
    /**
     * @dev deployment test
     */
    function testDeployment() public {
        assertTrue(address(vvvToken) != address(0));
    }

    /**
     * @dev test initial supply
     */

    function testInitialSupply() public {
        uint256 expected = initialSupply;
        uint256 actual = vvvToken.totalSupply();

        assertEq(actual, expected);
    }

    /**
     * @dev test cap
     */
    function testCap() public {
        uint256 expected = cap;
        uint256 actual = vvvToken.cap();

        assertEq(actual, expected);
    }
}

