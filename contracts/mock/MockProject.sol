//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockProject is ERC20 {
    constructor(uint decimals) ERC20("MockERC20", "MOCK") {
        uint initialSupply = 1000000000 * 10 ** decimals;
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
