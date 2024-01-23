//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "lib/forge-std/src/Test.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/IVVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";

/**
    @title VVVVCTokenDistributor Test Base
 */
abstract contract VVVVCTokenDistributorBase is Test {
    VVVVCInvestmentLedger public LedgerInstance;
    VVVVCTokenDistributor public TokenDistributorInstance;

    uint256 public deployerKey = 1;
    uint256 public userKey = 2;
    address deployer = vm.addr(deployerKey);
    address sampleUser = vm.addr(userKey);

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
