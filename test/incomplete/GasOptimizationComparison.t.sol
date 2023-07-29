//SPDX-License-Identifier: MIT

/**
 * look at --gas-report to compare outputs
 * issues with signature creation being valid...
 */

pragma solidity 0.8.20;

import "lib/forge-std/src/Test.sol";
import "test/InvestmentHandlerTestSetup.sol";
import { InvestmentHandler } from "contracts/InvestmentHandler.sol";
import { InvestmentHandlerUnoptimized } from "contracts/ref/InvestmentHandlerUnoptimized.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";

contract InvestmentHandlerGasSavingsTest is Test, InvestmentHandlerTestSetup {

    InvestmentHandlerUnoptimized public investmentHandlerUnoptimized;
    
    function setUpUnoptimized() public {
        vm.startPrank(deployer, deployer);
            investmentHandlerUnoptimized = new InvestmentHandlerUnoptimized();
            mockStable = new MockERC20(6); //usdc decimals
            mockProject = new MockERC20(18); //project token
        vm.stopPrank();        
    }

    function createInvestmentOnUnoptimized() public {
        vm.startPrank(deployer, deployer);
            investmentHandlerUnoptimized.addInvestment(deployer, address(mockStable), 1500000 * 1e18);
            investmentHandlerUnoptimized.setInvestmentProjectTokenAddress(latestInvestmentId, address(mockProject));
        vm.stopPrank();
    }

    function testBoth() public {   
        setUpUnoptimized();
        createInvestmentOnUnoptimized(); //102675 median
        createInvestment(); // 96408 median
        userInvestUnoptimized(users[0], users[0], stableAmount);
        // userInvest(users[0], users[0], 1000000 * 1e6);
    }

    function userInvestUnoptimized(address _caller, address _kycAddress, uint _amount) public {
            vm.startPrank(deployer, deployer);
                bytes memory thisSignature = getSignatureUnoptimized(_kycAddress, _amount, phase);
            vm.stopPrank();

            vm.startPrank(_caller, _caller);
                mockStable.approve(address(investmentHandler), type(uint).max);
                
                InvestmentHandlerUnoptimized.InvestParams memory investParams = InvestmentHandlerUnoptimized.InvestParams({
                    investmentId: investmentHandlerUnoptimized.latestInvestmentId(),
                    maxInvestableAmount: _amount,
                    thisInvestmentAmount: _amount,
                    userPhase: 1,
                    kycAddress: _kycAddress,
                    signature: thisSignature
                });
                
                investmentHandlerUnoptimized.invest(investParams);
            vm.stopPrank();
    }

    function getSignatureUnoptimized(address _user, uint _amount, uint _phase) public view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            _user,
            _amount,
            _phase
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, messageHash);
        return toBytesConcat(r, s, v);
    }


}