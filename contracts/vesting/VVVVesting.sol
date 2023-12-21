//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVVesting is Ownable {
    using SafeERC20 for IERC20;
    
    ///@notice the token being vested
    IERC20 public token;

    /**
        @notice struct representing a user's vesting schedule
        @param totalAmount the total amount of tokens to be vested
        @param amountWithdrawn the amount of tokens that have been withdrawn
        @param duration the duration of the vesting schedule
        @param startTime the start time of the vesting schedule
     */
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 amountWithdrawn;
        uint256 duration;
        uint256 startTime;
    }

    ///@notice maps user address to array of vesting schedules
    mapping(address => VestingSchedule[]) public userVestingSchedules;

    /**
        @notice emitted when a user's vesting schedule is set or updated
        @param _address the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _totalAmount the total amount of tokens to be vested
        @param _amountWithdrawn the amount of tokens that have been withdrawn
        @param _duration the duration of the vesting schedule
        @param _startTime the start time of the vesting schedule
    */
    event SetVestingSchedule(
        address indexed _address,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _amountWithdrawn,
        uint256 _duration,
        uint256 _startTime
    );

    /**
        @notice emitted when user withdraws tokens
        @param _address the address of the user whose tokens are being withdrawn
        @param _destination the address the tokens are being sent to
        @param _amount the amount of tokens being withdrawn
        @param _vestingScheduleIndex the index of the vesting schedule the tokens are being withdrawn from
    */
    event VestedTokenWithdrawal(
        address indexed _address,
        address indexed _destination,
        uint256 _amount,
        uint256 _vestingScheduleIndex
    );

    ///@notice emitted when user tries to withdraw more tokens than are available to withdraw
    error AmountIsGreaterThanWithdrawable(); 
    
    ///@notice emitted when the contract is deployed with invalid constructor arguments
    error InvalidConstructorArguments();

    /**
        @notice constructor
        @param _token the token being vested
        @dev reverts if _token is the zero address
     */
    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) {
            revert InvalidConstructorArguments();
        }

        token = IERC20(_token);
    }

    /**
        @notice allows user to withdraw any portion of their currently available tokens for a given vesting schedule
        @param _amount amount of tokens to withdraw
        @param _destination address to send tokens to
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

        emit VestedTokenWithdrawal(msg.sender, _destination, _amount, _vestingScheduleIndex);
    }

    /**
        @notice sets or replaces vesting schedule
        @param _address the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _totalAmount the total amount of tokens to be vested
        @param _duration the duration of the vesting schedule
        @param _startTime the start time of the vesting schedule
     */
    function _setVestingSchedule(
        address _address,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) internal {
        VestingSchedule memory newSchedule = VestingSchedule(_totalAmount, 0, _duration, _startTime);

        if (_vestingScheduleIndex == userVestingSchedules[_address].length) {
            userVestingSchedules[_address].push(newSchedule);
        } else {
            userVestingSchedules[_address][_vestingScheduleIndex] = newSchedule;
        }

        emit SetVestingSchedule(_address, _vestingScheduleIndex, _totalAmount, 0, _duration, _startTime);
    }

    /**
        @notice returns a user's vesting schedule
        @param _address the address of the user whose vesting schedule is being queried
        @param _vestingScheduleIndex the index of the vesting schedule being queried
     */
    function getVestingSchedule(address _address, uint256 _vestingScheduleIndex) external view returns (VestingSchedule memory) {
        return userVestingSchedules[_address][_vestingScheduleIndex];
    }

    /**
        @notice returns the amount of tokens that are currently vested (exlcudes amount withdrawn)
        @param _address the user whose withdrawable amount is being queried
        @param _vestingScheduleIndex the index of the vesting schedule being queried
        @dev considers 3 cases for calculating withdrawable amount:
            1. schedule has not started OR has not been set
            2. schedule has ended with tokens remaining to withdraw
            3. schedule is in progress with tokens remaining to withdraw
     */
    function getVestedAmount(address _address, uint256 _vestingScheduleIndex) public view returns (uint256){
        VestingSchedule storage vestingSchedule = userVestingSchedules[_address][_vestingScheduleIndex];

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

    /**
        @notice sets or replaces vesting schedule
        @notice only callable by admin
        @param _address the address of the user whose vesting schedule is being set
        @param _vestingScheduleIndex the index of the vesting schedule being set
        @param _totalAmount the total amount of tokens to be vested
        @param _duration the duration of the vesting schedule
        @param _startTime the start time of the vesting schedule
     */
    function setVestingSchedule(
        address _address,
        uint256 _vestingScheduleIndex,
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) external onlyOwner {
        _setVestingSchedule(_address, _vestingScheduleIndex, _totalAmount, _duration, _startTime);
    }

    /**
        @notice removes vesting schedule while preserving indices of other schedules
        @notice only callable by admin
        @param _address the address of the user whose vesting schedule is being removed
        @param _vestingScheduleIndex the index of the vesting schedule being removed
     */
    function removeVestingSchedule(address _address, uint256 _vestingScheduleIndex) external onlyOwner {
        delete userVestingSchedules[_address][_vestingScheduleIndex];   
        emit SetVestingSchedule(_address, _vestingScheduleIndex, 0, 0, 0, 0);     
    }
}