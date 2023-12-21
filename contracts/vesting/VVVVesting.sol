//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVVesting is Ownable {
    //=====================================================================
    //STORAGE AND SETUP
    //=====================================================================
    using SafeERC20 for IERC20;
    IERC20 public token;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 amountWithdrawn;
        uint256 duration;
        uint256 startTime;
    }

    mapping(address => VestingSchedule[]) public userVestingSchedules;

    event SetVestingSchedule(
        address indexed _user,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _amountWithdrawn,
        uint256 _duration,
        uint256 _startTime
    );

    error AmountIsGreaterThanWithdrawable(); 
    error InvalidConstructorArguments();

    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) {
            revert InvalidConstructorArguments();
        }

        token = IERC20(_token);
    }

    //=====================================================================
    //USER
    //=====================================================================

    /**
        @notice allows user to withdraw any portion of their currently available tokens for a given vesting schedule
        @param _amount amount of tokens to withdraw
        @param _vestingScheduleIndex index of vesting schedule to withdraw from
        @dev reverts if user withdrawable amount for that schedule is less than _amount or if the contract balance is less than _amount
     */
    function withdrawVestedTokens(uint256 _amount, address _destination, uint256 _vestingScheduleIndex) external {
        VestingSchedule storage vestingSchedule = userVestingSchedules[msg.sender][_vestingScheduleIndex];

        if (_amount > getVestedAmount(msg.sender, _vestingScheduleIndex) - vestingSchedule.amountWithdrawn){
            revert AmountIsGreaterThanWithdrawable();        
        }
    
        vestingSchedule.amountWithdrawn += _amount;

        token.safeTransfer(_destination, _amount);
    }

    //=====================================================================
    //INTERNAL
    //=====================================================================

    ///@notice sets or replaces vesting schedule
    function _setVestingSchedule(
        address _user,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) private {
        VestingSchedule memory newSchedule = VestingSchedule(_totalAmount, 0, _duration, _startTime);

        if (_vestingScheduleIndex == userVestingSchedules[_user].length) {
            userVestingSchedules[_user].push(newSchedule);
        } else {
            userVestingSchedules[_user][_vestingScheduleIndex] = newSchedule;
        }

        emit SetVestingSchedule(_user, _vestingScheduleIndex, _totalAmount, 0, _duration, _startTime);
    }
    
    //=====================================================================
    //VIEW
    //=====================================================================

    function getVestingSchedule(address _user, uint256 _vestingScheduleIndex) public view returns (VestingSchedule memory) {
        return userVestingSchedules[_user][_vestingScheduleIndex];
    }

    /**
        @notice returns the amount of tokens that are currently vested (exlcudes amount withdrawn)
        @param _user the user whose withdrawable amount is being queried
        @dev considers 3 cases for calculating withdrawable amount:
            1. schedule has not started OR has not been set
            2. schedule has ended with tokens remaining to withdraw
            3. schedule is in progress with tokens remaining to withdraw
     */
    function getVestedAmount(address _user, uint256 _vestingScheduleIndex) public view returns (uint256){
        VestingSchedule storage vestingSchedule = userVestingSchedules[_user][_vestingScheduleIndex];

        if(
            block.timestamp < vestingSchedule.startTime || 
            vestingSchedule.startTime == 0
        ){
            return 0;
        } else if (block.timestamp >= vestingSchedule.startTime + vestingSchedule.duration){
            return vestingSchedule.totalAmount;
        } else {
            return (vestingSchedule.totalAmount * (block.timestamp - vestingSchedule.startTime)) / vestingSchedule.duration;
        }
    }

    //=====================================================================
    //ADMIN
    //=====================================================================

    function setVestingSchedule(
        address _user,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) external onlyOwner {
        _setVestingSchedule(_user, _vestingScheduleIndex, _totalAmount, _duration, _startTime);
    }

    ///@dev removes vesting schedule while preserving indices of other schedules
    function removeVestingSchedule(address _user, uint256 _vestingScheduleIndex) external onlyOwner {
        delete userVestingSchedules[_user][_vestingScheduleIndex];   
        emit SetVestingSchedule(_user, _vestingScheduleIndex, 0, 0, 0, 0);     
    }

}
