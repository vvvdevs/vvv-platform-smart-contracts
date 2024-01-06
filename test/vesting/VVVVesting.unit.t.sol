//SPDX-License-Identifier: MIT

/**
 * @title VVVVesting Unit Tests
 * @dev use "forge test --match-contract VVVVestingUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVesting" to run coverage
 */

pragma solidity ^0.8.23;

import { VVVVestingTestBase } from "test/vesting/VVVVestingTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract VVVVestingUnitTests is VVVVestingTestBase {
    //=====================================================================
    // SETUP
    //=====================================================================
    function setUp() public {
        vm.startPrank(deployer, deployer);

        VVVTokenInstance = new MockERC20(18);
        VVVVestingInstance = new VVVVesting(address(VVVTokenInstance));

        VVVTokenInstance.mint(address(VVVVestingInstance), 1_000_000 * 1e18); //1M tokens

        vm.stopPrank();
    }

    //=====================================================================
    // UNIT TESTS
    //=====================================================================
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

    // admin actions ------------------------------------------------------

    //test admin/owner only functions are not accessible by other callers
    function testAdminFunctionNotCallableByOtherUsers() public {
        //values that would work if caller was owner/admin
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        VVVVestingInstance.setVestingSchedule(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        VVVVestingInstance.removeVestingSchedule(sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test invalid vesting schedule index
    function testInvalidVestingScheduleIndex() public {
        uint256 vestingScheduleIndex = 1; //at this point length is 0, so 1 should fail
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp;

        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVesting.InvalidScheduleIndex.selector);
        VVVVestingInstance.setVestingSchedule(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);
        vm.stopPrank();
    }

    //test that a new vesting schedule can be set and the correct values are stored/read
    function testSetNewVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 duration = 60*60*24*365*2; //2 years
        uint256 startTime = block.timestamp + 60*60*24*2; //2 days from now

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, duration, startTime);

        (uint256 _totalAmount, uint256 _amountWithdrawn, uint256 _duration, uint256 _startTime) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
    
        assertTrue(_totalAmount == totalAmount);
        assertTrue(_amountWithdrawn == 0);
        assertTrue(_duration == duration);
        assertTrue(_startTime == startTime);
    }

    //test that a vesting schedule can be updated and the correct values are stored/read
    function testSetExistingVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 duration = 60*60*24*365*2; //2 years
        uint256 startTime = block.timestamp + 60*60*24*2; //2 days from now

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, duration, startTime);

        (uint256 _totalAmount, uint256 _amountWithdrawn, uint256 _duration, uint256 _startTime) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
    
        assertTrue(_totalAmount == totalAmount);
        assertTrue(_amountWithdrawn == 0);
        assertTrue(_duration == duration);
        assertTrue(_startTime == startTime);

        uint256 totalAmount2 = 20_000 * 1e18; //20k tokens
        uint256 duration2 = 60*60*24*365*3; //3 years
        uint256 startTime2 = block.timestamp + 60*60*24*3; //3 days from now

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount2, duration2, startTime2);

        (uint256 _totalAmount2, uint256 _amountWithdrawn2, uint256 _duration2, uint256 _startTime2) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
    
        assertTrue(_totalAmount2 == totalAmount2);
        assertTrue(_amountWithdrawn2 == 0);
        assertTrue(_duration2 == duration2);
        assertTrue(_startTime2 == startTime2);
    }

    //test that a vesting schedule can be removed (reset) and the correct values are stored/read
    function testRemoveVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 duration = 60*60*24*365*2; //2 years
        uint256 startTime = block.timestamp + 60*60*24*2; //2 days from now

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, duration, startTime);

        (uint256 _totalAmount, uint256 _amountWithdrawn, uint256 _duration, uint256 _startTime) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
    
        assertTrue(_totalAmount == totalAmount);
        assertTrue(_amountWithdrawn == 0);
        assertTrue(_duration == duration);
        assertTrue(_startTime == startTime);

        removeVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex);

        (uint256 _totalAmount2, uint256 _amountWithdrawn2, uint256 _duration2, uint256 _startTime2) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
    
        assertTrue(_totalAmount2 == 0);
        assertTrue(_amountWithdrawn2 == 0);
        assertTrue(_duration2 == 0);
        assertTrue(_startTime2 == 0);
    }

    // user actions -------------------------------------------------------

    //test that a user can withdraw tokens from a vesting schedule
    function testUserWithdrawAndVestedAmount() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp;
        uint256 startBlock = block.number;

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);
        advanceBlockNumberAndTimestampInBlocks(durationInSeconds/12/2); //seconds/(seconds per block)/fraction of durationInSeconds

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);        
        uint256 vestingContractBalanceBeforeWithdraw = VVVTokenInstance.balanceOf(address(VVVVestingInstance));

        withdrawVestedTokensAsUser(sampleUser, vestedAmount, sampleUser, vestingScheduleIndex);

        ( , uint256 _amountWithdrawn2,  ,  ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0);
        assertTrue(_amountWithdrawn2 == vestedAmount);

        uint256 vestingContractBalanceAfterWithdraw = VVVTokenInstance.balanceOf(address(VVVVestingInstance));
        assertTrue(vestingContractBalanceBeforeWithdraw == vestedAmount + vestingContractBalanceAfterWithdraw);
    }

    ///vests more tokens than the contract token balance, so that both error cases can be reached
    function testWithdrawMoreThanPermitted() public {
        uint256 vestingScheduleIndex = 0;

        //one more than total contract balance, relies on order of error checking in withdrawVestedTokens()
        uint256 contractBalance = VVVTokenInstance.balanceOf(address(VVVVestingInstance));
        uint256 totalAmount = contractBalance * 2; 
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp;

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);
        advanceBlockNumberAndTimestampInBlocks(durationInSeconds); //seconds/(seconds per block) - be sure to be past 100% vesting

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
        uint256 totalAmount = 10_000 * 1e18; //10k tokens

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVesting.InvalidScheduleIndex.selector);
        VVVVestingInstance.withdrawVestedTokens(totalAmount, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test withdrawVestedTokens() with a finished vesting schedule
    function testWithdrawVestedTokensWithFinishedVestingSchedule() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp;

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);
        advanceBlockNumberAndTimestampInBlocks(durationInSeconds*10); //seconds/(seconds per block) - be sure to be past 100% vesting

        //withdraw all vested tokens after schedule is finished
        withdrawVestedTokensAsUser(sampleUser, totalAmount, sampleUser, vestingScheduleIndex);

        //attempt to withdraw one more token, should fail
        vm.startPrank(sampleUser, sampleUser);        
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(1, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }

    //test withdrawVestedTokens() with a vesting schedule that has not yet started
    function testWithdrawVestedTokensWithVestingScheduleNotStarted() public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 durationInSeconds = 120; //120 seconds
        uint256 startTime = block.timestamp + 60*60*24*2; //2 days from now

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, durationInSeconds, startTime);

        vm.startPrank(sampleUser, sampleUser);        
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(totalAmount, sampleUser, vestingScheduleIndex);
        vm.stopPrank();
    }
}