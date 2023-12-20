//SPDX-License-Identifier: MIT

/**
 * @dev VVVVesting Unit Tests
 * @dev use "forge test --match-contract VVVVestingTests -vvv" to run tests and show logs if applicable
 * @dev use "forge coverage --match-contract VVVVesting" to run coverage
 */

pragma solidity ^0.8.15;

import { Test } from "lib/forge-std/src/Test.sol"; //for stateless tests
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract VVVVestingTests is Test {

    MockERC20 public VVVTokenInstance;
    VVVVesting public VVVVestingInstance;

    address[] public users = new address[](333);

    uint256 public deployerKey = 1;
    uint256 public userKey = 2;
    address deployer = vm.addr(deployerKey);
    address sampleUser = vm.addr(userKey);

    bool logging = true;

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainid;

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

    // admin actions ------------------------------------------------------

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
        
        if(logging){
            emit log_named_uint("startBlock", startBlock);
            emit log_named_uint("startTimestamp", startTime);
            emit log_named_uint("block.number", block.number);
            emit log_named_uint("block.timestamp", block.timestamp);
            emit log_named_uint("vestedAmount", vestedAmount/1e18);            
        }

    }

    ///@dev vests more tokens than the contract token balance, so that both error cases can be reached
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

        if(logging){
            emit log_named_uint("contract balance", contractBalance/1e18);
            emit log_named_uint("totalAmount", totalAmount/1e18);
            emit log_named_uint("vestedAmount", vestedAmount/1e18);
        }

        //prank to incorporate each expected revert message
        vm.startPrank(sampleUser, sampleUser);        
        vm.expectRevert(VVVVesting.InsufficientContractBalance.selector);
        VVVVestingInstance.withdrawVestedTokens(contractBalance + 1, sampleUser, vestingScheduleIndex);
        vm.stopPrank();        
        
        vm.startPrank(sampleUser, sampleUser);        
        vm.expectRevert(VVVVesting.AmountIsGreaterThanWithdrawable.selector);
        VVVVestingInstance.withdrawVestedTokens(vestedAmount + 1, sampleUser, vestingScheduleIndex);
        vm.stopPrank();


    }

    //=====================================================================
    // HELPERS
    //=====================================================================
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
