//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./InvestmentHandlerTestSetup.sol";

contract InvestmentHandlerTests is InvestmentHandlerTestSetup {

    /**
        creates an investment and checks it incremented latestInvestmentId within the contract
     */
    function testCreateInvestment() public {
        createInvestment();
        assertTrue(latestInvestmentIdFromTesting == investmentHandler.latestInvestmentId());
    }


    /**
        testCreateInvestment, then invests in it from a network wallet
     */
    function testInvestFromNetworkWallet() public {
        testCreateInvestment();

        uint120 investAmount = 1000000 * 1e6;
        userInvest(sampleUser, sampleKycAddress, investAmount);

        (,,,, uint128 investedPaymentToken,,,) = investmentHandler.investments(investmentHandler.latestInvestmentId());
        assertTrue(investedPaymentToken == investAmount);
    }


    /**
        testInvestFromNetworkWallet, then claims allocation, checks balance matches allocation as computed by contract
     */
    function testClaimFromNetworkWallet() public {
        testInvestFromNetworkWallet();

        uint thisInvestmentId = investmentHandler.latestInvestmentId();
        uint thisClaimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(sampleKycAddress, thisInvestmentId);

        vm.startPrank(sampleUser, sampleUser);
            investmentHandler.claim(thisInvestmentId, thisClaimAmount, sampleUser, sampleKycAddress);
        vm.stopPrank();

        assertTrue(mockProject.balanceOf(sampleUser) == thisClaimAmount);
    }
}
