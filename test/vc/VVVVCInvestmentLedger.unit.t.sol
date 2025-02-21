//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { IERC20WithDecimals } from "contracts/tokens/IERC20WithDecimals.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
/**
 * @title VVVVCInvestmentLedger Unit Tests
 * @dev use "forge test --match-contract VVVVCInvestmentLedgerUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCInvestmentLedger" to run coverage
 */
contract VVVVCInvestmentLedgerUnitTests is VVVVCTestBase {
    /// @notice sets up project and payment tokens, and an instance of the investment ledger
    function setUp() public {
        vm.startPrank(deployer, deployer);

        ProjectTokenInstance = new MockERC20(18);
        PaymentTokenInstance = new MockERC20(6); //usdc has 6 decimals

        //deploy auth registry (deployer is default admin)
        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);

        LedgerInstance = new VVVVCInvestmentLedger(
            testSigner,
            environmentTag,
            address(AuthRegistry),
            exchangeRateDenominator
        );

        //grant ledgerManager the ledgerManagerRole
        AuthRegistry.grantRole(ledgerManagerRole, ledgerManager);

        //add permissions to ledgerManagerRole for withdraw and addInvestmentRecord on the LedgerInstance
        bytes4 withdrawSelector = LedgerInstance.withdraw.selector;
        bytes4 addInvestmentRecordsSelector = LedgerInstance.addInvestmentRecords.selector;
        bytes4 setInvestmentPausedSelector = LedgerInstance.setInvestmentIsPaused.selector;
        bytes4 setDecimalsSelector = LedgerInstance.setDecimals.selector;
        AuthRegistry.setPermission(address(LedgerInstance), withdrawSelector, ledgerManagerRole);
        AuthRegistry.setPermission(
            address(LedgerInstance),
            addInvestmentRecordsSelector,
            ledgerManagerRole
        );
        AuthRegistry.setPermission(
            address(LedgerInstance),
            setInvestmentPausedSelector,
            ledgerManagerRole
        );
        AuthRegistry.setPermission(address(LedgerInstance), setDecimalsSelector, ledgerManagerRole);

        ledgerDomainSeparator = LedgerInstance.computeDomainSeparator();
        investmentTypehash = LedgerInstance.INVESTMENT_TYPEHASH();

        PaymentTokenInstance.mint(sampleUser, paymentTokenMintAmount); //10k tokens

        generateUserAddressListAndDealEtherAndToken(PaymentTokenInstance);

        vm.stopPrank();
    }

    /// @notice Tests deployment of VVVVCInvestmentLedger
    function testDeployment() public {
        assertTrue(address(LedgerInstance) != address(0));
    }

    /**
     * @notice Tests creation and validation of EIP712 signatures
     * @dev defines an InvestParams struct, creates a signature for it, and validates it with the same struct parameters
     */
    function testValidateSignature() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        vm.prank(sampleUser);
        assertTrue(LedgerInstance.isSignatureValid(params));
    }

    /**
     * @notice Test that a false signature is not validated
     * @dev defines an InvestParams struct, creates a signature for it, and validates it with different struct parameters
     */
    function testInvalidateFalseSignature() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        //round start timestamp is off by one second
        params.investmentRoundStartTimestamp += 1;

        vm.prank(sampleUser);
        assertFalse(LedgerInstance.isSignatureValid(params));
    }

    /**
     * @notice Test that a valid signature with the wrong signer for the ledger is not validated
     */
    function testInvalidSignatureWrongSigner() public {
        // Generate params with the default test signer
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        // but deploy another ledger with a different signer
        address differentSigner = makeAddr("differentSigner");
        VVVVCInvestmentLedger newLedger = new VVVVCInvestmentLedger(
            differentSigner,
            environmentTag,
            address(AuthRegistry),
            exchangeRateDenominator
        );

        vm.prank(sampleUser);
        assertFalse(newLedger.isSignatureValid(params));
    }

    /**
     * @notice Tests that an otherwise would-be-valid but expired signature is invalid
     */
    function testInvalidSignatureExpired() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        // Advance time past the deadline of 1 hour
        advanceBlockNumberAndTimestampInSeconds(1 hours + 2);

        vm.prank(sampleUser);
        assertFalse(LedgerInstance.isSignatureValid(params));
    }

    /// @notice Tests that a wrong amountToInvest param is not validated
    function testInvalidAmountToInvest() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        // change amountToInvest to be +1
        params.amountToInvest += 1;

        vm.prank(sampleUser);
        assertFalse(LedgerInstance.isSignatureValid(params));
    }

    /**
     * @notice Tests investment function call by user
     * @dev defines an InvestParams struct, creates a signature for it, validates it, and invests some PaymentToken
     */
    function testInvest() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        uint256 preInvestBalance = PaymentTokenInstance.balanceOf(sampleUser);
        uint256 feeAmount = (params.amountToInvest * params.feeNumerator) /
            LedgerInstance.FEE_DENOMINATOR();

        investAsUser(sampleUser, params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(
            PaymentTokenInstance.balanceOf(address(LedgerInstance)) == params.amountToInvest + feeAmount
        );
        assertTrue(
            PaymentTokenInstance.balanceOf(sampleUser) + params.amountToInvest + feeAmount ==
                preInvestBalance
        );
    }

    ///@notice same as above, just with zero fee to confirm this works as well
    function testInvestZeroFee() public {
        uint256 feeNumerator = 0;

        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        uint256 preInvestBalance = PaymentTokenInstance.balanceOf(sampleUser);

        investAsUser(sampleUser, params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == params.amountToInvest);
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) + params.amountToInvest == preInvestBalance);
    }

    /**
        @notice Tests investment function call by user with two exchange rates to confirm the invested amount reflects the exchange rate
     */
    function testInvestNewExchangeRate() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );
        investAsUser(sampleUser, params);
        uint256 userInvested = LedgerInstance.kycAddressInvestedPerRound(
            sampleKycAddress,
            sampleInvestmentRoundIds[0]
        );

        //double default exchange rate of 1e6, so the stablecoin equivalent for a given amount of payment tokens is halved
        uint256 newExchangeRateNumerator = 2e6;

        VVVVCInvestmentLedger.InvestParams memory params2 = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            newExchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );
        investAsUser(sampleUser, params2);
        uint256 userInvested2 = LedgerInstance.kycAddressInvestedPerRound(
            sampleKycAddress,
            sampleInvestmentRoundIds[0]
        );

        //confirm that the stable-equivalent invested amount of the 2nd investment is double that of the first
        //after the 2nd investment, the 1st investment should account for 1/3rd of total invested
        assertTrue(
            userInvested2 ==
                userInvested +
                    (userInvested * newExchangeRateNumerator) /
                    LedgerInstance.exchangeRateDenominator()
        );
    }

    /**
     * @notice Tests that a user can invest multiple times in a single round within the user and round limits
     * @dev in generateInvestParamsWithSignature, the user is allocated 1000 tokens, and the round limit is 10000 tokens
     * @dev so 10 investments work, but 11 won't
     */
    function testMultipleInvestmentsInSingleRound() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        uint256 numberOfInvestments = 10;
        uint256 feeAmount = (params.amountToInvest * params.feeNumerator) /
            LedgerInstance.FEE_DENOMINATOR();

        for (uint256 i = 0; i < numberOfInvestments; i++) {
            investAsUser(sampleUser, params);
        }

        assertTrue(
            PaymentTokenInstance.balanceOf(address(LedgerInstance)) ==
                (params.amountToInvest + feeAmount) * numberOfInvestments
        );
    }

    /**
     * @notice Tests that a user cannot invest when the investment round is not active and the InactiveInvestmentRound error is thrown, when the round has not yet started
     */
    function testInvestInactiveRoundBeforeStart() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            block.timestamp + 1 days,
            block.timestamp + 2 days
        );

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCInvestmentLedger.InactiveInvestmentRound.selector);
        LedgerInstance.invest(params);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot invest when the investment round is not active and the InactiveInvestmentRound error is thrown, when the round has ended
     */
    function testInvestInactiveRoundAfterEnd() public {
        advanceBlockNumberAndTimestampInSeconds(10 days);

        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            block.timestamp - 2 days,
            block.timestamp - 1 days
        );

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCInvestmentLedger.InactiveInvestmentRound.selector);
        LedgerInstance.invest(params);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot invest multiple times in a single round to exceed their allocation. 
     10 investments work but the 11th will revert. userPaymentTokenDefaultAllocation is 10,000,
     and each investment amount (sampleAmountsToInvest[0]) is 1,000.
     */
    function testTooManyInvestmentsInSingleRound() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        uint256 numberOfInvestments = 10;
        uint256 feeAmount = (params.amountToInvest * params.feeNumerator) /
            LedgerInstance.FEE_DENOMINATOR();

        for (uint256 i = 0; i < numberOfInvestments; i++) {
            investAsUser(sampleUser, params);
        }

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCInvestmentLedger.ExceedsAllocation.selector);
        LedgerInstance.invest(params);
        vm.stopPrank();

        assertTrue(
            PaymentTokenInstance.balanceOf(address(LedgerInstance)) ==
                (params.amountToInvest + feeAmount) * numberOfInvestments
        );
    }

    // @notice Tests that a payment token with a number of decimals that exceeds the contract's is not accepted.
    function testInvestUnsupportedPaymentTokenDecimals() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.setDecimals(5);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCInvestmentLedger.UnsupportedPaymentTokenDecimals.selector);
        LedgerInstance.invest(params);
        vm.stopPrank();
    }

    /**
     * @notice Tests investment function call by user with invalid signature
     * @dev defines an InvestParams struct, creates a signature for it, changes a param and should fail to invest
     */
    function test_RevertWhen_InvestWithInvalidSignature() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        params.investmentRoundStartTimestamp += 1;

        vm.expectRevert(VVVVCInvestmentLedger.InvalidSignature.selector);
        vm.prank(sampleUser);
        LedgerInstance.invest(params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == 0);
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) == paymentTokenMintAmount);
    }

    /**
     * @notice Tests withdraw of ERC20 tokens by admin
     */
    function testWithdrawPostInvestment() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        investAsUser(sampleUser, params);

        uint256 preTransferRecipientBalance = PaymentTokenInstance.balanceOf(deployer);
        uint256 preTransferContractBalance = PaymentTokenInstance.balanceOf(address(LedgerInstance));

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.withdraw(
            params.paymentTokenAddress,
            deployer,
            PaymentTokenInstance.balanceOf(address(LedgerInstance))
        );
        vm.stopPrank();

        uint256 postTransferRecipientBalance = PaymentTokenInstance.balanceOf(deployer);

        assertTrue(
            (postTransferRecipientBalance - preTransferRecipientBalance) == preTransferContractBalance
        );
    }

    /**
     * @notice Tests that a non-admin cannot withdraw ERC20 tokens
     */
    function test_RevertWhen_NonAdminAttemptsWithdraw() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        investAsUser(sampleUser, params);

        uint256 ledgerBalance = PaymentTokenInstance.balanceOf(address(LedgerInstance));

        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        vm.startPrank(sampleUser, sampleUser);
        LedgerInstance.withdraw(params.paymentTokenAddress, deployer, ledgerBalance);

        vm.stopPrank();
    }

    /**
     * @notice Tests emission of VCInvestment event upon user investment
     */
    function testEmitVCInvestmentUser() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );

        vm.startPrank(sampleUser, sampleUser);

        //this only works because in VVVVCTestBase, the exchange rate numerator and denominator are both 1e6
        uint256 tokenFee = ((params.amountToInvest * params.feeNumerator) /
            LedgerInstance.FEE_DENOMINATOR());
        uint8 paymentTokenDecimals = IERC20WithDecimals(params.paymentTokenAddress).decimals();
        uint256 paymentTokenToInternalUnitsConversion = 10 **
            (LedgerInstance.decimals() - paymentTokenDecimals);

        PaymentTokenInstance.approve(address(LedgerInstance), params.amountToInvest + tokenFee);
        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCInvestment(
            params.investmentRound,
            params.paymentTokenAddress,
            params.kycAddress,
            params.exchangeRateNumerator,
            LedgerInstance.exchangeRateDenominator(),
            params.feeNumerator,
            params.amountToInvest * paymentTokenToInternalUnitsConversion,
            paymentTokenDecimals,
            LedgerInstance.decimals()
        );
        LedgerInstance.invest(params);
        vm.stopPrank();
    }

    /**
     * @notice Tests emission of VCInvestment event upon admin investment
     * @dev address(0) and 0 are used as placeholders because there is no payment token transferred, only ledger stablecoin-equivalent entries are updated
     */
    function testEmitVCInvestmentAdmin() public {
        vm.startPrank(ledgerManager, ledgerManager);

        uint256 numRecords = users.length;
        address[] memory kycAddresses = new address[](numRecords);
        uint256[] memory investmentRounds = new uint256[](numRecords);
        uint256[] memory amountsToInvest = new uint256[](numRecords);

        for (uint256 i = 0; i < numRecords; i++) {
            kycAddresses[i] = users[i];
            investmentRounds[i] = sampleInvestmentRoundIds[0];
            amountsToInvest[i] = 1e8 + i;

            vm.expectEmit(address(LedgerInstance));
            emit VVVVCInvestmentLedger.VCInvestment(
                investmentRounds[i],
                address(0),
                kycAddresses[i],
                0,
                0,
                0,
                amountsToInvest[i],
                LedgerInstance.decimals(),
                LedgerInstance.decimals()
            );
        }
        LedgerInstance.addInvestmentRecords(kycAddresses, investmentRounds, amountsToInvest);
        vm.stopPrank();
    }

    /**
     * @notice Tests addition of investment records by admin
     */
    function testAdminAddMultipleInvestmentRecords() public {
        uint256 numRecords = users.length;
        address[] memory kycAddresses = new address[](numRecords);
        uint256[] memory investmentRounds = new uint256[](numRecords);
        uint256[] memory amountsToInvest = new uint256[](numRecords);

        uint256[] memory userInvestedAfter = new uint256[](numRecords);
        uint256 totalInvestedAfter;
        uint256 expectedTotalInvested;

        for (uint256 i = 0; i < numRecords; i++) {
            kycAddresses[i] = users[i];
            investmentRounds[i] = sampleInvestmentRoundIds[0];
            amountsToInvest[i] = 1e8 + i;
            expectedTotalInvested += amountsToInvest[i];
        }

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.addInvestmentRecords(kycAddresses, investmentRounds, amountsToInvest);
        vm.stopPrank();

        for (uint256 i = 0; i < numRecords; i++) {
            userInvestedAfter[i] = LedgerInstance.kycAddressInvestedPerRound(
                kycAddresses[i],
                investmentRounds[i]
            );
            assertTrue(userInvestedAfter[i] == amountsToInvest[i]);
        }

        totalInvestedAfter = LedgerInstance.totalInvestedPerRound(investmentRounds[0]);
        assertTrue(totalInvestedAfter == expectedTotalInvested);
    }

    /**
     * @notice Tests that attempting to add investment records using arrays of different lengths reverts
     with the ArrayLengthMismatch error
     */
    function testAdminAddMultipleInvestmentRecordsArrayLengthMismatchPath1() public {
        uint256 numRecords = users.length;
        address[] memory kycAddresses = new address[](numRecords + 1);
        uint256[] memory investmentRounds = new uint256[](numRecords);
        uint256[] memory amountsToInvest = new uint256[](numRecords);

        uint256[] memory userInvestedAfter = new uint256[](numRecords);
        uint256 totalInvestedAfter;
        uint256 expectedTotalInvested;

        for (uint256 i = 0; i < numRecords; i++) {
            kycAddresses[i] = users[i];
            investmentRounds[i] = sampleInvestmentRoundIds[0];
            amountsToInvest[i] = 1e8 + i;
            expectedTotalInvested += amountsToInvest[i];
        }
        kycAddresses[numRecords] = address(0);

        vm.startPrank(ledgerManager, ledgerManager);
        vm.expectRevert(VVVVCInvestmentLedger.ArrayLengthMismatch.selector);
        LedgerInstance.addInvestmentRecords(kycAddresses, investmentRounds, amountsToInvest);
        vm.stopPrank();
    }

    function testAdminAddMultipleInvestmentRecordsArrayLengthMismatchPath2() public {
        uint256 numRecords = users.length;
        address[] memory kycAddresses = new address[](numRecords);
        uint256[] memory investmentRounds = new uint256[](numRecords);
        uint256[] memory amountsToInvest = new uint256[](numRecords + 1);

        uint256[] memory userInvestedAfter = new uint256[](numRecords);
        uint256 totalInvestedAfter;
        uint256 expectedTotalInvested;

        for (uint256 i = 0; i < numRecords; i++) {
            kycAddresses[i] = users[i];
            investmentRounds[i] = sampleInvestmentRoundIds[0];
            amountsToInvest[i] = 1e8 + i;
            expectedTotalInvested += amountsToInvest[i];
        }
        amountsToInvest[numRecords] = 1;

        vm.startPrank(ledgerManager, ledgerManager);
        vm.expectRevert(VVVVCInvestmentLedger.ArrayLengthMismatch.selector);
        LedgerInstance.addInvestmentRecords(kycAddresses, investmentRounds, amountsToInvest);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a non-admin cannot add an investment record
     */
    function testUserCantAddInvestmentRecord() public {
        address[] memory kycAddresses = new address[](1);
        uint256[] memory investmentRounds = new uint256[](1);
        uint256[] memory amountsToInvest = new uint256[](1);

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        LedgerInstance.addInvestmentRecords(kycAddresses, investmentRounds, amountsToInvest);
        vm.stopPrank();
    }

    /**
        @notice tests that a user cannot invest when investment is paused
     */
    function testInvestAttemptWhilePaused() public {
        //invest when not paused
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            feeNumerator,
            sampleKycAddress,
            sampleUser,
            activeRoundStartTimestamp,
            activeRoundEndTimestamp
        );
        investAsUser(sampleUser, params);

        //attempt to invest when paused
        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.setInvestmentIsPaused(true);

        vm.startPrank(sampleUser, sampleUser);
        PaymentTokenInstance.approve(address(LedgerInstance), params.amountToInvest);
        vm.expectRevert(VVVVCInvestmentLedger.InvestmentPaused.selector);
        LedgerInstance.invest(params);
    }

    /// @notice Tests that an admin can pause and unpause investments
    function testAdminPauseInvestments() public {
        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.setInvestmentIsPaused(true);
        assertTrue(LedgerInstance.investmentIsPaused());
    }

    /// @notice Tests that a non-admin cannot pause investments
    function testNonAdminPauseInvestments() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        LedgerInstance.setInvestmentIsPaused(true);
    }

    /// @notice Tests that an admin can update decimals
    function testAdminSetDecimals() public {
        vm.startPrank(ledgerManager, ledgerManager);
        uint8 newDecimals = 6;
        LedgerInstance.setDecimals(newDecimals);
        assertEq(LedgerInstance.decimals(), newDecimals);
    }

    /// @notice Tests that a non-admin cannot update decimals
    function testNonAdminSetDecimals() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        LedgerInstance.setDecimals(6);
    }

    /// @notice Tests that the domain separator matches reference domain separator
    function testDomainSeparatorMatch() public {
        assertTrue(
            LedgerInstance.computeDomainSeparator() ==
                calculateReferenceDomainSeparator(address(LedgerInstance))
        );
    }

    /// @notice Tests that the domain separator is updated when chain ID changes
    function testDomainSeparatorChainIdChange() public {
        bytes32 refDomainSeparator = calculateReferenceDomainSeparator(address(LedgerInstance));
        vm.chainId(123456789);
        assertFalse(LedgerInstance.computeDomainSeparator() == refDomainSeparator);
    }
}
