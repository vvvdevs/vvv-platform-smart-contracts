//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**

@dev This is a minimal linear vesting contract that will be expanded upon as requirements are more clearly defined for vesting.

 */


contract MinimalLinearVesting is Ownable {
    //=====================================================================
    //STORAGE AND SETUP
    //=====================================================================
    IERC20 public token;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 amountWithdrawn;
        uint256 duration;
        uint256 startTime;
    }

    mapping(address => VestingSchedule) public userVestingSchedule;


    event SetVestingSchedule(
        address indexed _user,
        uint256 _remainingAmount,
        uint256 _duration,
        uint256 _startTime
    );

    error AmountIsGreaterThanWithdrawable(); 
    error InsufficientContractBalance();   
    error InvalidConstructorArguments();
    error VestingScheduleNotSet();
    error VestingScheduleNotStarted();
    error VestingScheduleAlreadyFulfilled();


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
        @notice allows user to withdraw any portion of their currently available tokens
        @param _amount amount of tokens to withdraw
        @dev reverts if user has no vesting schedule set, if vesting schedule has not started, if amount is greater than withdrawable amount, or if contract has insufficient balance
     */
    function withdrawVestedTokens(uint256 _amount) external {
        VestingSchedule storage vestingSchedule = userVestingSchedule[msg.sender];

        if(vestingSchedule.startTime == 0){
            revert VestingScheduleNotSet();
        } else if (block.timestamp < vestingSchedule.startTime){
            revert VestingScheduleNotStarted();
        } else if (_amount > getVestedAmount(msg.sender) - vestingSchedule.amountWithdrawn){
            revert AmountIsGreaterThanWithdrawable();        
        } else if (token.balanceOf(address(this)) < _amount){
            revert InsufficientContractBalance();
        }
    
        vestingSchedule.amountWithdrawn += _amount;

        //TODO: handle lag and slashing in future issues here or in breakout functions called here

        token.transfer(msg.sender, _amount);
    }

    //=====================================================================
    //INTERNAL
    //=====================================================================

    function _setVestingSchedule(
        address _user,
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) private {
        userVestingSchedule[_user] = VestingSchedule(_totalAmount, 0, _duration, _startTime);
        emit SetVestingSchedule(_user, _totalAmount, _duration, _startTime);
    }
    
    //=====================================================================
    //VIEW
    //=====================================================================

    function getVestingSchedule(address _user) public view returns (VestingSchedule memory) {
        return userVestingSchedule[_user];
    }

    /**
        @notice returns the amount of tokens that are currently vested (exlcudes amount withdrawn)
        @param _user the user whose withdrawable amount is being queried
        @dev considers 4 cases for calculating withdrawable amount:
            1. schedule has not started OR has not been set OR all tokens have been withdrawn
            2. schedule has ended with tokens remaining to withdraw
            3. schedule is in progress with tokens remaining to withdraw
     */

    function getVestedAmount(address _user) public view returns(uint256){
        VestingSchedule storage vestingSchedule = userVestingSchedule[_user];

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
        uint256 _totalAmount,
        uint256 _duration,
        uint256 _startTime
    ) external onlyOwner {
        _setVestingSchedule(_user, _totalAmount, _duration, _startTime);
    }
    

}
