//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { VVVVestingTestBase } from "test/vesting/VVVVestingTestBase.sol";

/**
 * @title VVVVesting Unit Tests
 * @dev use "forge test --match-contract VVVVestingUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVesting" to run coverage
 */
contract VVVVestingUnitTests is VVVVestingTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        VVVTokenInstance = new MockERC20(18);
        VVVVestingInstance = new VVVVesting(address(VVVTokenInstance));

        VVVTokenInstance.mint(address(VVVVestingInstance), 1_000_000 * 1e18); //1M tokens

        vm.stopPrank();
    }

    function testDeployment() public {
        assertTrue(address(VVVVestingInstance) != address(0));
    }

    //test deployment with zero address as vvv token address
    function testDeploymentWithZeroAddress() public {
        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVesting.InvalidConstructorArguments.selector);
        VVVVestingInstance = new VVVVesting(address(0));
        vm.stopPrank();
    }

    //test admin/owner only functions are not accessible by other callers
    function testAdminFunctionNotCallableByOtherUsers() public {
        //values that would work if caller was owner/admin
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute cliff
        uint256 intervalLength = 12;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        VVVVestingInstance.setVestingSchedule(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        VVVVestingInstance.removeVestingSchedule(sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test invalid vesting schedule index
    function testInvalidVestingScheduleIndex() public {
        uint256 vestingScheduleIndex = 1; //at this point length is 0, so 1 should fail
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute cliff
        uint256 intervalLength = 12;

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVesting.InvalidScheduleIndex.selector);
        VVVVestingInstance.setVestingSchedule(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );
        vm.stopPrank();
    }

    //test that a new vesting schedule can be set and the correct values are stored/read
    function testSetNewVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 60 * 60 * 24 * 365 * 2; //2 years
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        (
            uint256 _tokensToVestAfterStart,
            uint256 _tokensToVestAtStart,
            uint256 _amountWithdrawn,
            uint256 _durationInSeconds,
            uint256 _scheduleStartTime,
            uint256 _cliffEndTime,
            uint256 _intervalLength,

        ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

        assertTrue(_tokensToVestAfterStart == tokensToVestAfterStart);
        assertTrue(_tokensToVestAtStart == tokensToVestAtStart);
        assertTrue(_amountWithdrawn == 0);
        assertTrue(_durationInSeconds == postCliffDuration);
        assertTrue(_scheduleStartTime == scheduleStartTime);
        assertTrue(_cliffEndTime == cliffEndTime);
        assertTrue(_intervalLength == intervalLength);
    }

    //test that a vesting schedule can be updated and the correct values are stored/read
    function testSetExistingVestingSchedule() public {
        {
            uint256 vestingScheduleIndex = 0;
            uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
            uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
            uint256 amountWithdrawn = 0;
            uint256 postCliffDuration = 60 * 60 * 24 * 365 * 2; //2 years
            uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
            uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
            uint256 intervalLength = 60 * 60 * 6 * 365; //3 months

            setVestingScheduleFromDeployer(
                sampleUser,
                vestingScheduleIndex,
                tokensToVestAfterStart,
                tokensToVestAtStart,
                amountWithdrawn,
                postCliffDuration,
                scheduleStartTime,
                cliffEndTime,
                intervalLength
            );

            (
                uint256 _tokensToVestAfterStart,
                uint256 _tokensToVestAtStart,
                uint256 _amountWithdrawn,
                uint256 _durationInSeconds,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,

            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAfterStart == tokensToVestAfterStart);
            assertTrue(_tokensToVestAtStart == tokensToVestAtStart);
            assertTrue(_amountWithdrawn == 0);
            assertTrue(_durationInSeconds == postCliffDuration);
            assertTrue(_scheduleStartTime == scheduleStartTime);
            assertTrue(_cliffEndTime == cliffEndTime);
            assertTrue(_intervalLength == intervalLength);
        }
        {
            //update part of schedule (tokensToVestAfterStart is now 20k, postCliffDuration is now 3 years)
            uint256 vestingScheduleIndex2 = 0;
            uint256 totalAmountToBeVested2 = 20_000 * 1e18; //20k tokens
            uint256 totalPrevestedTokens2 = 1_000 * 1e18; //1k tokens
            uint256 amountWithdrawn2 = 0;
            uint256 durationInSeconds2 = 60 * 60 * 24 * 365 * 3; //3 years
            uint256 scheduleStartTime2 = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
            uint256 cliffEndTime2 = scheduleStartTime2 + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
            uint256 intervalLength2 = 60 * 60 * 6 * 365; //3 months

            setVestingScheduleFromDeployer(
                sampleUser,
                vestingScheduleIndex2,
                totalAmountToBeVested2,
                totalPrevestedTokens2,
                amountWithdrawn2,
                durationInSeconds2,
                scheduleStartTime2,
                cliffEndTime2,
                intervalLength2
            );

            (
                uint256 _totalAmountToBeVested2,
                uint256 _prevestedAmount2,
                uint256 _amountWithdrawn2,
                uint256 _durationInSeconds2,
                uint256 _scheduleStartTime2,
                uint256 _cliffEndTime2,
                uint256 _intervalLength2,

            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_totalAmountToBeVested2 == totalAmountToBeVested2);
            assertTrue(_prevestedAmount2 == totalPrevestedTokens2);
            assertTrue(_amountWithdrawn2 == 0);
            assertTrue(_durationInSeconds2 == durationInSeconds2);
            assertTrue(_scheduleStartTime2 == scheduleStartTime2);
            assertTrue(_cliffEndTime2 == cliffEndTime2);
            assertTrue(_intervalLength2 == intervalLength2);
        }
    }

    //test that a vesting schedule can be removed (reset) and the correct values are stored/read
    function testRemoveVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        {
            uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
            uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
            uint256 amountWithdrawn = 0;
            uint256 postCliffDuration = 60 * 60 * 24 * 365 * 2; //2 years
            uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
            uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
            uint256 intervalLength = 60 * 60 * 6 * 365; //3 months

            setVestingScheduleFromDeployer(
                sampleUser,
                vestingScheduleIndex,
                tokensToVestAfterStart,
                tokensToVestAtStart,
                amountWithdrawn,
                postCliffDuration,
                scheduleStartTime,
                cliffEndTime,
                intervalLength
            );

            (
                uint256 _tokensToVestAfterStart,
                uint256 _tokensToVestAtStart,
                uint256 _amountWithdrawn,
                uint256 _durationInSeconds,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,

            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAfterStart == tokensToVestAfterStart);
            assertTrue(_tokensToVestAtStart == tokensToVestAtStart);
            assertTrue(_amountWithdrawn == 0);
            assertTrue(_durationInSeconds == postCliffDuration);
            assertTrue(_scheduleStartTime == scheduleStartTime);
            assertTrue(_cliffEndTime == cliffEndTime);
            assertTrue(_intervalLength == intervalLength);
        }

        {
            removeVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex);
            (
                uint256 _totalAmount2,
                uint256 _prevestedAmount2,
                uint256 _amountWithdrawn2,
                uint256 _duration2,
                uint256 _scheduleStartTime2,
                uint256 _cliffEndTime2,
                uint256 _intervalLength2,
                uint256 _amountPerInterval2
            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_totalAmount2 == 0);
            assertTrue(_prevestedAmount2 == 0);
            assertTrue(_amountWithdrawn2 == 0);
            assertTrue(_duration2 == 0);
            assertTrue(_scheduleStartTime2 == 0);
            assertTrue(_cliffEndTime2 == 0);
            assertTrue(_intervalLength2 == 0);
            assertTrue(_amountPerInterval2 == 0);
        }
    }

    //test that a user can withdraw the correct amount of tokens from a vesting schedule and the vesting contract state matches the withdrawal
    function testUserWithdrawAndVestedAmount() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );
        advanceBlockNumberAndTimestampInBlocks(postCliffDuration / 12 / 2); //seconds/(seconds per block)/fraction of postCliffDuration

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        uint256 vestingContractBalanceBeforeWithdraw = VVVTokenInstance.balanceOf(
            address(VVVVestingInstance)
        );

        withdrawVestedTokensAsUser(sampleUser, vestedAmount, sampleUser, vestingScheduleIndex);

        (, , uint256 _amountWithdrawn2, , , , , ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
        assertTrue(_amountWithdrawn2 == vestedAmount);

        uint256 vestingContractBalanceAfterWithdraw = VVVTokenInstance.balanceOf(
            address(VVVVestingInstance)
        );
        assertTrue(
            vestingContractBalanceBeforeWithdraw == vestedAmount + vestingContractBalanceAfterWithdraw
        );
    }

    // tests the case where the contract vests more tokens than the contract token balance
    function testWithdrawMoreThanPermitted() public {
        uint256 vestingScheduleIndex = 0;

        //one more than total contract balance, relies on order of error checking in withdrawVestedTokens()
        uint256 contractBalance = VVVTokenInstance.balanceOf(address(VVVVestingInstance));
        uint256 tokensToVestAfterStart = contractBalance * 2;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );
        advanceBlockNumberAndTimestampInBlocks(postCliffDuration); //seconds/(seconds per block) - be sure to be past 100% vesting

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);

        //prank to incorporate expected revert message
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(vestedAmount + 1, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test withdrawVestedTokens() with invalid vesting schedule index - at this point there are no schedules, so any index should fail
    function testWithdrawVestedTokensWithInvalidVestingScheduleIndex() public {
        uint256 vestingScheduleIndex = 0;
        uint256 amountToWithdraw = 0;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.InvalidScheduleIndex.selector);
        VVVVestingInstance.withdrawVestedTokens(amountToWithdraw, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test withdrawVestedTokens() with a finished vesting schedule
    function testWithdrawVestedTokensWithFinishedVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );
        advanceBlockNumberAndTimestampInBlocks(postCliffDuration * 10); //seconds/(seconds per block) - be sure to be past 100% vesting

        //withdraw all vested tokens after schedule is finished
        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        withdrawVestedTokensAsUser(sampleUser, vestedAmount, sampleUser, vestingScheduleIndex);

        //attempt to withdraw one more token, should fail
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(1, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test withdrawVestedTokens() with a vesting schedule that has not yet started
    function testWithdrawVestedTokensWithVestingScheduleNotStarted() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(
            (tokensToVestAfterStart + tokensToVestAtStart),
            sampleUser,
            vestingScheduleIndex
        );
        vm.stopPrank();
    }

    //tests that an admin can set the vested token address, and than a non-admin cannot do so
    function testAdminCanSetVestedToken() public {
        address newVestedTokenAddress = 0x1234567890123456789012345678901234567890;

        // Should work
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.setVestedToken(newVestedTokenAddress);
        vm.stopPrank();

        assertTrue(address(VVVVestingInstance.VVVToken()) == newVestedTokenAddress);
    }

    //test that the zero address cannot be set as the vested token
    function testZeroAddressCannotBeSetAsVestedToken() public {
        address zeroAddress = address(0);

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVesting.InvalidTokenAddress.selector);
        VVVVestingInstance.setVestedToken(zeroAddress);
        vm.stopPrank();
    }

    //test that a user cannot set the vested token
    function testUserCannotSetVestedToken() public {
        address newVestedTokenAddress = 0x1234567890123456789012345678901234567890;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sampleUser));
        VVVVestingInstance.setVestedToken(newVestedTokenAddress);
        vm.stopPrank();
    }

    //test batch-setting vesting schedules as admin with a varying vestedAddress in each vesting schedule
    function testBatchSetVestingSchedulesVaryingVestedAddress() public {
        //sample data
        uint256 numberOfVestedUsers = 2;
        string memory paramToVary = "vestedUser";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                paramToVary
            );

        //set a vesting schedule as admin
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.batchSetVestingSchedule(setVestingScheduleParams);
        vm.stopPrank();

        //ensure schedules properly set
        for (uint256 i = 0; i < numberOfVestedUsers; i++) {
            (
                uint256 _tokensToVestAfterStart,
                uint256 _tokensToVestAtStart,
                uint256 _amountWithdrawn,
                uint256 _postCliffDuration,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _tokenAmountPerInterval
            ) = VVVVestingInstance.userVestingSchedules(setVestingScheduleParams[i].vestedUser, 0);
            assertTrue(
                _tokensToVestAfterStart ==
                    setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterStart
            );
            assertTrue(
                _tokensToVestAtStart == setVestingScheduleParams[i].vestingSchedule.tokensToVestAtStart
            );
            assertTrue(_amountWithdrawn == 0);
            assertTrue(
                _postCliffDuration == setVestingScheduleParams[i].vestingSchedule.postCliffDuration
            );
            assertTrue(
                _scheduleStartTime == setVestingScheduleParams[i].vestingSchedule.scheduleStartTime
            );
            assertTrue(_cliffEndTime == setVestingScheduleParams[i].vestingSchedule.cliffEndTime);
            assertTrue(_intervalLength == setVestingScheduleParams[i].vestingSchedule.intervalLength);
            assertTrue(
                _tokenAmountPerInterval ==
                    (_tokensToVestAfterStart / (_postCliffDuration / _intervalLength))
            );
        }
    }

    //test batch-setting vesting schedules as admin with a varying scheduleIndex in each vesting schedule
    function testBatchSetVestingSchedulesVaryingScheduleIndex() public {
        //sample data
        uint256 numberOfVestedUsers = 2;
        string memory paramToVary = "vestingScheduleIndex";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                paramToVary
            );

        //set a vesting schedule as admin
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.batchSetVestingSchedule(setVestingScheduleParams);
        vm.stopPrank();

        //ensure schedules properly set
        for (uint256 i = 0; i < numberOfVestedUsers; i++) {
            (
                uint256 _tokensToVestAfterStart,
                uint256 _tokensToVestAtStart,
                uint256 _amountWithdrawn,
                uint256 _durationInSeconds,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _tokenAmountPerInterval
            ) = VVVVestingInstance.userVestingSchedules(
                    setVestingScheduleParams[i].vestedUser,
                    setVestingScheduleParams[i].vestingScheduleIndex
                );
            assertTrue(
                _tokensToVestAfterStart ==
                    setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterStart
            );
            assertTrue(
                _tokensToVestAtStart == setVestingScheduleParams[i].vestingSchedule.tokensToVestAtStart
            );
            assertTrue(_amountWithdrawn == 0);
            assertTrue(
                _durationInSeconds == setVestingScheduleParams[i].vestingSchedule.postCliffDuration
            );
            assertTrue(
                _scheduleStartTime == setVestingScheduleParams[i].vestingSchedule.scheduleStartTime
            );
            assertTrue(_cliffEndTime == setVestingScheduleParams[i].vestingSchedule.cliffEndTime);
            assertTrue(_intervalLength == setVestingScheduleParams[i].vestingSchedule.intervalLength);
            assertTrue(
                _tokenAmountPerInterval ==
                    (_tokensToVestAfterStart / (_durationInSeconds / _intervalLength))
            );
        }
    }

    //test that a non-admin cannot batch-set vesting schedules
    function testBatchSetVestingSchedulesUnauthorizedUser() public {
        //sample data
        uint256 numberOfVestedUsers = 1;
        string memory paramToVary = "vestedUser";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                paramToVary
            );

        //set as user (not allowed)
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sampleUser));
        VVVVestingInstance.batchSetVestingSchedule(setVestingScheduleParams);
        vm.stopPrank();
    }

    //test for remainder from division truncation, and make sure it is withdrawable after vesting schedule is finished. choosing prime amounts to make sure it'd work with any vesting schedule
    function testRemainderFromDivisionTruncationIsWithdrawable() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 3888888886666664444227;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 4159;
        uint256 scheduleStartTime = block.timestamp;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 397;
        uint256 tokenAmountPerInterval = tokensToVestAfterStart / (postCliffDuration / intervalLength);
        uint256 numberOfIntervalsToAdvanceTimestamp = 10; // 10 intervals = 3970 seconds

        //397/4159 = 0.09545563837460928, so I'll advance 10 intervals to get 95% of the way to the end of the schedule
        //at this point, the total vested amount should be (tokensToVestAfterStart + tokensToVestAtStart) - tokenAmountPerInterval - truncation error
        //(also equal to 9*tokenAmountPerInterval)

        //then advance 1 more interval to get beyond the end of the schedule, at which point total vested amount should be tokensToVestAfterStart + tokensToVestAtStart

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        advanceBlockNumberAndTimestampInSeconds(intervalLength * numberOfIntervalsToAdvanceTimestamp);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);

        //vestedAmount should be 9*tokenAmountPerInterval because at 95% of the schedule length, 9 intervals have passed
        assertTrue(
            vestedAmount ==
                ((numberOfIntervalsToAdvanceTimestamp - 1) * tokenAmountPerInterval) + tokensToVestAtStart
        );

        advanceBlockNumberAndTimestampInSeconds(intervalLength);

        uint256 vestedAmount2 = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        assertTrue(vestedAmount2 == tokensToVestAfterStart + tokensToVestAtStart);
    }

    //tests that the tokensToVestAtStart are available to withdraw immediately at start of vesting schedule
    function testTokensToVestAtStartAreClaimableAtVestingScheduleStart() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        //advance to start of vesting schedule
        advanceBlockNumberAndTimestampInSeconds(scheduleStartTime);

        //read vested amount from contract
        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);

        //assert that vested amount is equal to tokensToVestAtStart
        assertTrue(vestedAmount == tokensToVestAtStart);
    }

    //test that the tokensToVestAtStart are available until cliffEndTime has elapsed
    function testTokensToVestAtStartAreClaimableAtCliffEndTime() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        //advance to end of cliff
        advanceBlockNumberAndTimestampInSeconds(cliffEndTime);

        //read vested amount from contract
        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);

        //assert that vested amount is equal to tokensToVestAtStart
        assertTrue(vestedAmount == tokensToVestAtStart);
    }

    //test that any amount greater than tokensToVestAtStart is NOT available before cliffEndTime has elapsed
    function testClaimMoreThanTokensToVestAtStartBeforeCliffEndTime() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountToWithdraw = tokensToVestAtStart + 1; //1 more than tokensToVestAtStart
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120; //120 seconds
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 12;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        //advance to end of cliff
        advanceBlockNumberAndTimestampInSeconds(cliffEndTime);

        //attempt to withdraw more than tokensToVestAtStart
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(amountToWithdraw, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }
}
