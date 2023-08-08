//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./InvestmentHandlerTestSetup.sol";

contract InvestmentHandlerUnitTests is InvestmentHandlerTestSetup {
    
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler =
            new InvestmentHandler(defaultAdminController, investmentManager, contributionManager, refundManager);
        mockStable = new MockERC20(6); //usdc decimals
        mockProject = new MockERC20(18); //project token
        vm.stopPrank();

        targetContract(address(investmentHandler));

        generateUserAddressListAndDealEtherAndMockERC20();
    }

    /**
     * creates an investment and checks it incremented latestInvestmentId within the contract
     */
    function testCreateInvestment() public {
        createInvestment();
        assertTrue(ghost_latestInvestmentId == investmentHandler.latestInvestmentId());
    }

    /**
     * testCreateInvestment, then invests in it from a network wallet
     */
    function testInvestFromNetworkWallet() public {
        createInvestment();

        uint120 investAmount = 1000000 * 1e6;
        userInvest(sampleUser, sampleKycAddress, investAmount);

        (,,,, uint128 investedPaymentToken,,,) = investmentHandler.investments(investmentHandler.latestInvestmentId());
        assertTrue(investedPaymentToken == investAmount);
    }

    /**
     * testInvestFromNetworkWallet, then claims allocation, checks balance matches allocation as computed by contract
     */
    function testClaimFromNetworkWallet() public {
        testInvestFromNetworkWallet();

        uint16 thisInvestmentId = investmentHandler.latestInvestmentId();
        uint256 thisClaimAmount =
            investmentHandler.computeUserClaimableAllocationForInvestment(sampleKycAddress, thisInvestmentId);

        vm.startPrank(sampleUser, sampleUser);
            investmentHandler.claim(thisInvestmentId, thisClaimAmount, sampleUser, sampleKycAddress);
        vm.stopPrank();

        assertTrue(mockProject.balanceOf(sampleUser) == thisClaimAmount);
    }

    /// @dev add single investment and contribution to measure gas for manualAddContribution
    function testManualAddSingleContribution() public {
        createInvestment();
        address _kycAddress = users[0];
        uint16 _investmentId = investmentHandler.latestInvestmentId();
        uint128 _paymentTokenAmount = 1000000 * 1e6; // 1M USDC

        vm.startPrank(contributionManager, contributionManager);
            investmentHandler.manualAddContribution(_kycAddress, _investmentId, _paymentTokenAmount);
        vm.stopPrank();
        
        (uint128 investedPaymentToken,,)=investmentHandler.userInvestments(_kycAddress, _investmentId);
        assertTrue(investedPaymentToken == _paymentTokenAmount);
    }

    /// @dev sequence: add investments, then add data for each investment with arrays
    function testAddPreviousInvestmentData() public {
        uint16 numInvestments = 10;
        for (uint256 i = 0; i < numInvestments; i++) {
            createInvestment();
        }

        address[] memory _kycAddresses = users;
        uint16[] memory _investmentIds = new uint16[](users.length);
        uint128[] memory _paymentTokenAmounts = new uint128[](users.length);

        for (uint16 i = 0; i < users.length; i++) {
            _investmentIds[i] = numInvestments % (i + 1);
            _paymentTokenAmounts[i] = 1000000 * 1e6; // 1M USDC
        }

        vm.startPrank(contributionManager, contributionManager);
        investmentHandler.batchManualAddContribution(_kycAddresses, _investmentIds, _paymentTokenAmounts);
        vm.stopPrank();

        for (uint256 i = 0; i < users.length; i++) {
            (uint128 investedPaymentToken,,) =
                investmentHandler.userInvestments(_kycAddresses[i], _investmentIds[i]);
            assertTrue(investedPaymentToken == _paymentTokenAmounts[i]);
        }
    }

    function testTransferPaymentToken() public {
        testInvestFromNetworkWallet();

        uint128 transferAmount = 1000000 * 1e6;

        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.transferPaymentToken(
            investmentHandler.latestInvestmentId(),
            sampleProjectTreasury,
            transferAmount
        );
        
        if(logging) console.log("mockStable.balanceOf(sampleProjectTreasury)", mockStable.balanceOf(sampleProjectTreasury));
        assert(mockStable.balanceOf(sampleProjectTreasury) == transferAmount);
    }

    function testFunctionIsPaused() public {
        //pause addInvestment
        vm.startPrank(defaultAdminController, defaultAdminController);
            investmentHandler.pauseFunction(investmentHandler.addInvestment.selector, true);
        vm.stopPrank();

        //try to add investment
        vm.startPrank(investmentManager, investmentManager);
            bytes4 FUNCTION_IS_PAUSED_SELECTOR = bytes4(keccak256("FunctionIsPaused()"));
            vm.expectRevert(FUNCTION_IS_PAUSED_SELECTOR);
            investmentHandler.addInvestment(signer, address(mockStable), stableAmount);
        vm.stopPrank();

        //unpause addInvestment
        vm.startPrank(defaultAdminController, defaultAdminController);
            investmentHandler.pauseFunction(investmentHandler.addInvestment.selector, false);
        vm.stopPrank();

        //add investment
        vm.startPrank(investmentManager, investmentManager);
            investmentHandler.addInvestment(signer, address(mockStable), stableAmount);
        vm.stopPrank();
        
    }


}
