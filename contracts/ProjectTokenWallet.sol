//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

///@notice wallet to contain vested project tokens for a single invesment

contract ProjectTokenWallet is Initializable {
    using SafeERC20 for IERC20;
    address public investmentHandler;
    address public projectToken;
    error CallerIsNotInvestmentHandler();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
      _disableInitializers();
    }

    function initialize(address _investmentHandler, address _projectToken) external initializer {
        investmentHandler = _investmentHandler;
        projectToken = _projectToken;
    }

    modifier onlyInvestmentHandler() {
        if(msg.sender != investmentHandler) {
            revert CallerIsNotInvestmentHandler();
        }
        _;
    }

    function userClaim(address _to, uint256 _amount) external onlyInvestmentHandler {
        IERC20(projectToken).safeTransfer(_to, _amount);
    }

    function adminWithdraw(address _token, address _to) external onlyInvestmentHandler {
        IERC20 token = IERC20(_token);
        token.transfer(_to, token.balanceOf(address(this)));
    }

}