//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20WithDecimals is IERC20 {
    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() external view returns (uint8);
}
