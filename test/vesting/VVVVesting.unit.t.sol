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
        VestingParams memory params = VestingParams({
            vestingScheduleIndex: 0,
            tokensToVestAtStart: 1_000 * 1e18, //1k tokens
            tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
            amountWithdrawn: 0,
            scheduleStartTime: block.timestamp,
            cliffEndTime: block.timestamp + 60, //1 minute cliff
            intervalLength: 12,
            maxIntervals: 100,
            growthRatePercentage: 0
        });

        setVestingScheduleFromDeployer(
            sampleUser,
            params.vestingScheduleIndex,
            params.tokensToVestAtStart,
            params.tokensToVestAfterFirstInterval,
            params.amountWithdrawn,
            params.scheduleStartTime,
            params.cliffEndTime,
            params.intervalLength,
            params.maxIntervals,
            params.growthRatePercentage
        );

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        setVestingScheduleFromDeployer(
            sampleUser,
            params.vestingScheduleIndex,
            params.tokensToVestAtStart,
            params.tokensToVestAfterFirstInterval,
            params.amountWithdrawn,
            params.scheduleStartTime,
            params.cliffEndTime,
            params.intervalLength,
            params.maxIntervals,
            params.growthRatePercentage
        );
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        VVVVestingInstance.removeVestingSchedule(sampleUser, params.vestingScheduleIndex);
        vm.stopPrank();
    }

    //test invalid vesting schedule index
    function testInvalidVestingScheduleIndex() public {
        VestingParams memory params = VestingParams({
            vestingScheduleIndex: 0,
            tokensToVestAtStart: 1_000 * 1e18, //1k tokens
            tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
            amountWithdrawn: 0,
            scheduleStartTime: block.timestamp,
            cliffEndTime: block.timestamp + 60, //1 minute cliff
            intervalLength: 12,
            maxIntervals: 100,
            growthRatePercentage: 0
        });

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVesting.InvalidScheduleIndex.selector);
        setVestingScheduleFromDeployer(
            sampleUser,
            params.vestingScheduleIndex,
            params.tokensToVestAtStart,
            params.tokensToVestAfterFirstInterval,
            params.amountWithdrawn,
            params.scheduleStartTime,
            params.cliffEndTime,
            params.intervalLength,
            params.maxIntervals,
            params.growthRatePercentage
        );
        vm.stopPrank();
    }

    //test that a new vesting schedule can be set and the correct values are stored/read
    function testSetNewVestingSchedule() public {
        VestingParams memory params = VestingParams({
            vestingScheduleIndex: 0,
            tokensToVestAtStart: 1_000 * 1e18, //1k tokens
            tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
            amountWithdrawn: 0,
            scheduleStartTime: block.timestamp + 60 * 60 * 24 * 2,
            cliffEndTime: block.timestamp + 60 * 60 * 24 * 365,
            intervalLength: 12,
            maxIntervals: 100,
            growthRatePercentage: 0
        });

        setVestingScheduleFromDeployer(
            sampleUser,
            params.vestingScheduleIndex,
            params.tokensToVestAtStart,
            params.tokensToVestAfterFirstInterval,
            params.amountWithdrawn,
            params.scheduleStartTime,
            params.cliffEndTime,
            params.intervalLength,
            params.maxIntervals,
            params.growthRatePercentage
        );

        (
            uint256 _tokensToVestAtStart,
            uint256 _tokensToVestAfterFirstInterval,
            uint256 _tokenAmountWithdrawn,
            uint256 _scheduleStartTime,
            uint256 _cliffEndTime,
            uint256 _intervalLength,
            uint256 _maxIntervals,
            uint256 _growthRatePercentage
        ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

        assertTrue(_tokensToVestAtStart == params.tokensToVestAtStart);
        assertTrue(_tokensToVestAfterFirstInterval == params.tokensToVestAfterFirstInterval);
        assertTrue(_tokenAmountWithdrawn == 0);
        assertTrue(_scheduleStartTime == params.scheduleStartTime);
        assertTrue(_cliffEndTime == params.cliffEndTime);
        assertTrue(_intervalLength == params.intervalLength);
        assertTrue(_maxIntervals == params.maxIntervals);
        assertTrue(_growthRatePercentage == params.growthRatePercentage);
    }

    // START HERE!
    //test that a vesting schedule can be updated and the correct values are stored/read
    function testSetExistingVestingSchedule() public {
        {
            VestingParams memory params = VestingParams({
                vestingScheduleIndex: 0,
                tokensToVestAtStart: 1_000 * 1e18, //1k tokens
                tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
                amountWithdrawn: 0,
                scheduleStartTime: block.timestamp + 60 * 60 * 24 * 2,
                cliffEndTime: block.timestamp + 60 * 60 * 24 * 365,
                intervalLength: 12,
                maxIntervals: 100,
                growthRatePercentage: 0
            });

            setVestingScheduleFromDeployer(
                sampleUser,
                params.vestingScheduleIndex,
                params.tokensToVestAtStart,
                params.tokensToVestAfterFirstInterval,
                params.amountWithdrawn,
                params.scheduleStartTime,
                params.cliffEndTime,
                params.intervalLength,
                params.maxIntervals,
                params.growthRatePercentage
            );

            (
                uint256 _tokensToVestAtStart,
                uint256 _tokensToVestAfterFirstInterval,
                uint256 _tokenAmountWithdrawn,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _maxIntervals,
                uint256 _growthRatePercentage
            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAtStart == params.tokensToVestAtStart);
            assertTrue(_tokensToVestAfterFirstInterval == params.tokensToVestAfterFirstInterval);
            assertTrue(_tokenAmountWithdrawn == 0);
            assertTrue(_scheduleStartTime == params.scheduleStartTime);
            assertTrue(_cliffEndTime == params.cliffEndTime);
            assertTrue(_intervalLength == params.intervalLength);
            assertTrue(_maxIntervals == params.maxIntervals);
            assertTrue(_growthRatePercentage == params.growthRatePercentage);
        }
        {
            //update part of schedule (tokensToVestAfterStart is now 20k, postCliffDuration is now 3 years)
            VestingParams memory params = VestingParams({
                vestingScheduleIndex: 0,
                tokensToVestAtStart: 2_000 * 1e18, //2k tokens
                tokensToVestAfterFirstInterval: 200 * 1e18, //200 tokens
                amountWithdrawn: 0,
                scheduleStartTime: block.timestamp + 60 * 60 * 24 * 3, //3 days from now
                cliffEndTime: block.timestamp + 60 * 60 * 24 * 180, //180 days from scheduleStartTime
                intervalLength: 12,
                maxIntervals: 200,
                growthRatePercentage: 0
            });

            setVestingScheduleFromDeployer(
                sampleUser,
                params.vestingScheduleIndex,
                params.tokensToVestAtStart,
                params.tokensToVestAfterFirstInterval,
                params.amountWithdrawn,
                params.scheduleStartTime,
                params.cliffEndTime,
                params.intervalLength,
                params.maxIntervals,
                params.growthRatePercentage
            );

            (
                uint256 _tokensToVestAtStart,
                uint256 _tokensToVestAfterFirstInterval,
                uint256 _tokenAmountWithdrawn,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _maxIntervals,
                uint256 _growthRatePercentage
            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAtStart == params.tokensToVestAtStart);
            assertTrue(_tokensToVestAfterFirstInterval == params.tokensToVestAfterFirstInterval);
            assertTrue(_tokenAmountWithdrawn == 0);
            assertTrue(_scheduleStartTime == params.scheduleStartTime);
            assertTrue(_cliffEndTime == params.cliffEndTime);
            assertTrue(_intervalLength == params.intervalLength);
            assertTrue(_maxIntervals == params.maxIntervals);
            assertTrue(_growthRatePercentage == params.growthRatePercentage);
        }
    }

    //test that a vesting schedule can be removed (reset) and the correct values are stored/read
    function testRemoveVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        {
            VestingParams memory params = VestingParams({
                vestingScheduleIndex: 0,
                tokensToVestAtStart: 1_000 * 1e18, //1k tokens
                tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
                amountWithdrawn: 0,
                scheduleStartTime: block.timestamp + 60 * 60 * 24 * 2,
                cliffEndTime: block.timestamp + 60 * 60 * 24 * 365,
                intervalLength: 12,
                maxIntervals: 100,
                growthRatePercentage: 0
            });

            setVestingScheduleFromDeployer(
                sampleUser,
                params.vestingScheduleIndex,
                params.tokensToVestAtStart,
                params.tokensToVestAfterFirstInterval,
                params.amountWithdrawn,
                params.scheduleStartTime,
                params.cliffEndTime,
                params.intervalLength,
                params.maxIntervals,
                params.growthRatePercentage
            );

            (
                uint256 _tokensToVestAtStart,
                uint256 _tokensToVestAfterFirstInterval,
                uint256 _tokenAmountWithdrawn,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _maxIntervals,
                uint256 _growthRatePercentage
            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAtStart == params.tokensToVestAtStart);
            assertTrue(_tokensToVestAfterFirstInterval == params.tokensToVestAfterFirstInterval);
            assertTrue(_tokenAmountWithdrawn == 0);
            assertTrue(_scheduleStartTime == params.scheduleStartTime);
            assertTrue(_cliffEndTime == params.cliffEndTime);
            assertTrue(_intervalLength == params.intervalLength);
            assertTrue(_maxIntervals == params.maxIntervals);
            assertTrue(_growthRatePercentage == params.growthRatePercentage);
        }

        {
            removeVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex);
            (
                uint256 _tokensToVestAtStart2,
                uint256 _tokensToVestAfterFirstInterval2,
                uint256 _tokenAmountWithdrawn2,
                uint256 _scheduleStartTime2,
                uint256 _cliffEndTime2,
                uint256 _intervalLength2,
                uint256 _maxIntervals2,
                uint256 _growthRatePercentage2
            ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);

            assertTrue(_tokensToVestAtStart2 == 0);
            assertTrue(_tokensToVestAfterFirstInterval2 == 0);
            assertTrue(_tokenAmountWithdrawn2 == 0);
            assertTrue(_scheduleStartTime2 == 0);
            assertTrue(_cliffEndTime2 == 0);
            assertTrue(_intervalLength2 == 0);
            assertTrue(_maxIntervals2 == 0);
            assertTrue(_growthRatePercentage2 == 0);
        }
    }

    //test that a user can withdraw the correct amount of tokens from a vesting schedule and the vesting contract state matches the withdrawal
    function testUserWithdrawAndVestedAmount() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
        );

        //advance partially through the vesting schedule
        advanceBlockNumberAndTimestampInBlocks((maxIntervals * intervalLength) / 12 / 2); //seconds/(seconds per block)/fraction of postCliffDuration

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
        //one more than total contract balance, relies on order of error checking in withdrawVestedTokens()
        uint256 contractBalance = VVVTokenInstance.balanceOf(address(VVVVestingInstance));

        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = contractBalance * 2;
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
        );
        advanceBlockNumberAndTimestampInBlocks(maxIntervals * intervalLength); //seconds/(seconds per block) - be sure to be past 100% vesting

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
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
        );
        advanceBlockNumberAndTimestampInBlocks(maxIntervals * intervalLength * 10); //seconds/(seconds per block) - be sure to be past 100% vesting

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
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
        );

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(
            (maxIntervals * intervalLength + tokensToVestAtStart),
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
        uint256 growthRate = 0;
        string memory paramToVary = "vestedUser";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                growthRate,
                paramToVary
            );

        //set a vesting schedule as admin
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.batchSetVestingSchedule(setVestingScheduleParams);
        vm.stopPrank();

        //ensure schedules properly set
        for (uint256 i = 0; i < numberOfVestedUsers; i++) {
            (
                uint256 _tokensToVestAtStart,
                uint256 _tokensToVestAfterFirstInterval,
                uint256 _tokenAmountWithdrawn,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _maxIntervals,
                uint256 _growthRatePercentage
            ) = VVVVestingInstance.userVestingSchedules(setVestingScheduleParams[i].vestedUser, 0);

            assertTrue(
                _tokensToVestAtStart == setVestingScheduleParams[i].vestingSchedule.tokensToVestAtStart
            );
            assertTrue(
                _tokensToVestAfterFirstInterval ==
                    setVestingScheduleParams[i].vestingSchedule.maxIntervals *
                        setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterFirstInterval
            );

            assertTrue(_tokenAmountWithdrawn == 0);
            assertTrue(
                _scheduleStartTime == setVestingScheduleParams[i].vestingSchedule.scheduleStartTime
            );
            assertTrue(_cliffEndTime == setVestingScheduleParams[i].vestingSchedule.cliffEndTime);
            assertTrue(_intervalLength == setVestingScheduleParams[i].vestingSchedule.intervalLength);
            assertTrue(_maxIntervals == setVestingScheduleParams[i].vestingSchedule.maxIntervals);
            assertTrue(
                _growthRatePercentage == setVestingScheduleParams[i].vestingSchedule.growthRatePercentage
            );
        }
    }

    //test batch-setting vesting schedules as admin with a varying scheduleIndex in each vesting schedule
    function testBatchSetVestingSchedulesVaryingScheduleIndex() public {
        //sample data
        uint256 numberOfVestedUsers = 2;
        uint256 growthRate = 0;
        string memory paramToVary = "vestingScheduleIndex";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                growthRate,
                paramToVary
            );

        //set a vesting schedule as admin
        vm.startPrank(deployer, deployer);
        VVVVestingInstance.batchSetVestingSchedule(setVestingScheduleParams);
        vm.stopPrank();

        //ensure schedules properly set
        for (uint256 i = 0; i < numberOfVestedUsers; i++) {
            (
                uint256 _tokensToVestAtStart,
                uint256 _tokensToVestAfterFirstInterval,
                uint256 _tokenAmountWithdrawn,
                uint256 _scheduleStartTime,
                uint256 _cliffEndTime,
                uint256 _intervalLength,
                uint256 _maxIntervals,
                uint256 _growthRatePercentage
            ) = VVVVestingInstance.userVestingSchedules(
                    setVestingScheduleParams[i].vestedUser,
                    setVestingScheduleParams[i].vestingScheduleIndex
                );
            assertTrue(
                _tokensToVestAtStart == setVestingScheduleParams[i].vestingSchedule.tokensToVestAtStart
            );
            assertTrue(
                _tokensToVestAfterFirstInterval ==
                    setVestingScheduleParams[i].vestingSchedule.maxIntervals *
                        setVestingScheduleParams[i].vestingSchedule.tokensToVestAfterFirstInterval
            );
            assertTrue(_tokenAmountWithdrawn == 0);
            assertTrue(
                _scheduleStartTime == setVestingScheduleParams[i].vestingSchedule.scheduleStartTime
            );
            assertTrue(_cliffEndTime == setVestingScheduleParams[i].vestingSchedule.cliffEndTime);
            assertTrue(_intervalLength == setVestingScheduleParams[i].vestingSchedule.intervalLength);
            assertTrue(_maxIntervals == setVestingScheduleParams[i].vestingSchedule.maxIntervals);
            assertTrue(
                _growthRatePercentage == setVestingScheduleParams[i].vestingSchedule.growthRatePercentage
            );
        }
    }

    //test that a non-admin cannot batch-set vesting schedules
    function testBatchSetVestingSchedulesUnauthorizedUser() public {
        //sample data
        uint256 numberOfVestedUsers = 1;
        uint256 growthRate = 0;
        string memory paramToVary = "vestedUser";
        VVVVesting.SetVestingScheduleParams[]
            memory setVestingScheduleParams = generateSetVestingScheduleData(
                numberOfVestedUsers,
                growthRate,
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
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 3737 * 1e18; //3737 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 4159; //4159 seconds from now
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute from scheduleStartTime
        uint256 intervalLength = 397; //397 seconds
        uint256 maxIntervals = 111;
        uint256 growthRatePercentage = 0;

        uint256 numberOfIntervalsToAdvanceTimestamp = 110;

        //TODO: REWRITE!
        //397/4159 = 0.09545563837460928, so I'll advance 10 intervals to get 95% of the way to the end of the schedule
        //at this point, the total vested amount should be (tokensToVestAfterStart + tokensToVestAtStart) - tokenAmountPerInterval - truncation error
        //(also equal to 9*tokenAmountPerInterval)

        //then advance 1 more interval to get beyond the end of the schedule, at which point total vested amount should be tokensToVestAfterStart + tokensToVestAtStart

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
        );

        advanceBlockNumberAndTimestampInSeconds(intervalLength * numberOfIntervalsToAdvanceTimestamp);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);

        assertTrue(
            vestedAmount ==
                tokensToVestAtStart +
                    _calculateVestedAmountAtInterval(
                        tokensToVestAfterFirstInterval,
                        (95 * maxIntervals) / 100,
                        growthRatePercentage
                    )
        );

        advanceBlockNumberAndTimestampInSeconds(intervalLength);

        uint256 vestedAmount2 = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        assertTrue(
            vestedAmount2 ==
                _calculateVestedAmountAtInterval(
                    tokensToVestAfterFirstInterval,
                    maxIntervals,
                    growthRatePercentage
                ) +
                    tokensToVestAtStart
        );
    }

    //tests that the tokensToVestAtStart are available to withdraw immediately at start of vesting schedule
    function testTokensToVestAtStartAreClaimableAtVestingScheduleStart() public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
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
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
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
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountToWithdraw = tokensToVestAtStart + 1; //1 more than tokensToVestAtStart
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = block.timestamp + 60 * 60 * 24 * 2; //2 days from now
        uint256 cliffEndTime = scheduleStartTime + 60 * 60 * 24 * 365; //1 year from scheduleStartTime
        uint256 intervalLength = 60 * 60 * 6 * 365; //3 months
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            sampleUser,
            vestingScheduleIndex,
            tokensToVestAtStart,
            tokensToVestAfterFirstInterval,
            amountWithdrawn,
            scheduleStartTime,
            cliffEndTime,
            intervalLength,
            maxIntervals,
            growthRatePercentage
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
