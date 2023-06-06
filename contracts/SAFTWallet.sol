//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SAFTWallet is Initializable {

    // Storage 
    address projectToken;
    address projectTokenDepositor;
    address investmentHandler;

    // Events

    // Errors
    error CallerIsNotInvestmentHandler();

    constructor(){} // @curi0n-s _disableInitializers here?

    modifier callerIsInvestmentHandler() {
        if(msg.sender != investmentHandler){ revert CallerIsNotInvestmentHandler(); }
        _;
    }

    function initialize(
        address _projectToken,
        address _projectTokenDepositor,
        address _investmentHandler
    ) public initializer {
        projectToken = _projectToken;
        projectTokenDepositor = _projectTokenDepositor;
        investmentHandler = _investmentHandler;
    }

    function setTokenAddress(address _projectToken) public callerIsInvestmentHandler {
        projectToken = _projectToken;
    }

}