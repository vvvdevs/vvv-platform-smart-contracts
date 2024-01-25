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
        uint256 vestingScheduleIndex = 0;
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120;
        uint256 scheduleStartTime = 1;
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute cliff
        uint256 intervalLength = 30;

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

        uint256 vestingTime = _vestingTime > cliffEndTime ? _vestingTime : cliffEndTime;
        advanceBlockNumberAndTimestampInSeconds(vestingTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        (, , uint256 withdrawnTokens, , , , , ) = VVVVestingInstance.userVestingSchedules(
            sampleUser,
            vestingScheduleIndex
        );
        uint256 amountToWithdraw = Math.min(vestedAmount - withdrawnTokens, _tokenAmountToWithdraw);

        withdrawVestedTokensAsUser(sampleUser, amountToWithdraw, sampleUser, vestingScheduleIndex);
        assertEq(VVVTokenInstance.balanceOf(sampleUser), amountToWithdraw);
    }

    //tests both that the correct amount of vested and withdrawn tokens are read
    function testFuzz_GetVestedAmount(address _vestedUser, uint256 _vestingTime) public {
        uint256 tokensToVestAfterStart = 10_000 * 1e18; //10k tokens
        uint256 tokensToVestAtStart = 1_000 * 1e18; //1k tokens
        uint256 amountWithdrawn = 0;
        uint256 postCliffDuration = 120;
        uint256 scheduleStartTime = 1; //using block.timestamp would return different values after manipulating timestamp...strange.
        uint256 cliffEndTime = scheduleStartTime + 60; //1 minute cliff
        uint256 vestingScheduleIndex = 0;
        uint256 intervalLength = 30;
        uint256 tokenAmountPerInterval = tokensToVestAfterStart / (postCliffDuration / intervalLength);

        setVestingScheduleFromDeployer(
            _vestedUser,
            vestingScheduleIndex,
            tokensToVestAfterStart,
            tokensToVestAtStart,
            amountWithdrawn,
            postCliffDuration,
            scheduleStartTime,
            cliffEndTime,
            intervalLength
        );

        uint256 vestingTime = _vestingTime > cliffEndTime ? _vestingTime : cliffEndTime;
        advanceBlockNumberAndTimestampInSeconds(vestingTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(_vestedUser, vestingScheduleIndex);
        uint256 elapsedIntervals = (block.timestamp - cliffEndTime) / intervalLength;

        //if the elapsed intervals is less than the max uint256 value divided by the token amount per interval, then we can calculate the reference vested amount
        //otherwise, the reference vested amount would overflow
        if (elapsedIntervals <= (type(uint256).max - tokensToVestAtStart) / tokenAmountPerInterval) {
            uint256 referenceVestedAmount = Math.min(
                tokensToVestAfterStart,
                elapsedIntervals * tokenAmountPerInterval
            ) + tokensToVestAtStart;

            assertEq(vestedAmount, referenceVestedAmount);
        }
    }
}
