//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @dev Base for testing VVVETHStaking.sol
 */

import "lib/forge-std/src/Test.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVETHStaking } from "contracts/staking/VVVETHStaking.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";

abstract contract VVVETHStakingTestBase is Test {
    VVVAuthorizationRegistry AuthRegistry;
    VVVToken VvvTokenInstance;
    VVVETHStaking EthStakingInstance;

    uint256 deployerKey = 1234;
    uint256 ethStakingManagerKey = 1235;
    uint256 sampleUserKey = 1234567;

    address deployer = vm.addr(deployerKey);
    address ethStakingManager = vm.addr(ethStakingManagerKey);
    address sampleUser = vm.addr(sampleUserKey);

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainId = 31337; //test chain id - leave this alone

    bytes32 ethStakingManagerRole = keccak256("ETH_STAKING_MANAGER_ROLE");
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
