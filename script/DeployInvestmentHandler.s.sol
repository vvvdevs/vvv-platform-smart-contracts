//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {InvestmentHandler} from "contracts/InvestmentHandler.sol";
import "forge-std/Script.sol";

contract DeployInvestmentHandler is Script {

    InvestmentHandler public investmentHandler;
    
    // Admin Role Addresses: Testing is msg.sender, Production is a multisig or hardware wallet for each role
    address public deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

    address public defaultAdminController = deployer;
    address public pauser = deployer;
    address public investmentManager = deployer;
    address public contributionAndRefundManager = deployer;
    address public refunder = deployer;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionAndRefundManager,
            refunder
        );

        console.log("InvestmentHandler deployed at address: %s", address(investmentHandler));
        vm.stopBroadcast();
    }
}

/**
    forge script script/DeployInvestmentHandler.s.sol:DeployInvestmentHandler --fork-url $ETH_GOERLI_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY 
    
    (optionally) --broadcast --verify

    deploys 
    0x01D1a93e9CC5f2Ab537Fcb35De4efBB5605fb808
    0x6b59209840641161b6B33BEfeC87d74c42b71838
 */