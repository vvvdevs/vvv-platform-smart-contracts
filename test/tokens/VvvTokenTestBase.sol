//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @dev Base for testing VvvToken.sol
 */
import "lib/forge-std/src/Test.sol";
import {VVVToken} from "contracts/tokens/VvvToken.sol";

contract VVVTokenTestBase is Test {
    VVVToken vvvToken;

    uint256 public initialSupply = 1000000;
    uint256 public cap = initialSupply * 10;

    uint256 public deployerKey = 1234;
    address public deployer = vm.addr(deployerKey);
}
