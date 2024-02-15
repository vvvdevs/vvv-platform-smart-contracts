//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ABDKMath64x64 } from "./ABDKMath64x64.sol";

contract VVVVesting is Ownable {
    using SafeERC20 for IERC20;
    ///@notice the VVV token being vested

    IERC20 public VVVToken;

    /**
        @notice struct representing a user's vesting schedule
        @param tokensToVestAfterStart the total amount of tokens to be vested after schedule start
        @param tokensToVestAtStart the total amount of tokens to be vested at schedule start
        @param tokenAmountWithdrawn the amount of tokens that have been withdrawn
        @param postCliffDuration the postCliffDuration of the vesting schedule
        @param scheduleStartTime the start time of the vesting schedule
        @param cliffEndTime the end time of the cliff
        @param intervalLength the length of each interval in seconds
        @param tokenAmountPerInterval the amount of tokens to be vested per interval
     */
    struct VestingSchedule {
        uint256 tokensToVestAfterStart;
        uint256 tokensToVestAtStart;
        uint256 tokenAmountWithdrawn;
        uint256 postCliffDuration;
        uint256 scheduleStartTime;
        uint256 cliffEndTime;
        uint256 intervalLength;
        uint256 tokenAmountPerInterval;
    }

    /**
       @notice struct representing parameters for setting a vesting schedule
       @param vestedUser the address of the user whose vesting schedule is being set
       @param vestingScheduleIndex the index of the vesting schedule being set
       @param vestingSchedule the vesting schedule being set
     */
    struct SetVestingScheduleParams {
        address vestedUser;
        uint256 vestingScheduleIndex;
        VestingSchedule vestingSchedule;
    }

    ///@notice maps user address to array of vesting schedules
    mapping(address => VestingSchedule[]) public userVestingSchedules;

    /**
        @notice emitted when a user's vesting schedule is set or updated
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _tokensToVestAfterStart the total amount of tokens to be vested after schedule start
        @param _tokensToVestAtStart the total amount of tokens to be vested at schedule start
        @param _vestingScheduleAmountWithdrawn the amount of tokens that have been withdrawn
        @param _vestingScheduleDuration the postCliffDuration of the vesting schedule
        @param _vestingScheduleStartTime the start time of the vesting schedule
        @param _vestingScheduleCliffEndTime the end time of the cliff
        @param _vestingScheduleIntervalLength the length of each interval in seconds
        @param _vestingScheduleTokenAmountPerInterval the amount of tokens to be vested per interval
    */
    event SetVestingSchedule(
        address indexed _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _tokensToVestAfterStart,
        uint256 _tokensToVestAtStart,
        uint256 _vestingScheduleAmountWithdrawn,
        uint256 _vestingScheduleDuration,
        uint256 _vestingScheduleStartTime,
        uint256 _vestingScheduleCliffEndTime,
        uint256 _vestingScheduleIntervalLength,
        uint256 _vestingScheduleTokenAmountPerInterval
    );

    /**
        @notice emitted when a user's vesting schedule is removed
        @param _vestedUser the address of the user whose vesting schedule is being removed
        @param _vestingScheduleIndex the index of the vesting schedule being removed
     */
    event RemoveVestingSchedule(address indexed _vestedUser, uint256 _vestingScheduleIndex);

    /**
        @notice emitted when user withdraws tokens
        @param _vestedUser the address of the user whose tokens are being withdrawn
        @param _tokenDestination the address the tokens are being sent to
        @param _tokenAmountToWithdraw the amount of tokens being withdrawn
        @param _vestingScheduleIndex the index of the vesting schedule the tokens are being withdrawn from
     */
    event VestedTokenWithdrawal(
        address indexed _vestedUser,
        address indexed _tokenDestination,
        uint256 _tokenAmountToWithdraw,
        uint256 _vestingScheduleIndex
    );

    /**
        @notice emitted when the vested token is set
        @param _vvvtoken the address of the VVV token being vested
     */
    event SetVestedToken(address indexed _vvvtoken);

    ///@notice emitted when user tries to withdraw more tokens than are available to withdraw
    error AmountIsGreaterThanWithdrawable();

    ///@notice emitted when the contract is deployed with invalid constructor arguments
    error InvalidConstructorArguments();

    ///@notice emitted when a user tries to set a vesting schedule that does not exist
    error InvalidScheduleIndex();

    ///@notice emitted when an admin tries to set the vested token to the zero address
    error InvalidTokenAddress();

    /**
       @notice constructor
           @param _vvvtoken the VVV token being vested
           @dev reverts if _vvvtoken is the zero address
     */
    constructor(address _vvvtoken) Ownable(msg.sender) {
        if (_vvvtoken == address(0)) {
            revert InvalidConstructorArguments();
        }

        VVVToken = IERC20(_vvvtoken);
    }

    /**
        @notice allows user to withdraw any portion of their currently available tokens for a given vesting schedule
        @param _tokenAmountToWithdraw amount of tokens to withdraw
        @param _tokenDestination address to send tokens to
        @param _vestingScheduleIndex index of vesting schedule to withdraw from
        @dev reverts if user withdrawable amount for that schedule is less than _tokenAmountToWithdraw
     */
    function withdrawVestedTokens(
        uint256 _tokenAmountToWithdraw,
        address _tokenDestination,
        uint256 _vestingScheduleIndex
    ) external {
        VestingSchedule[] storage vestingSchedules = userVestingSchedules[msg.sender];

        if (_vestingScheduleIndex >= vestingSchedules.length) {
            revert InvalidScheduleIndex();
        }

        VestingSchedule storage vestingSchedule = vestingSchedules[_vestingScheduleIndex];

        if (
            _tokenAmountToWithdraw >
            getVestedAmount(msg.sender, _vestingScheduleIndex) - vestingSchedule.tokenAmountWithdrawn
        ) {
            revert AmountIsGreaterThanWithdrawable();
        }

        vestingSchedule.tokenAmountWithdrawn += _tokenAmountToWithdraw;

        VVVToken.safeTransfer(_tokenDestination, _tokenAmountToWithdraw);

        emit VestedTokenWithdrawal(
            msg.sender,
            _tokenDestination,
            _tokenAmountToWithdraw,
            _vestingScheduleIndex
        );
    }

    /**
        @notice sets or replaces vesting schedule
        @param _params SetVestingScheduleParams struct
     */
    function _setVestingSchedule(SetVestingScheduleParams memory _params) private {
        VestingSchedule memory newSchedule = _params.vestingSchedule;

        newSchedule.tokenAmountPerInterval =
            newSchedule.tokensToVestAfterStart /
            (newSchedule.postCliffDuration / newSchedule.intervalLength);

        if (_params.vestingScheduleIndex == userVestingSchedules[_params.vestedUser].length) {
            userVestingSchedules[_params.vestedUser].push(newSchedule);
        } else if (_params.vestingScheduleIndex < userVestingSchedules[_params.vestedUser].length) {
            userVestingSchedules[_params.vestedUser][_params.vestingScheduleIndex] = newSchedule;
        } else {
            revert InvalidScheduleIndex();
        }

        emit SetVestingSchedule(
            _params.vestedUser,
            _params.vestingScheduleIndex,
            _params.vestingSchedule.tokensToVestAfterStart,
            _params.vestingSchedule.tokensToVestAtStart,
            _params.vestingSchedule.tokenAmountWithdrawn,
            _params.vestingSchedule.postCliffDuration,
            _params.vestingSchedule.scheduleStartTime,
            _params.vestingSchedule.cliffEndTime,
            _params.vestingSchedule.intervalLength,
            _params.vestingSchedule.tokenAmountPerInterval
        );
    }

    /**
       @notice returns the amount of tokens that are currently vested (exlcudes amount withdrawn)
           @param _vestedUser the user whose withdrawable amount is being queried
           @param _vestingScheduleIndex the index of the vesting schedule being queried
           @dev considers 4 cases for calculating withdrawable amount:
               1. schedule has not started OR has not been set
               2. schedule has started, but cliff has not ended
               3. schedule has ended with tokens remaining to withdraw
               4. schedule is in progress with tokens remaining to withdraw
     */
    function getVestedAmount(
        address _vestedUser,
        uint256 _vestingScheduleIndex
    ) public view returns (uint256) {
        VestingSchedule storage vestingSchedule = userVestingSchedules[_vestedUser][_vestingScheduleIndex];

        if (
            block.timestamp < vestingSchedule.scheduleStartTime ||
            vestingSchedule.scheduleStartTime == 0 ||
            userVestingSchedules[_vestedUser].length == 0
        ) {
            return 0;
        } else if (block.timestamp < vestingSchedule.cliffEndTime) {
            return vestingSchedule.tokensToVestAtStart;
        } else if (block.timestamp >= vestingSchedule.cliffEndTime + vestingSchedule.postCliffDuration) {
            return vestingSchedule.tokensToVestAfterStart + vestingSchedule.tokensToVestAtStart;
        } else {
            uint256 elapsedIntervals = (block.timestamp - vestingSchedule.cliffEndTime) /
                vestingSchedule.intervalLength;
            return
                (elapsedIntervals * vestingSchedule.tokenAmountPerInterval) +
                vestingSchedule.tokensToVestAtStart;
        }
    }

    //================================================================================
    // This is temporary, testing code for ABDKMath64x64 pending resolution of discussion on how to
    // address linear+exponential vesting living in harmony

    uint256 growthRatePercentage = 1;
    uint256 elapsedIntervalsTesting = 100;
    uint256 tokensToVestAfterFirstInterval = 100;
    uint256 denominator = 100;

    /**
        y_n = y_0 * (1 + r)^(n-1) direct in loop
     */
    function getVestedAmountExponentialTesting(uint256 _numIntervals) public view returns (uint64) {
        int128 tokensToVestAtFirstInterval = ABDKMath64x64.fromUInt(tokensToVestAfterFirstInterval);
        int128 growthRate = ABDKMath64x64.divu(growthRatePercentage, denominator);
        int128 growthTerm = ABDKMath64x64.add(ABDKMath64x64.fromUInt(1), growthRate);
        int128 totalToVest = ABDKMath64x64.fromUInt(0);

        for (uint256 i = 1; i <= _numIntervals; i++) {
            int128 expTerm = ABDKMath64x64.pow(growthTerm, i - 1);

            int128 tokensToVestForIntervalN = ABDKMath64x64.mul(tokensToVestAtFirstInterval, expTerm);

            totalToVest = ABDKMath64x64.add(totalToVest, tokensToVestForIntervalN);
        }

        return ABDKMath64x64.toUInt(totalToVest);
    }

    //same as above effectively, optimized loop
    function getVestedAmountExponentialTestingOptimizedLoop(
        uint256 _numIntervals
    ) public view returns (uint64) {
        int128 tokensToVestAtFirstInterval = ABDKMath64x64.fromUInt(tokensToVestAfterFirstInterval);
        int128 growthRate = ABDKMath64x64.divu(growthRatePercentage, denominator);
        int128 growthTerm = ABDKMath64x64.add(ABDKMath64x64.fromUInt(1), growthRate);
        int128 totalToVest = ABDKMath64x64.fromUInt(0);
        int128 tokensToVestForIntervalN = tokensToVestAtFirstInterval;

        for (uint256 i = 0; i < _numIntervals; i++) {
            if (i > 0) {
                // Apply growth rate from the second interval onwards
                tokensToVestForIntervalN = ABDKMath64x64.mul(tokensToVestForIntervalN, growthTerm);
            }
            totalToVest = ABDKMath64x64.add(totalToVest, tokensToVestForIntervalN);
        }
        return ABDKMath64x64.toUInt(totalToVest);
    }

    /**
        Geometric series approach: 
        Sn = a * (r^n - 1) / (r - 1) 
        where: 
        a is the amount vested at 1st interval
        r is growth rate
        n is number of invervals
    */
    function getVestedAmountExponentialTestingGeomSeries(
        uint256 _numIntervals
    ) public view returns (uint64) {
        int128 a = ABDKMath64x64.fromUInt(tokensToVestAfterFirstInterval);
        int128 r = ABDKMath64x64.divu(growthRatePercentage + denominator, denominator); // 1 + growthRate
        int128 n = ABDKMath64x64.fromUInt(_numIntervals);

        // Calculate r^n
        int128 r_pow_n = ABDKMath64x64.pow(r, ABDKMath64x64.toUInt(n));

        // Calculate the sum of the geometric series
        int128 Sn = ABDKMath64x64.div(
            ABDKMath64x64.mul(a, ABDKMath64x64.sub(r_pow_n, ABDKMath64x64.fromUInt(1))),
            ABDKMath64x64.sub(r, ABDKMath64x64.fromUInt(1))
        );

        return ABDKMath64x64.toUInt(Sn);
    }

    //================================================================================

    /**
        @notice sets or replaces vesting schedule
        @notice only callable by admin
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _tokensToVestAfterStart the total amount of tokens to be vested after schedule start
        @param _tokensToVestAtStart the total amount of tokens that are vested at schedule start
        @param _vestingScheduleAmountWithdrawn the amount of tokens that have been withdrawn
        @param _vestingScheduleDuration the postCliffDuration of the vesting schedule
        @param _vestingScheduleStartTime the start time of the vesting schedule
        @param _vestingScheduleCliffEndTime the end time of the vesting schedule
        @param _vestingScheduleIntervalLength the length of each interval in seconds
     */
    function setVestingSchedule(
        address _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _tokensToVestAfterStart,
        uint256 _tokensToVestAtStart,
        uint256 _vestingScheduleAmountWithdrawn,
        uint256 _vestingScheduleDuration,
        uint256 _vestingScheduleStartTime,
        uint256 _vestingScheduleCliffEndTime,
        uint256 _vestingScheduleIntervalLength
    ) external onlyOwner {
        VestingSchedule memory newSchedule;
        newSchedule.tokensToVestAfterStart = _tokensToVestAfterStart;
        newSchedule.tokensToVestAtStart = _tokensToVestAtStart;
        newSchedule.tokenAmountWithdrawn = _vestingScheduleAmountWithdrawn;
        newSchedule.postCliffDuration = _vestingScheduleDuration;
        newSchedule.scheduleStartTime = _vestingScheduleStartTime;
        newSchedule.cliffEndTime = _vestingScheduleCliffEndTime;
        newSchedule.intervalLength = _vestingScheduleIntervalLength;

        SetVestingScheduleParams memory params = SetVestingScheduleParams(
            _vestedUser,
            _vestingScheduleIndex,
            newSchedule
        );

        _setVestingSchedule(params);
    }

    /**
        @notice used to batch-call _setVestingSchedule
        @notice only callable by admin
        @param _params array of SetVestingScheduleParams structs
     */
    function batchSetVestingSchedule(SetVestingScheduleParams[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; ++i) {
            _setVestingSchedule(_params[i]);
        }
    }

    /**
        @notice removes vesting schedule while preserving indices of other schedules
        @notice only callable by admin
        @param _vestedUser the address of the user whose vesting schedule is being removed
        @param _vestingScheduleIndex the index of the vesting schedule being removed
     */
    function removeVestingSchedule(address _vestedUser, uint256 _vestingScheduleIndex) external onlyOwner {
        delete userVestingSchedules[_vestedUser][_vestingScheduleIndex];
        emit RemoveVestingSchedule(_vestedUser, _vestingScheduleIndex);
    }

    /**
        @notice sets the address of the VVV token being vested
        @notice emits SetVestedToken event
        @param _vvvtoken the address of the VVV token being vested
        @dev in-place update that carries over existing vesting schedules and user claims
        @dev reverts if _vvvtoken is the zero address
     */
    function setVestedToken(address _vvvtoken) external onlyOwner {
        if (_vvvtoken == address(0)) {
            revert InvalidTokenAddress();
        }

        VVVToken = IERC20(_vvvtoken);
        emit SetVestedToken(_vvvtoken);
    }
}
