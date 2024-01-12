//SPDX-License-Identifier: MIT

/**
 * @title VVVVesting Fuzz Tests
 * @dev use "forge test --match-contract VVVVestingFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVestingFuzzTests" to run coverage
 */
pragma solidity ^0.8.23;

import { VVVVestingTestBase } from "test/vesting/VVVVestingTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract VVVVestingFuzzTests is VVVVestingTestBase {
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
    // FUZZ TESTS
    //=====================================================================
    //test setting a vesting schedule and withdrawing tokens, assert that the correct amount of tokens are withdrawn
    //fuzzes with withdraw values between 0 and (vested-withdrawn)
    function testFuzz_WithdrawVestedTokens(uint256 _tokenAmountToWithdraw) public {
        uint256 vestingScheduleIndex = 0;
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 duration = 120;
        uint256 startTime = block.timestamp;

        setVestingScheduleFromDeployer(sampleUser, vestingScheduleIndex, totalAmount, duration, startTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(sampleUser, vestingScheduleIndex);
        (, uint256 withdrawnTokens, , ) = VVVVestingInstance.userVestingSchedules(
            sampleUser,
            vestingScheduleIndex
        );
        uint256 amountToWithdraw = Math.min(vestedAmount - withdrawnTokens, _tokenAmountToWithdraw);

        withdrawVestedTokensAsUser(sampleUser, amountToWithdraw, sampleUser, vestingScheduleIndex);
        assertEq(VVVTokenInstance.balanceOf(sampleUser), amountToWithdraw);
    }

    //tests both that the correct amount of vested and withdrawn tokens are read
    function testFuzz_GetVestedAmount(address _vestedUser, uint8 _vestingTime) public {
        uint256 totalAmount = 10_000 * 1e18; //10k tokens
        uint256 duration = 120;
        uint256 startTime = block.timestamp;
        uint256 vestingScheduleIndex = 0;

        setVestingScheduleFromDeployer(
            _vestedUser,
            vestingScheduleIndex,
            totalAmount,
            duration,
            startTime
        );

        uint256 vestingTime = _vestingTime > 0 ? _vestingTime : 1;
        advanceBlockNumberAndTimestampInSeconds(vestingTime);

        uint256 vestedAmount = VVVVestingInstance.getVestedAmount(_vestedUser, vestingScheduleIndex);

        uint256 referenceVestedAmount = Math.min(
            totalAmount,
            (totalAmount * (block.timestamp - startTime)) / duration
        );

        assertEq(vestedAmount, referenceVestedAmount);
    }
}
