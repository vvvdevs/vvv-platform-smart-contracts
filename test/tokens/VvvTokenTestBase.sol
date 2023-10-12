//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @dev Base for testing VvvToken.sol
 */


import "lib/forge-std/src/Test.sol";
import { ERC20_UniV3 } from "contracts/tokens/VvvToken.sol";

contract VVVTokenTestBase is Test {
    ERC20_UniV3 vvvToken;

    address public UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public UNIV3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    uint256 public cap = 10_000_000 * 1e18;
    uint256 public initialDeployerSupply = 2_000_000 * 1e18;
    uint256 public initialLiquiditySupply = 1_000_000 * 1e18;

    uint256 public deployerKey = 1234;
    address public deployer = vm.addr(deployerKey);

    uint256 public positionRecipientKey = 1235;
    address public positionRecipient = vm.addr(positionRecipientKey);
}
