//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
    @curi0n-s initial notes
    1. this contract, assuming receipt of ERC20 tokens, cannot "react" to receipt of tokens
    2. reacting to receipt of tokens would require the token being deposited to be created using ERC223 or ERC777, which we can't assume is the case...

 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SAFTWallet is Initializable {

    // Storage 
    address projectToken;
    address projectTokenDepositor;
    address investmentHandler;

    // Events
    event Initialization(address _projectToken, address _projectTokenDepositor, address _investmentHandler);
    event TokenAddressSet(address _projectToken);

    // Errors
    error CallerIsNotInvestmentHandler();

    constructor(){} // @curi0n-s _disableInitializers here?

    modifier callerIsInvestmentHandler() {
        if(msg.sender != investmentHandler){ revert CallerIsNotInvestmentHandler(); }
        _;
    }

    /**
        @dev Initialize the contract by setting token address, depositor address, and investment handler address,
        and approving the investment handler to spend the project token, which enables claims to be made.
    */ 

    function initialize(
        address _projectToken,
        address _projectTokenDepositor,
        address _investmentHandler
    ) public initializer {
        projectToken = _projectToken;
        projectTokenDepositor = _projectTokenDepositor;
        investmentHandler = _investmentHandler;
        IERC20(projectToken).approve(investmentHandler, type(uint256).max);
        emit Initialization(_projectToken, _projectTokenDepositor, _investmentHandler);
    }

    function setTokenAddress(address _projectToken) public callerIsInvestmentHandler {
        projectToken = _projectToken;
        emit TokenAddressSet(_projectToken);
    }

}