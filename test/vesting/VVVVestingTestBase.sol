//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title VVVVesting Test Base
 *   @dev storage, setup, and helper functions for VVVVesting tests
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

    function setVestingScheduleFromDeployer(
        address _user,
        uint256 _vestingScheduleIndex,
        uint256 _tokensToVestAfterStart,
        uint256 _tokensToVestAtStart,
        uint256 _amountWithdrawn,
        uint256 _postCliffDuration,
        uint256 _scheduleStartTime,
        uint256 _cliffEndTime,
        uint256 _intervalLength
    ) public {
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.setVestingSchedule(
            _user,
            _vestingScheduleIndex,
            _tokensToVestAfterStart,
            _tokensToVestAtStart,
            _amountWithdrawn,
            _postCliffDuration,
            _scheduleStartTime,
            _cliffEndTime,
            _intervalLength
        );
        vm.stopPrank();
    }

    function removeVestingScheduleFromDeployer(address _user, uint256 _vestingScheduleIndex) public {
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.removeVestingSchedule(_user, _vestingScheduleIndex);
        vm.stopPrank();
    }

    function withdrawVestedTokensAsUser(
        address _caller,
        uint256 _amount,
        address _destination,
        uint256 _vestingScheduleIndex
    ) public {
        vm.startPrank(_caller, _caller);
        VVVVestingInstance.withdrawVestedTokens(_amount, _destination, _vestingScheduleIndex);
        vm.stopPrank();
    }

    // generates a SetVestingScheduleParams array with the specified number of users and the specified parameter varied,
    // and varies vestedUser and vestingScheduleIndex because these are the factors by which the vesting schedule is identified
    function generateSetVestingScheduleData(
        uint256 _numUsers,
        string memory paramToVary
    ) public view returns (VVVVesting.SetVestingScheduleParams[] memory) {
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = new VVVVesting.SetVestingScheduleParams[](_numUsers);

        if (keccak256(abi.encodePacked(paramToVary)) == keccak256(abi.encodePacked("vestedUser"))) {
            for (uint256 i = 0; i < _numUsers; i++) {
                setVestingScheduleParams[i].vestedUser = address(
                    uint160(uint256(keccak256(abi.encodePacked(i))))
                );
                setVestingScheduleParams[i].vestingScheduleIndex = 0;
                setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterStart =
                    (i + 1) *
                    10_000 *
                    1e18; //10k
                setVestingScheduleParams[i].vestingSchedule.postCliffDuration =
                    (i + 1) *
                    60 *
                    24 *
                    365 *
                    2; //2 years
                setVestingScheduleParams[i].vestingSchedule.scheduleStartTime =
                    block.timestamp +
                    i *
                    60 *
                    24 *
                    2; //2 days from now
                setVestingScheduleParams[i].vestingSchedule.cliffEndTime =
                    block.timestamp +
                    i *
                    60 *
                    24 *
                    30; //30 days
                setVestingScheduleParams[i].vestingSchedule.intervalLength = 60 * 24 * 30; //30 days
            }
        } else if (
            keccak256(abi.encodePacked(paramToVary)) == keccak256(abi.encodePacked("vestingScheduleIndex"))
        ) {
            for (uint256 i = 0; i < _numUsers; i++) {
                setVestingScheduleParams[i].vestedUser = address(
                    uint160(uint256(keccak256(abi.encodePacked("vestedUser"))))
                );
                setVestingScheduleParams[i].vestingScheduleIndex = i;
                setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
                setVestingScheduleParams[i].vestingSchedule.postCliffDuration = 60 * 24 * 365 * 2; //2 years
                setVestingScheduleParams[i].vestingSchedule.scheduleStartTime =
                    block.timestamp *
                    60 *
                    24 *
                    2; //2 days from now
                setVestingScheduleParams[i].vestingSchedule.cliffEndTime = block.timestamp * 60 * 24 * 30; //30 days
                setVestingScheduleParams[i].vestingSchedule.intervalLength = 60 * 24 * 30; //30 days
            }
        } else {
            revert("invalid paramToVary");
        }

        return setVestingScheduleParams;
    }
}
