//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @dev Base for testing VvvToken.sol
 */


import "lib/forge-std/src/Test.sol";
import { VVVToken } from "src/VvvToken.sol";

contract VVVTokenTestBase is Test {
    VVVToken vvvToken;

    uint256 public initialSupply = 1000000
    uint256 public cap = initialSupply * 10;

    uint256 public deployerKey = 1234;
    address deployer = vm.addr(deployerKey);
}





