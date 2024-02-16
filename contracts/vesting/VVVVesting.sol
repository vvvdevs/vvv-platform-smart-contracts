//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ABDKMath64x64 } from "./ABDKMath64x64.sol";

contract VVVVesting is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMALS = 18;
    uint256 public constant DENOMINATOR = 100;

    ///@notice the VVV token being vested
    IERC20 public VVVToken;

    /**
        @notice struct representing a user's vesting schedule
        @param tokensToVestAtStart the total amount of tokens to be vested at schedule start
        @param tokensToVestAfterFirstInterval the total amount of tokens to be vested after the first interval
        @param tokenAmountWithdrawn the amount of tokens that have been withdrawn
        @param scheduleStartTime the start time of the vesting schedule
        @param cliffEndTime the end time of the cliff
        @param intervalLength the length of each interval in seconds
        @param maxIntervals number of post-cliff intervals
        @param growthRatePercentage the % increase in tokens to be vested per interval
     */
    struct VestingSchedule {
        uint256 tokensToVestAtStart;
        uint256 tokensToVestAfterFirstInterval;
        uint256 tokenAmountWithdrawn;
        uint256 scheduleStartTime;
        uint256 cliffEndTime;
        uint256 intervalLength;
        uint256 maxIntervals;
        uint256 growthRatePercentage;
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
        @param _tokensToVestAtStart the total amount of tokens to be vested at schedule start
        @param _tokensToVestAfterFirstInterval the total amount of tokens to be vested after the first interval
        @param _vestingScheduleAmountWithdrawn the amount of tokens that have been withdrawn
        @param _vestingScheduleStartTime the start time of the vesting schedule
        @param _vestingScheduleCliffEndTime the end time of the cliff
        @param _vestingScheduleIntervalLength the length of each interval in seconds
        @param _vestingScheduleMaxIntervals number of post-cliff intervals
        @param _vestingScheduleGrowthRatePercentage the % increase in tokens to be vested per interval
    */
    event SetVestingSchedule(
        address indexed _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _tokensToVestAtStart,
        uint256 _tokensToVestAfterFirstInterval,
        uint256 _vestingScheduleAmountWithdrawn,
        uint256 _vestingScheduleStartTime,
        uint256 _vestingScheduleCliffEndTime,
        uint256 _vestingScheduleIntervalLength,
        uint256 _vestingScheduleMaxIntervals,
        uint256 _vestingScheduleGrowthRatePercentage
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
            _params.vestingSchedule.tokensToVestAtStart,
            _params.vestingSchedule.tokensToVestAfterFirstInterval,
            _params.vestingSchedule.tokenAmountWithdrawn,
            _params.vestingSchedule.scheduleStartTime,
            _params.vestingSchedule.cliffEndTime,
            _params.vestingSchedule.intervalLength,
            _params.vestingSchedule.maxIntervals,
            _params.vestingSchedule.growthRatePercentage
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
        } else {
            uint256 elapsedIntervals = (block.timestamp - vestingSchedule.cliffEndTime) /
                vestingSchedule.intervalLength;
            elapsedIntervals = elapsedIntervals > vestingSchedule.maxIntervals
                ? vestingSchedule.maxIntervals
                : elapsedIntervals;
            return (vestingSchedule.tokensToVestAtStart +
                _calculateVestedAmountAtInterval(
                    vestingSchedule.tokensToVestAtStart,
                    elapsedIntervals,
                    vestingSchedule.growthRatePercentage
                ));
        }
    }

    /**
        @notice handles ABDKMath64x64 calculations for getVestedAmount
        @dev uses sum of geometric series where each element of series is y_n = y_0 * (1 + r)^(n - 1)
        @dev sum of series is Sn = y_0 * (r^n - 1) / (r - 1)
        @param _firstIntervalAccrual the amount of tokens to be vested after the first interval
        @param _elapsedIntervals the number of intervals over which to calculate the vested amount
        @param _growthRatePercentage the % increase in tokens to be vested per interval
     */
    function _calculateVestedAmountAtInterval(
        uint256 _firstIntervalAccrual,
        uint256 _elapsedIntervals,
        uint256 _growthRatePercentage
    ) private pure returns (uint256) {
        int128 firstIntervalAccrual = ABDKMath64x64.divu(_firstIntervalAccrual, 10 ** DECIMALS);
        int128 growthRate = ABDKMath64x64.divu(_growthRatePercentage + DENOMINATOR, DENOMINATOR);
        int128 growthRateToElapsedIntervals = ABDKMath64x64.pow(growthRate, _elapsedIntervals);
        int128 seriesSum = ABDKMath64x64.div(
            ABDKMath64x64.mul(
                firstIntervalAccrual,
                ABDKMath64x64.sub(growthRateToElapsedIntervals, ABDKMath64x64.fromInt(1))
            ),
            ABDKMath64x64.sub(growthRate, ABDKMath64x64.fromInt(1))
        );
        return uint256(ABDKMath64x64.toUInt(seriesSum)) * 10 ** DECIMALS;
    }

    /**
        @notice sets or replaces vesting schedule
        @notice only callable by admin        
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _tokensToVestAtStart the total amount of tokens to be vested at schedule start
        @param _tokensToVestAfterFirstInterval the total amount of tokens to be vested after the first interval
        @param _vestingScheduleAmountWithdrawn the amount of tokens that have been withdrawn
        @param _vestingScheduleStartTime the start time of the vesting schedule
        @param _vestingScheduleCliffEndTime the end time of the cliff
        @param _vestingScheduleIntervalLength the length of each interval in seconds
        @param _vestingScheduleMaxIntervals number of post-cliff intervals
        @param _vestingScheduleGrowthRatePercentage the % increase in tokens to be vested per interval
    */
    function setVestingSchedule(
        address _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _tokensToVestAtStart,
        uint256 _tokensToVestAfterFirstInterval,
        uint256 _vestingScheduleAmountWithdrawn,
        uint256 _vestingScheduleStartTime,
        uint256 _vestingScheduleCliffEndTime,
        uint256 _vestingScheduleIntervalLength,
        uint256 _vestingScheduleMaxIntervals,
        uint256 _vestingScheduleGrowthRatePercentage
    ) external onlyOwner {
        VestingSchedule memory newSchedule;
        newSchedule.tokensToVestAtStart = _tokensToVestAtStart;
        newSchedule.tokensToVestAfterFirstInterval = _tokensToVestAfterFirstInterval;
        newSchedule.tokenAmountWithdrawn = _vestingScheduleAmountWithdrawn;
        newSchedule.scheduleStartTime = _vestingScheduleStartTime;
        newSchedule.cliffEndTime = _vestingScheduleCliffEndTime;
        newSchedule.intervalLength = _vestingScheduleIntervalLength;
        newSchedule.maxIntervals = _vestingScheduleMaxIntervals;
        newSchedule.growthRatePercentage = _vestingScheduleGrowthRatePercentage;

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
