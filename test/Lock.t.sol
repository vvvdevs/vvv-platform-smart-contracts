// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "lib/forge-std/src/Test.sol";
import {Lock} from "contracts/demo/Lock.sol";

contract LockTest is Test {
    //======================================================================
    //SETUP
    //======================================================================

    Lock public lock;

    address public userAddress = 0x5De14394c41A7f44a893713Da4AA838476f46CBB;
    address public ownerAddress = 0x5De14394c41A7f44a893713Da4AA838476f46CBB;

    //======================================================================

    function setUp() public {
        vm.startPrank(ownerAddress, ownerAddress);

        lock = new Lock(block.timestamp + 60 seconds);
    }

    function testLockDeploy() public {
        assertEq(lock.owner(), ownerAddress);
    }
}