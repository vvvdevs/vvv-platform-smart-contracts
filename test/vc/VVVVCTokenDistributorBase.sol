//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "lib/forge-std/src/Test.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";

/**
    @title VVVVCTokenDistributor Test Base
 */
abstract contract VVVVCTokenDistributorBase is Test {
    VVVVCInvestmentLedger public LedgerInstance;
    VVVVCTokenDistributor public TokenDistributorInstance;

    uint256 deployerKey = 1234;
    uint256 testSignerKey = 12345;
    uint256 sampleUserKey = 1234567;

    address deployer = vm.addr(deployerKey);
    address testSigner = vm.addr(testSignerKey);
    address sampleUser = vm.addr(sampleUserKey);

    uint256 blockNumber;
    uint256 blockTimestamp;

    string domainTag = "development";

    function advanceBlockNumberAndTimestampInBlocks(uint256 blocks) public {
        blockNumber += blocks;
        blockTimestamp += blocks * 12; //seconds per block
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    function advanceBlockNumberAndTimestampInSeconds(uint256 secondsToAdvance) public {
        blockNumber += secondsToAdvance / 12; //seconds per block
        blockTimestamp += secondsToAdvance;
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }
}
