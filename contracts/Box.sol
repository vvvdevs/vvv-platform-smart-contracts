// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/*
proxy --> implementation
  ^
  |
  |
proxy admin
*/

contract Box {
    uint public val;

    function initialize(uint _val) external {
        val = _val;
    }
}