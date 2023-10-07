//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @dev Base for testing VvvToken.sol
 */


import "lib/forge-std/src/Test.sol";
import { ERC20_UniV3 } from "contracts/tokens/VvvToken.sol";

contract VVVTokenTestBase is Test {
    ERC20_UniV3 vvvToken;

    uint256 public cap = 10_000_000 * 1e18;
    uint256 public initialDeployerSupply = 2_000_000 * 1e18;
    uint256 public initialLiquiditySupply = 1_000_000 * 1e18;

    uint256 public deployerKey = 1234;
    address public deployer = vm.addr(deployerKey);

    uint256 public positionRecipientKey = 1235;
    address public positionRecipient = vm.addr(positionRecipientKey);
}
