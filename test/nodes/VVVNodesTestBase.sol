//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "lib/forge-std/src/Test.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVNodes } from "contracts/nodes/VVVNodes.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";

abstract contract VVVNodesTestBase is Test {
    VVVAuthorizationRegistry AuthRegistry;
    VVVNodes NodesInstance;
    VVVToken VVVTokenInstance;

    uint256 deployerKey = 1234;
    uint256 sampleUserKey = 1234567;

    address deployer = vm.addr(deployerKey);
    address sampleUser = vm.addr(sampleUserKey);

    uint256 blockNumber;
    uint256 blockTimestamp;

    uint48 defaultAdminTransferDelay = 1 days;

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
