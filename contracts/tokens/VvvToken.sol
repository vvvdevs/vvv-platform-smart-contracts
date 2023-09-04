//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title VvvToken
 * @author @vvvfund (@curi0n-s + @c0dejax)
 */

import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { ERC20Capped } from "@openzeppelin/token/ERC20/extensions/ERC20Capped.sol";

contract VVVToken is ERC20, Ownable, ERC20Capped {
    event tokensMinted (address indexed to, uint256 amount);

    constructor(uint256 _cap, uint256 _initialSupply) ERC20("vVvToken", "VVV") ERC20Capped(_cap) {
        _mint(msg.sender, _initialSupply);

        emit tokensMinted(_to, _amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
