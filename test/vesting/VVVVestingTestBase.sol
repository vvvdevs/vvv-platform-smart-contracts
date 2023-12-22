//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
  @title VVVVesting Test Base
  @dev storage, setup, and helper functions for VVVVesting tests
 */

import { Test } from "lib/forge-std/src/Test.sol"; //for stateless tests
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";

abstract contract VVVVestingTestBase is Test {
    MockERC20 public VVVTokenInstance;
    VVVVesting public VVVVestingInstance;    
    
    uint256 public deployerKey = 1;
    uint256 public userKey = 2;
    address deployer = vm.addr(deployerKey);
    address sampleUser = vm.addr(userKey);
    
    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainid;
    
    
    function advanceBlockNumberAndTimestampInBlocks(uint256 blocks) public {
        for (uint256 i = 0; i < blocks; i++) {
            blockNumber += 1;
            blockTimestamp += 12; //seconds per block
        }
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    function setVestingScheduleFromDeployer(address _user, uint256 _vestingScheduleIndex, uint256 _totalAmount, uint256 _duration, uint256 _startTime) public {
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.setVestingSchedule(_user, _vestingScheduleIndex, _totalAmount, _duration, _startTime);
        vm.stopPrank();
    }

    function removeVestingScheduleFromDeployer(address _user, uint256 _vestingScheduleIndex) public {
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.removeVestingSchedule(_user, _vestingScheduleIndex);
        vm.stopPrank();
    }

    function withdrawVestedTokensAsUser(address _caller, uint256 _amount, address _destination, uint256 _vestingScheduleIndex) public {
        vm.startPrank(_caller, _caller);
        VVVVestingInstance.withdrawVestedTokens(_amount, _destination, _vestingScheduleIndex);
        vm.stopPrank();
    }
}