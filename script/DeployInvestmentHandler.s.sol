//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {InvestmentHandler} from "contracts/InvestmentHandler.sol";
import "forge-std/Script.sol";

contract DeployInvestmentHandler is Script {

    InvestmentHandler public investmentHandler;
    
    // Admin Role Addresses: Testing is msg.sender, Production is a multisig or hardware wallet for each role
    address public defaultAdminController = msg.sender;
    address public pauser = msg.sender;
    address public investmentManager = msg.sender;
    address public contributionAndRefundManager = msg.sender;
    address public refunder = msg.sender;

    function run() public {
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionAndRefundManager,
            refunder
        );

        console.log("InvestmentHandler deployed at address: %s", address(investmentHandler));
    }
}

/**
    forge script script/DeployInvestmentHandler.s.sol:DeployInvestmentHandler --fork-url $ETH_GOERLI_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY 
    
    (optionally) --broadcast --verify
 */