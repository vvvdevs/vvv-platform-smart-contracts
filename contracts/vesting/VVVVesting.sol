//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVVesting is Ownable {
    using SafeERC20 for IERC20;
    ///@notice the VVV token being vested
    IERC20 public VVVToken;

    /**
        @notice struct representing a user's vesting schedule
        @param totalTokenAmountToVest the total amount of tokens to be vested
        @param tokenAmountWithdrawn the amount of tokens that have been withdrawn
        @param duration the duration of the vesting schedule
        @param startTime the start time of the vesting schedule
     */
    struct VestingSchedule {
        uint256 totalTokenAmountToVest;
        uint256 tokenAmountWithdrawn;
        uint256 duration;
        uint256 startTime;
    }

    ///@notice maps user address to array of vesting schedules
    mapping(address => VestingSchedule[]) public userVestingSchedules;

    /**
        @notice emitted when a user's vesting schedule is set or updated
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _vestingScheduleTotalAmount the total amount of tokens to be vested for this schedule
        @param _vestingScheduleAmountWithdrawn the amount of tokens that have been withdrawn
        @param _vestingScheduleDuration the duration of the vesting schedule
        @param _vestingScheduleStartTime the start time of the vesting schedule
    */
    event SetVestingSchedule(
        address indexed _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _vestingScheduleTotalAmount,
        uint256 _vestingScheduleAmountWithdrawn,
        uint256 _vestingScheduleDuration,
        uint256 _vestingScheduleStartTime
    );

    /**
        @notice emitted when a user's vesting schedule is removed
        @param _vestedUser the address of the user whose vesting schedule is being removed
        @param _vestingScheduleIndex the index of the vesting schedule being removed
    */
    event RemoveVestingSchedule(
        address indexed _vestedUser,
        uint256 _vestingScheduleIndex
    );

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

    ///@notice emitted when user tries to withdraw more tokens than are available to withdraw
    error AmountIsGreaterThanWithdrawable(); 
    
    ///@notice emitted when the contract is deployed with invalid constructor arguments
    error InvalidConstructorArguments();

    ///@notice emitted when a user tries to set a vesting schedule that does not exist
    error InvalidScheduleIndex();

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
    function withdrawVestedTokens(uint256 _tokenAmountToWithdraw, address _tokenDestination, uint256 _vestingScheduleIndex) external {
        VestingSchedule[] storage vestingSchedules = userVestingSchedules[msg.sender];
        
        if(_vestingScheduleIndex >= vestingSchedules.length){
            revert InvalidScheduleIndex();
        }

        VestingSchedule storage vestingSchedule = vestingSchedules[_vestingScheduleIndex];

        if (_tokenAmountToWithdraw > getVestedAmount(msg.sender, _vestingScheduleIndex) - vestingSchedule.tokenAmountWithdrawn){
            revert AmountIsGreaterThanWithdrawable();        
        }
    
        vestingSchedule.tokenAmountWithdrawn += _tokenAmountToWithdraw;

        VVVToken.safeTransfer(_tokenDestination, _tokenAmountToWithdraw);

        emit VestedTokenWithdrawal(msg.sender, _tokenDestination, _tokenAmountToWithdraw, _vestingScheduleIndex);
    }

    /**
        @notice sets or replaces vesting schedule
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _vestingScheduleTotalAmount the total amount of tokens to be vested for this schedule
        @param _vestingScheduleDuration the duration of the vesting schedule
        @param _vestingScheduleStartTime the start time of the vesting schedule
     */
    function _setVestingSchedule(
        address _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _vestingScheduleTotalAmount,
        uint256 _vestingScheduleDuration,
        uint256 _vestingScheduleStartTime
    ) private {
        VestingSchedule memory newSchedule = VestingSchedule(_vestingScheduleTotalAmount, 0, _vestingScheduleDuration, _vestingScheduleStartTime);

        if (_vestingScheduleIndex == userVestingSchedules[_vestedUser].length) {
            userVestingSchedules[_vestedUser].push(newSchedule);
        } else if (_vestingScheduleIndex < userVestingSchedules[_vestedUser].length) {
            userVestingSchedules[_vestedUser][_vestingScheduleIndex] = newSchedule;
        } else {
            revert InvalidScheduleIndex();
        }

        emit SetVestingSchedule(_vestedUser, _vestingScheduleIndex, _vestingScheduleTotalAmount, 0, _vestingScheduleDuration, _vestingScheduleStartTime);
    }

    /**
        @notice returns a user's vesting schedule
        @param _vestedUser the address of the user whose vesting schedule is being queried
        @param _vestingScheduleIndex the index of the vesting schedule being queried
     */
    function getVestingSchedule(address _vestedUser, uint256 _vestingScheduleIndex) external view returns (VestingSchedule memory) {
        return userVestingSchedules[_vestedUser][_vestingScheduleIndex];
    }

    /**
        @notice returns the amount of tokens that are currently vested (exlcudes amount withdrawn)
        @param _vestedUser the user whose withdrawable amount is being queried
        @param _vestingScheduleIndex the index of the vesting schedule being queried
        @dev considers 3 cases for calculating withdrawable amount:
            1. schedule has not started OR has not been set
            2. schedule has ended with tokens remaining to withdraw
            3. schedule is in progress with tokens remaining to withdraw
     */
    function getVestedAmount(address _vestedUser, uint256 _vestingScheduleIndex) public view returns (uint256){
        VestingSchedule storage vestingSchedule = userVestingSchedules[_vestedUser][_vestingScheduleIndex];

        if(
            block.timestamp < vestingSchedule.startTime || 
            vestingSchedule.startTime == 0 ||
            userVestingSchedules[_vestedUser].length == 0
        ){
            return 0;
        } else if (block.timestamp >= vestingSchedule.startTime + vestingSchedule.duration){
            return vestingSchedule.totalTokenAmountToVest;
        } else {
            return (vestingSchedule.totalTokenAmountToVest * (block.timestamp - vestingSchedule.startTime)) / vestingSchedule.duration;
        }
    }

    /**
        @notice sets or replaces vesting schedule
        @notice only callable by admin
        @param _vestedUser the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _vestingScheduleTotalAmount the total amount of tokens to be vested
        @param _vestingScheduleDuration the duration of the vesting schedule
        @param _vestingScheduleStartTime the start time of the vesting schedule
     */
    function setVestingSchedule(
        address _vestedUser,
        uint256 _vestingScheduleIndex,
        uint256 _vestingScheduleTotalAmount,
        uint256 _vestingScheduleDuration,
        uint256 _vestingScheduleStartTime
    ) external onlyOwner {
        _setVestingSchedule(_vestedUser, _vestingScheduleIndex, _vestingScheduleTotalAmount, _vestingScheduleDuration, _vestingScheduleStartTime);
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
}