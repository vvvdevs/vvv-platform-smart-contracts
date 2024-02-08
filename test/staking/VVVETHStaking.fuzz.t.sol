//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { VVVETHStakingTestBase } from "test/staking/VVVETHStakingTestBase.sol";
import { VVVETHStaking } from "contracts/staking/VVVETHStaking.sol";

/**
 * @title VVVETHStaking Fuzz Tests
 * @dev use "forge test --match-contract VVVETHStakingUnitFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVETHStaking" to run coverage
 */
contract VVVETHStakingUnitFuzzTests is VVVETHStakingTestBase {
    // Sets up project and payment tokens, and an instance of the ETH staking contract
    function setUp() public {
        vm.startPrank(deployer, deployer);
        EthStakingInstance = new VVVETHStaking();
        generateUserAddressListAndDealEther();
        vm.stopPrank();
    }

    // function testFuzz_stakeEth() public {}
    // function testFuzz_withdraw() public {}
}
