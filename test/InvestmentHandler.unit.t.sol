//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./InvestmentHandlerTestSetup.sol";

contract InvestmentHandlerUnitTests is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockERC20(6); //usdc decimals
        mockProject = new MockERC20(18); //project token
        vm.stopPrank();

        targetContract(address(investmentHandler));

        generateUserAddressListAndDealEtherAndMockStable();
    }

    /**
     * @dev deployment test
     */
    function testDeployment() public {
        assertTrue(address(investmentHandler) != address(0));
    }

    /// @dev tests default pause config is set correctly

    function testDefaultPauseConfig() public {
        assertTrue(investmentHandler.functionIsPaused(investmentHandler.manualAddContribution.selector));
        assertTrue(investmentHandler.functionIsPaused(investmentHandler.refundUser.selector));
        assertTrue(investmentHandler.functionIsPaused(investmentHandler.transferPaymentToken.selector));
        assertTrue(investmentHandler.functionIsPaused(investmentHandler.recoverERC20.selector));
    }

    /// @dev tests adding address to kyc address network
    function testAddAddressToKycAddressNetwork() public {
        vm.startPrank(sampleKycAddress, sampleKycAddress);
        investmentHandler.addAddressToKycAddressNetwork(sampleUser);
        vm.stopPrank();
        assertTrue(investmentHandler.isInKycAddressNetwork(sampleKycAddress, sampleUser));
        assertTrue(investmentHandler.correspondingKycAddress(sampleUser) == sampleKycAddress);
    }

    /// @dev addAddressToKycAddressNetwork fails when adding address that is already in network
    function testAddAddressToKycAddressNetworkWhenAlreadyAdded() public {
        testAddAddressToKycAddressNetwork();
        vm.startPrank(sampleKycAddress, sampleKycAddress);
        vm.expectRevert(bytes4(keccak256("AddressAlreadyInKycNetwork()")));
        investmentHandler.addAddressToKycAddressNetwork(sampleUser);
        vm.stopPrank();
    }

    /// @dev tests removing address from kyc address network
    function testRemoveAddressFromKycAddressNetwork() public {
        testAddAddressToKycAddressNetwork();
        vm.startPrank(sampleKycAddress, sampleKycAddress);
        investmentHandler.removeAddressFromKycAddressNetwork(sampleUser);
        vm.stopPrank();
        assertTrue(!investmentHandler.isInKycAddressNetwork(sampleKycAddress, sampleUser));
        assertTrue(investmentHandler.correspondingKycAddress(sampleUser) == address(0));
    }

    /// @dev removeAddressFromKycAddressNetwork fails when trying to remove an address that is not in the network
    function testRemoveAddressFromKycAddressNetworkThatIsntPartOfNetwork() public {
        vm.startPrank(sampleKycAddress, sampleKycAddress);
        vm.expectRevert(bytes4(keccak256("AddressNotInKycNetwork()")));
        investmentHandler.removeAddressFromKycAddressNetwork(sampleUser);
        vm.stopPrank();
    }

    /// @dev test computing allocation correctly (claimable allocation)
    function testComputeUserClaimableAndTotalAllocationForInvestment() public {
        createInvestment();
        userInvest(
            investmentHandler.latestInvestmentId(),
            sampleUser,
            sampleKycAddress,
            1000 * 1e6 // 1000 USDC
        );

        uint16 thisInvestmentId = investmentHandler.latestInvestmentId();

        (, address projectTokenWallet, , , , , , ) = investmentHandler.investments(thisInvestmentId);
        mintProjectTokensTo(projectTokenWallet);

        uint256 thisTotalClaimAmount = investmentHandler.computeUserTotalAllocationForInvesment(
            sampleKycAddress,
            thisInvestmentId
        );

        uint256 thisCurrentClaimableAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
            sampleKycAddress,
            thisInvestmentId
        );

        uint256 projectToPaymentRatio = IERC20(mockProject).balanceOf(projectTokenWallet) /
            IERC20(mockStable).balanceOf(address(investmentHandler));

        (uint128 investedPaymentToken, ) = investmentHandler.userInvestments(
            sampleKycAddress,
            thisInvestmentId
        );

        assertTrue(thisTotalClaimAmount / investedPaymentToken == projectToPaymentRatio);
        assertTrue(thisCurrentClaimableAmount / investedPaymentToken == projectToPaymentRatio);
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

        //now test expected revert for chaing payment token after investments start. will revert even if called with same token address
        userInvest(latestId, sampleUser, sampleKycAddress, 1000000 * 1e6);

        vm.startPrank(investmentManager, investmentManager);
        vm.expectRevert(bytes4(keccak256("InvestmentTokenAlreadyDeposited()")));
        investmentHandler.setInvestmentPaymentTokenAddress(
            latestId,
            newPaymentTokenAddress,
            pauseAfterCall
        );
        vm.stopPrank();

        (
            ,   
            ,
            IERC20 projectToken,
            IERC20 paymentToken,
            uint8 currentPhase,
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
     * @dev test investing from kyc wallet
     */
    function testInvestFromKycWallet() public {
        createInvestment();

        uint120 investAmount = 1000000 * 1e6;
        userInvest(investmentHandler.latestInvestmentId(), sampleKycAddress, sampleKycAddress, investAmount);

        (, , , , , uint128 investedPaymentToken, , ) = investmentHandler.investments(
            investmentHandler.latestInvestmentId()
        );
        assertTrue(investedPaymentToken == investAmount);
    }

    /**
     * @dev testCreateInvestment, then invests in it from a network wallet
     */
    function testInvestFromNetworkWallet() public {
        createInvestment();

        uint120 investAmount = 1000000 * 1e6;
        userInvest(investmentHandler.latestInvestmentId(), sampleUser, sampleKycAddress, investAmount);

        (, , , , , uint128 investedPaymentToken, , ) = investmentHandler.investments(
            investmentHandler.latestInvestmentId()
        );
        assertTrue(investedPaymentToken == investAmount);
    }

    /**
     * @dev testInvestFromNetworkWallet, then claims allocation, checks balance matches allocation as computed by contract
     */
    function testClaimFromNetworkWallet() public {
        testInvestFromNetworkWallet();

        uint16 thisInvestmentId = investmentHandler.latestInvestmentId();
        
        (, address projectTokenWallet, , , , , , ) = investmentHandler.investments(thisInvestmentId);
        mintProjectTokensTo(projectTokenWallet);
        
        uint256 thisClaimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
            sampleKycAddress,
            thisInvestmentId
        );

        vm.startPrank(sampleUser, sampleUser);

        InvestmentHandler.ClaimParams memory params = InvestmentHandler.ClaimParams({
            investmentId: thisInvestmentId,
            claimAmount: uint240(thisClaimAmount),
            tokenRecipient: sampleUser,
            kycAddress: sampleKycAddress
        });

        investmentHandler.claim(params);
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
        vm.startPrank(pauser, pauser);
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

        (uint128 investedPaymentToken , ) = investmentHandler.userInvestments(_kycAddress, _investmentId);
        assertTrue(investedPaymentToken == _paymentTokenAmount);
    }

    /// @dev sequence: add investments, then add data for each investment with arrays
    function testAddPreviousInvestmentData() public {
        uint16 numInvestments = 10;
        for (uint256 i = 0; i < numInvestments; i++) {
            createInvestment();
        }

        address[] memory _kycAddresses = new address[](numInvestments);
        uint16[] memory _investmentIds = new uint16[](numInvestments);
        uint128[] memory _paymentTokenAmounts = new uint128[](numInvestments);

        //get a slice of users and write to _kycAddresses
        for (uint256 i = 0; i < numInvestments; i++) {
            _kycAddresses[i] = users[i + 4]; //some buffer to not interfere with sample addresses
        }

        for (uint16 i = 0; i < numInvestments; i++) {
            _investmentIds[i] = i + 1;
            _paymentTokenAmounts[i] = 1000000 * 1e6; // 1M USDC
        }

        vm.startPrank(contributionManager, contributionManager);
        investmentHandler.batchManualAddContribution(
            _kycAddresses,
            _investmentIds,
            _paymentTokenAmounts,
            pauseAfterCall
        );

        // revert when array lengths are not matching
        uint16[] memory _mistakeInvestmentIds = new uint16[](numInvestments - 1);
        for (uint16 i = 0; i < numInvestments - 1; i++) {
            _mistakeInvestmentIds[i] = i + 1;
        }
        vm.expectRevert(bytes4(keccak256("ArrayLengthMismatch()")));
        investmentHandler.batchManualAddContribution(
            _kycAddresses,
            _mistakeInvestmentIds,
            _paymentTokenAmounts,
            pauseAfterCall
        );

        vm.stopPrank();

        for (uint256 i = 0; i < numInvestments; i++) {
            (uint128 investedPaymentToken, ) = investmentHandler.userInvestments(
                _kycAddresses[i],
                _investmentIds[i]
            );
            assertTrue(investedPaymentToken == _paymentTokenAmounts[i]);
        }
    }

    /// @dev test refundUser and its requirements. unpauses relevant functions, then refunds user less than total invested balance, checks revert conditions, then checks balance changes post-refund
    function testRefundUser() public {
        createInvestment();
        uint16 _investmentId = investmentHandler.latestInvestmentId();
        uint120 _investAmount = 100000 * 1e6; // 1M USDC
        uint128 _claimAmount = 10000 * 1e6; // 100k USDC
        userInvest(_investmentId, sampleUser, sampleKycAddress, _investAmount);
        (uint128 investedPaymentTokenBeforeRefund, ) = investmentHandler.userInvestments(
            sampleKycAddress,
            _investmentId
        );

        //unpause as PAUSER_ROLE
        vm.startPrank(pauser, pauser);
        investmentHandler.setFunctionIsPaused(investmentHandler.refundUser.selector, false);
        vm.stopPrank();

        //refund user as REFUNDER_ROLE
        vm.startPrank(refundManager, refundManager);
        investmentHandler.refundUser(sampleKycAddress, _investmentId, _claimAmount, pauseAfterCall);
        vm.stopPrank();

        //revert case 1 refunding more than user invested
        vm.startPrank(refundManager, refundManager);
        vm.expectRevert(bytes4(keccak256("RefundAmountExceedsUserBalance()")));
        investmentHandler.refundUser(
            sampleKycAddress,
            _investmentId,
            _claimAmount * 10,
            pauseAfterCall //false
        );
        vm.stopPrank();

        // revert case 2 refunding when project tokens have been deposited (aka claims could have started already)
        (, address projectTokenWallet, , , , , , ) = investmentHandler.investments(_investmentId);
        mintProjectTokensTo(projectTokenWallet);

        vm.startPrank(refundManager, refundManager);
        vm.expectRevert(bytes4(keccak256("TooLateForRefund()")));
        investmentHandler.refundUser(sampleKycAddress, _investmentId, uint120(1), pauseAfterCall);
        vm.stopPrank();

        (uint128 investedPaymentTokenAfterRefund, ) = investmentHandler.userInvestments(
            sampleKycAddress,
            _investmentId
        );
        assertTrue(investedPaymentTokenBeforeRefund == _investAmount);
        assertTrue(investedPaymentTokenAfterRefund == _investAmount - _claimAmount);
    }

    /**
     * @dev Confirms that ERC20 transferred to the contract can be transferred away. I.e., when investment is made and payment to the project is required
     */
    function testTransferPaymentToken() public {
        uint120 transferAmount = 1000 * 1e6;
        createInvestment();
        userInvest(investmentHandler.latestInvestmentId(), sampleUser, sampleKycAddress, transferAmount);

        //unpause as PAUSER_ROLE
        vm.startPrank(pauser, pauser);
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

        //revert case 1 non-existent investment ID
        vm.startPrank(investmentManager, investmentManager);

        console.log("investmentId", investmentHandler.latestInvestmentId());
        console.log("paymentTokenBalance", mockStable.balanceOf(address(investmentHandler)));

        uint16 latestInvestmentId = investmentHandler.latestInvestmentId();
        vm.expectRevert(bytes4(keccak256("InvestmentDoesNotExist()")));
        investmentHandler.transferPaymentToken(
            latestInvestmentId + 1,
            sampleProjectTreasury,
            transferAmount,
            pauseAfterCall
        );
        vm.stopPrank();

        //revert case 2 transfer amount exceeds contract balance for that investment
        vm.startPrank(investmentManager, investmentManager);
        vm.expectRevert(bytes4(keccak256("TransferAmountExceedsInvestmentBalance()")));
        investmentHandler.transferPaymentToken(
            latestInvestmentId,
            sampleProjectTreasury,
            transferAmount * 2,
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

    function testRecoverERC20() public {
        uint256 recoverAmount = 1000 * 1e6;
        mockProject.mint(address(investmentHandler), recoverAmount);

        //unpause function as PAUSER_ROLE
        vm.startPrank(pauser, pauser);
        investmentHandler.setFunctionIsPaused(investmentHandler.recoverERC20.selector, false);
        vm.stopPrank();

        //recover ERC20 as PAYMENT_TOKEN_TRANSFER_ROLE
        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.recoverERC20(
            address(mockProject),
            investmentManager,
            recoverAmount,
            pauseAfterCall
        );
        vm.stopPrank();

        //revert case, recover more than balance
        vm.startPrank(investmentManager, investmentManager);
        vm.expectRevert();
        investmentHandler.recoverERC20(
            address(mockProject),
            investmentManager,
            recoverAmount * 2,
            pauseAfterCall
        );
        vm.stopPrank();

        assertTrue(mockProject.balanceOf(address(investmentHandler)) == 0);
    }

    /**
     * @dev confirms each function is paused and unpaused as expected
     */
    function testFunctionIsPaused() public {
        allocatedPaymentTokenPerPhase = [
            0,
            stableAmount,
            stableAmount,
            stableAmount,
            stableAmount
        ];


        //pause addInvestment
        vm.startPrank(pauser, pauser);
        investmentHandler.setFunctionIsPaused(investmentHandler.addInvestment.selector, true);
        vm.stopPrank();

        //try to add investment
        vm.startPrank(investmentManager, investmentManager);

        vm.expectRevert();
        investmentHandler.addInvestment(signer, address(mockStable), allocatedPaymentTokenPerPhase, pauseAfterCall);
        vm.stopPrank();

        //unpause addInvestment
        vm.startPrank(pauser, pauser);
        investmentHandler.setFunctionIsPaused(investmentHandler.addInvestment.selector, false);
        vm.stopPrank();

        //add investment
        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.addInvestment(signer, address(mockStable), allocatedPaymentTokenPerPhase, pauseAfterCall);
        vm.stopPrank();
    }

    /// @dev batch set function is paused
    function testBatchSetFunctionIsPaused() public {
        // function selector array
        bytes4[] memory functionSelectors = new bytes4[](13);
        functionSelectors[0] = investmentHandler.claim.selector;
        functionSelectors[1] = investmentHandler.invest.selector;
        functionSelectors[2] = investmentHandler.addAddressToKycAddressNetwork.selector;
        functionSelectors[3] = investmentHandler.removeAddressFromKycAddressNetwork.selector;
        functionSelectors[4] = investmentHandler.addInvestment.selector;
        functionSelectors[5] = investmentHandler.setInvestmentContributionPhase.selector;
        functionSelectors[6] = investmentHandler.setInvestmentPaymentTokenAddress.selector;
        functionSelectors[7] = investmentHandler.setInvestmentProjectTokenAddress.selector;
        functionSelectors[8] = investmentHandler.setInvestmentProjectTokenAllocation.selector;
        functionSelectors[9] = investmentHandler.manualAddContribution.selector;
        functionSelectors[10] = investmentHandler.refundUser.selector;
        functionSelectors[11] = investmentHandler.transferPaymentToken.selector;
        functionSelectors[12] = investmentHandler.recoverERC20.selector;

        bool[] memory isPaused = new bool[](13);
        for (uint256 i = 0; i < isPaused.length; i++) {
            isPaused[i] = true;
        }

        // pause all functions
        vm.startPrank(pauser, pauser);
        investmentHandler.batchSetFunctionIsPaused(functionSelectors, isPaused);
        vm.stopPrank();

        //confirm all are paused
        for (uint256 i = 0; i < isPaused.length; i++) {
            assertTrue(investmentHandler.functionIsPaused(functionSelectors[i]));
        }
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

        uint120 investAmount = 100000 * 1e6;
        uint256 claimAmount;
        uint16 investmentId = investmentHandler.latestInvestmentId();

        (, address projectTokenWallet, , , , , , ) = investmentHandler.investments(investmentId);
        mintProjectTokensTo(projectTokenWallet);

        // each user invests and claims in some rearranged order
        for (uint256 i = 2; i < users.length; i++) {
            userInvest(investmentHandler.latestInvestmentId(), users[i], users[i], investAmount);
            (uint128 investedPaymentToken, ) = investmentHandler.userInvestments(users[i], investmentId);
            assertTrue(investedPaymentToken == investAmount);
            advanceBlockNumberAndTimestamp(i);
        }

        for (uint256 i = users.length - 1; i > 1; i = i - 2) {
            claimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
                users[i],
                investmentId
            );
            userClaim(users[i], users[i], uint240(claimAmount));
            assertTrue(mockProject.balanceOf(users[i]) == claimAmount);
            advanceBlockNumberAndTimestamp(i);
        }

        for (uint256 i = users.length - 2; i > 1; i = i - 2) {
            claimAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
                users[i],
                investmentId
            );
            userClaim(users[i], users[i], uint240(claimAmount));
            assertTrue(mockProject.balanceOf(users[i]) == claimAmount);
            advanceBlockNumberAndTimestamp(i);
        }
    }


    /**
        @dev tests that no user can invest with false info. i.e. the signature check is functioning as expected.
        @dev getSignature() is the equivalent of what would be run on the backend, and requires security of the signer's private key
     */
    function testInvestWithConflictingInfo() public {
        // tests only investment amount being 1 uint off

        uint120 maxInvestAmount = 100 * 1e6;
        uint8 thisPhase = 1;

        bytes memory thisSignature = getSignature(
            uint16(investmentHandler.latestInvestmentId()),
            sampleUser,
            maxInvestAmount,
            thisPhase
        );

        InvestmentHandler.InvestParams memory investParams1 = InvestmentHandler.InvestParams({
            investmentId: uint16(investmentHandler.latestInvestmentId() + 1),
            thisInvestmentAmount: maxInvestAmount,
            maxInvestableAmount: uint120(maxInvestAmount + 1),
            userPhase: 1,
            kycAddress: sampleUser,
            signature: thisSignature
        });

        InvestmentHandler.InvestParams memory investParams2 = InvestmentHandler.InvestParams({
            investmentId: uint16(investmentHandler.latestInvestmentId()),
            thisInvestmentAmount: maxInvestAmount + 1,
            maxInvestableAmount: uint120(maxInvestAmount),
            userPhase: 1,
            kycAddress: sampleUser,
            signature: thisSignature
        });

        InvestmentHandler.InvestParams memory investParams3 = InvestmentHandler.InvestParams({
            investmentId: uint16(investmentHandler.latestInvestmentId()),
            thisInvestmentAmount: maxInvestAmount,
            maxInvestableAmount: uint120(maxInvestAmount + 1),
            userPhase: 1,
            kycAddress: sampleUser,
            signature: thisSignature
        });

        InvestmentHandler.InvestParams memory investParams4 = InvestmentHandler.InvestParams({
            investmentId: uint16(investmentHandler.latestInvestmentId()),
            thisInvestmentAmount: maxInvestAmount,
            maxInvestableAmount: uint120(maxInvestAmount),
            userPhase: 1 + 1,
            kycAddress: sampleUser,
            signature: thisSignature
        });

        InvestmentHandler.InvestParams memory investParams5 = InvestmentHandler.InvestParams({
            investmentId: uint16(investmentHandler.latestInvestmentId()),
            thisInvestmentAmount: maxInvestAmount,
            maxInvestableAmount: uint120(maxInvestAmount),
            userPhase: 1,
            kycAddress: users[13], //random user
            signature: thisSignature
        });

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        investmentHandler.invest(investParams1);
        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        investmentHandler.invest(investParams2);
        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        investmentHandler.invest(investParams3);
        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        investmentHandler.invest(investParams4);
        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        investmentHandler.invest(investParams5);
        vm.stopPrank();

    }
}
