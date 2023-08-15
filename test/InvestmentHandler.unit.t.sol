//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./InvestmentHandlerTestSetup.sol";

contract InvestmentHandlerUnitTests is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockStable(6); //usdc decimals
        mockProject = new MockProject(18); //project token
        vm.stopPrank();

        targetContract(address(investmentHandler));

        generateUserAddressListAndDealEtherAndMockStable();
    }

    /**
     * @dev creates an investment and checks it incremented latestInvestmentId within the contract
     */
    function testCreateInvestment() public {
        uint256 oldInvestmentId = investmentHandler.latestInvestmentId();
        createInvestment();
        assertTrue(investmentHandler.latestInvestmentId() == oldInvestmentId + 1);
    }

    /// @dev confirms that investment params are set correctly
    function testAlterInvestmentParams() public {
        createInvestment();
        uint8 desiredContributionPhase = 1;
        uint16 latestId = investmentHandler.latestInvestmentId();
        address newPaymentTokenAddress = address(mockStable);
        address newProjectTokenAddress = address(mockProject);
        uint256 newTokensAllocated = 123456789 * 1e18;

        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.setInvestmentContributionPhase(
            latestId,
            desiredContributionPhase,
            pauseAfterCall
        );
        investmentHandler.setInvestmentPaymentTokenAddress(
            latestId,
            newPaymentTokenAddress,
            pauseAfterCall
        );
        investmentHandler.setInvestmentProjectTokenAddress(
            latestId,
            newProjectTokenAddress,
            pauseAfterCall
        );
        investmentHandler.setInvestmentProjectTokenAllocation(
            latestId,
            newTokensAllocated,
            pauseAfterCall
        );

        vm.stopPrank();

        (
            ,
            IERC20 projectToken,
            IERC20 paymentToken,
            uint8 currentPhase,
            ,
            ,
            ,
            uint256 tokensAllocated
        ) = investmentHandler.investments(latestId);

        assertTrue(address(paymentToken) == newPaymentTokenAddress);
        assertTrue(address(projectToken) == newProjectTokenAddress);
        assertTrue(currentPhase == desiredContributionPhase);
        assertTrue(tokensAllocated == newTokensAllocated);
    }

    /**
     * @dev testCreateInvestment, then invests in it from a network wallet
     */
    function testInvestFromNetworkWallet() public {
        createInvestment();

        uint120 investAmount = 1000000 * 1e6;
        userInvest(investmentHandler.latestInvestmentId(), sampleUser, sampleKycAddress, investAmount);

        (, , , , uint128 investedPaymentToken, , , ) = investmentHandler.investments(
            investmentHandler.latestInvestmentId()
        );
        assertTrue(investedPaymentToken == investAmount);
    }

    /**
     * @dev testInvestFromNetworkWallet, then claims allocation, checks balance matches allocation as computed by contract
     */
    function testClaimFromNetworkWallet() public {
        testInvestFromNetworkWallet();
        mintProjectTokensToInvestmentHandler();

        uint16 thisInvestmentId = investmentHandler.latestInvestmentId();
        uint256 thisClaimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
            sampleKycAddress,
            thisInvestmentId
        );

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

        //unpause as PAUSER_ROLE
        vm.startPrank(defaultAdminController, defaultAdminController);
        investmentHandler.setFunctionIsPaused(investmentHandler.manualAddContribution.selector, false);
        vm.stopPrank();

        //add manual contribution as ADD_CONTRIBUTION_ROLE
        vm.startPrank(contributionManager, contributionManager);
        investmentHandler.manualAddContribution(
            _kycAddress,
            _investmentId,
            _paymentTokenAmount,
            pauseAfterCall
        );
        vm.stopPrank();

        (uint128 investedPaymentToken, , ) = investmentHandler.userInvestments(_kycAddress, _investmentId);
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
        investmentHandler.batchManualAddContribution(
            _kycAddresses,
            _investmentIds,
            _paymentTokenAmounts,
            pauseAfterCall
        );
        vm.stopPrank();

        for (uint256 i = 0; i < users.length; i++) {
            (uint128 investedPaymentToken, , ) = investmentHandler.userInvestments(
                _kycAddresses[i],
                _investmentIds[i]
            );
            assertTrue(investedPaymentToken == _paymentTokenAmounts[i]);
        }
    }

    /**
     * @dev Confirms that ERC20 transferred to the contract can be transferred away. I.e., when investment is made and payment to the project is required
     */
    function testTransferPaymentToken() public {
        testInvestFromNetworkWallet();

        uint128 transferAmount = 1000000 * 1e6;

        //unpause as PAUSER_ROLE
        vm.startPrank(defaultAdminController, defaultAdminController);
        investmentHandler.setFunctionIsPaused(investmentHandler.transferPaymentToken.selector, false);
        vm.stopPrank();

        //transfer payment token as PAYMENT_TOKEN_TRANSFER_ROLE
        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.transferPaymentToken(
            investmentHandler.latestInvestmentId(),
            sampleProjectTreasury,
            transferAmount,
            pauseAfterCall
        );
        vm.stopPrank();

        if (logging) {
            console.log(
                "mockStable.balanceOf(sampleProjectTreasury)",
                mockStable.balanceOf(sampleProjectTreasury)
            );
        }
        assert(mockStable.balanceOf(sampleProjectTreasury) == transferAmount);
    }

    /**
     * @dev confirms each function is paused and unpaused as expected
     */
    function testFunctionIsPaused() public {
        //pause addInvestment
        vm.startPrank(defaultAdminController, defaultAdminController);
        investmentHandler.setFunctionIsPaused(investmentHandler.addInvestment.selector, true);
        vm.stopPrank();

        //try to add investment
        vm.startPrank(investmentManager, investmentManager);

        vm.expectRevert();
        investmentHandler.addInvestment(signer, address(mockStable), stableAmount, pauseAfterCall);
        vm.stopPrank();

        //unpause addInvestment
        vm.startPrank(defaultAdminController, defaultAdminController);
        investmentHandler.setFunctionIsPaused(investmentHandler.addInvestment.selector, false);
        vm.stopPrank();

        //add investment
        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.addInvestment(signer, address(mockStable), stableAmount, pauseAfterCall);
        vm.stopPrank();
    }

    /**
     * @dev Ether cannot be sent to the contract - nonexistent fallback will revert
     * Strange: call reverts, yet balance of contract increases
     */
    function testSendEtherToContract() public {
        vm.deal(deployer, 1 ether);
        vm.startPrank(deployer, deployer);
        vm.expectRevert(bytes(""));
        (bool os, ) = address(investmentHandler).call{ value: 1 wei }("");
        vm.stopPrank();
        console.log("os", os);
        console.log("balance of investmentHandler", address(investmentHandler).balance);
        assertTrue(address(investmentHandler).balance == 0 wei);
    }

    /**
        This test is kinda weak...how to add random time delays and frequencies? what is worst case scenario for claims?
     */
    function testClaimsUnaffectedByClaimDelayAndFrequency() public {
        createInvestment();
        mintProjectTokensToInvestmentHandler();

        uint120 investAmount = 100000 * 1e6;
        uint256 claimAmount;
        uint16 investmentId = investmentHandler.latestInvestmentId();

        // each user invests and claims in some rearranged order
        for (uint256 i = 2; i < users.length; i++) {
            userInvest(investmentHandler.latestInvestmentId(), users[i], users[i], investAmount);
            (uint128 investedPaymentToken, , ) = investmentHandler.userInvestments(users[i], investmentId);
            assertTrue(investedPaymentToken == investAmount);
            advanceBlockNumberAndTimestamp(i);
        }

        for (uint256 i = users.length - 1; i > 1; i = i - 2) {
            claimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
                users[i],
                investmentId
            );
            userClaim(users[i], users[i], claimAmount);
            assertTrue(mockProject.balanceOf(users[i]) == claimAmount);
            advanceBlockNumberAndTimestamp(i);
        }

        for (uint256 i = users.length - 2; i > 1; i = i - 2) {
            claimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
                users[i],
                investmentId
            );
            userClaim(users[i], users[i], claimAmount);
            assertTrue(mockProject.balanceOf(users[i]) == claimAmount);
            advanceBlockNumberAndTimestamp(i);
        }
    }
}
