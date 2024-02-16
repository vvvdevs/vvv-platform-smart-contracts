//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVestingTestBase } from "test/vesting/VVVVestingTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title VVVVesting Fuzz Tests
 * @dev use "forge test --match-contract VVVVestingFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVestingFuzzTests" to run coverage
 */
contract VVVVestingFuzzTests is VVVVestingTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        VVVTokenInstance = new MockERC20(18);
        VVVVestingInstance = new VVVVesting(address(VVVTokenInstance));

        VVVTokenInstance.mint(address(VVVVestingInstance), 1_000_000 * 1e18); //1M tokens

        vm.stopPrank();
    }

    //test setting a vesting schedule and withdrawing tokens, assert that the correct amount of tokens are withdrawn
    //fuzzes with withdraw values between 0 and (vested-withdrawn)
    function testFuzz_WithdrawVestedTokens(uint256 _tokenAmountToWithdraw, uint256 _vestingTime) public {
        uint256 tokenAmountToWithdraw = bound(_tokenAmountToWithdraw, 1, 1_000_000 * 1e18); //1M tokens

        VestingParams memory params = VestingParams({
            vestingScheduleIndex: 0,
            tokensToVestAtStart: 1_000 * 1e18, //1k tokens
            tokensToVestAfterFirstInterval: 100 * 1e18, //100 tokens
            amountWithdrawn: 0,
            scheduleStartTime: 1,
            cliffEndTime: 1 + 60, //1 minute cliff
            intervalLength: 30,
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

        uint256 vestingTime = _vestingTime > params.cliffEndTime ? _vestingTime : params.cliffEndTime;
        advanceBlockNumberAndTimestampInSeconds(vestingTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, 0); // vestingScheduleIndex
        (, , uint256 withdrawnTokens, , , , , ) = VVVVestingInstance.userVestingSchedules(sampleUser, 0); // vestingScheduleIndex
        uint256 amountToWithdraw = Math.min(vestedAmount - withdrawnTokens, tokenAmountToWithdraw);

        withdrawVestedTokensAsUser(sampleUser, amountToWithdraw, sampleUser, 0); // vestingScheduleIndex
        assertEq(VVVTokenInstance.balanceOf(sampleUser), amountToWithdraw);
    }

    //tests both that the correct amount of vested and withdrawn tokens are read
    function testFuzz_GetVestedAmount(address _vestedUser, uint256 _vestingTime) public {
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 tokensToVestAfterFirstInterval = 100 * 1e18; //100 tokens
        uint256 amountWithdrawn = 0;
        uint256 scheduleStartTime = 1;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute cliff
        uint256 intervalLength = 30;
        uint256 maxIntervals = 100;
        uint256 growthRatePercentage = 0;

        setVestingScheduleFromDeployer(
            _vestedUser,
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

        //bound to some considerable amount past the end of the schedule
        uint256 vestingTime = bound(_vestingTime, cliffEndTime, intervalLength * maxIntervals * 100);
        advanceBlockNumberAndTimestampInSeconds(vestingTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(_vestedUser, vestingScheduleIndex);
        uint256 elapsedIntervals = (block.timestamp - cliffEndTime) / intervalLength;

        uint256 referenceVestedAmount = Math.min(
            maxIntervals * tokensToVestAfterFirstInterval,
            elapsedIntervals * tokensToVestAfterFirstInterval
        ) + tokensToVestAtStart;

        assertEq(vestedAmount, referenceVestedAmount);
    }
}
