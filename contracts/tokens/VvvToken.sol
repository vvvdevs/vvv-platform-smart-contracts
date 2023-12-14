//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title VvvToken
 * @author @vvvfund (@curi0n-s + @c0dejax)
 */

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Capped } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract VVVToken is ERC20Capped, Ownable {

    constructor(uint256 _cap, uint256 _initialSupply) ERC20("vVvToken", "VVV") ERC20Capped(_cap) Ownable(msg.sender) {
        _mint(msg.sender, _initialSupply);
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
