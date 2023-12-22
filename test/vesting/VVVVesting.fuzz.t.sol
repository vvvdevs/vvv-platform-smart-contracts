//SPDX-License-Identifier: MIT

/**
 * @title VVVVesting Fuzz Tests
 * @dev use "forge test --match-contract VVVVestingInvariantTests -vvv" to run tests and show logs if applicable
 * @dev use "forge coverage --match-contract VVVVesting" to run coverage
 */

pragma solidity ^0.8.23;

// import { Test } from "lib/forge-std/src/Test.sol"; //for stateless tests
import { VVVVestingTestBase } from "test/vesting/VVVVestingTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVesting } from "contracts/vesting/VVVVesting.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract VVVVestingFuzzTests is VVVVestingTestBase {
    bool logging = true;

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
        (, uint256 withdrawnTokens, , ) = VVVVestingInstance.userVestingSchedules(sampleUser, vestingScheduleIndex);
        uint256 amountToWithdraw = Math.min(vestedAmount - withdrawnTokens, _tokenAmountToWithdraw);

        withdrawVestedTokensAsUser(sampleUser, amountToWithdraw, sampleUser, vestingScheduleIndex);
        assertEq(VVVTokenInstance.balanceOf(sampleUser), amountToWithdraw);
    }


    // function testFuzz_GetVestedAmount() public {}
    // function testFuzz_SetVestingSchedule() public {}
    // function testFuzz_RemoveVestingSchedule() public {}
}

