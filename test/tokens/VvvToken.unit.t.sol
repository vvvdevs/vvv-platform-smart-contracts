//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {VVVTokenTestBase} from "./VvvTokenTestBase.sol";
import { ERC20_UniV3 } from "contracts/tokens/VvvToken.sol";

contract VVVTokenUInitTests is VVVTokenTestBase {

    function setUp() public {
        vm.startPrank(deployer, deployer);

        //replace last 3 args with mock addresses from new deployments if going this route
        vvvToken = new ERC20_UniV3(
            "VVV Token",
            "VVV",
            cap, 
            initialDeployerSupply,
            initialLiquiditySupply,
            positionRecipient,
            UNIV3_FACTORY,
            UNIV3_POSITION_MANAGER,
            WETH
        );
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
        uint256 expected = initialDeployerSupply + initialLiquiditySupply;
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
