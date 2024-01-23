//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";
import { VVVVCTokenDistributorBase } from "test/vc/VVVVCTokenDistributorBase.sol";

/**
 * @title VVVVCTokenDistributor Unit Tests
 * @dev use "forge test --match-contract VVVVCTokenDistributorUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCTokenDistributor" to run coverage
 */
contract VVVVCTokenDistributorUnitTests is VVVVCTokenDistributorBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        LedgerInstance = new VVVVCInvestmentLedger();
        TokenDistributorInstance = new VVVVCTokenDistributor(address(LedgerInstance), domainTag);

        vm.stopPrank();
    }

    function testDeployment() public {
        assertTrue(address(TokenDistributorInstance) != address(0));
    }
}
