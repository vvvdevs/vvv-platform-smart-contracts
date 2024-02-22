///SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "lib/forge-std/src/Test.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";

contract VVVAuthorizationRegistryTests is Test {
    VVVAuthorizationRegistry registry;

    uint256 deployerKey = 1234;
    address deployer = vm.addr(deployerKey);

    uint48 defaultAdminTransferDelay = 3 days;
    address defaultAdmin = deployer;

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainId = 31337; //test chain id - leave this alone

    function setUp() public {
        vm.startPrank(deployer, deployer);
        registry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, defaultAdmin);
        vm.stopPrank();
    }

    //helper
    function advanceBlockNumberAndTimestampInSeconds(uint256 secondsToAdvance) public {
        blockNumber += secondsToAdvance / 12; //seconds per block
        blockTimestamp += secondsToAdvance;
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    //unit tests
    //ensures contract is deployed as expected
    function testDeployment() public {
        assertTrue(address(registry) != address(0));
    }

    //ensures that the DEFAULT_ADMIN_ROLE can set permissions
    function testDefaultAdminSetPermission() public {
        bytes4 selector = bytes4(keccak256("test()"));
        bytes32 role = bytes32(keccak256("TEST_ROLE"));
        address contractToCall = address(this);

        vm.startPrank(deployer, deployer);
        registry.setPermission(contractToCall, selector, role);
        vm.stopPrank();

        bytes24 key = bytes24(keccak256(abi.encodePacked(contractToCall, selector)));
        assertTrue(registry.permissions(key) == role);
    }

    //ensures that the DEFAULT_ADMIN_ROLE can revoke a previously set permission by setting the role for a key to bytes32(0)
    function testDefaultAdminRevokePermission() public {
        vm.startPrank(deployer, deployer);
        bytes4 selector = bytes4(keccak256("test()"));
        bytes32 role = bytes32(keccak256("TEST_ROLE"));
        address contractToCall = address(this);

        registry.setPermission(contractToCall, selector, role);

        bytes24 key = bytes24(keccak256(abi.encodePacked(contractToCall, selector)));

        registry.setPermission(contractToCall, selector, bytes32(0));

        assertTrue(registry.permissions(key) == bytes32(0));

        vm.stopPrank();
    }
}
