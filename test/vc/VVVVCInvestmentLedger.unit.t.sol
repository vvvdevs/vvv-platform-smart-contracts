//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
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

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, environmentTag, address(AuthRegistry));

        //grant ledgerManager the ledgerManagerRole
        AuthRegistry.grantRole(ledgerManagerRole, ledgerManager);

        //add permissions to ledgerManagerRole for withdraw and addInvestmentRecord on the LedgerInstance
        bytes4 withdrawSelector = LedgerInstance.withdraw.selector;
        bytes4 addInvestmentRecordSelector = LedgerInstance.addInvestmentRecord.selector;
        bytes4 setExchangeRateDenominatorSelector = LedgerInstance.setExchangeRateDenominator.selector;
        bytes4 refundSelector = LedgerInstance.refundUserInvestment.selector;
        bytes4 setInvestmentPausedSelector = LedgerInstance.setInvestmentIsPaused.selector;
        AuthRegistry.setPermission(address(LedgerInstance), withdrawSelector, ledgerManagerRole);
        AuthRegistry.setPermission(
            address(LedgerInstance),
            addInvestmentRecordSelector,
            ledgerManagerRole
        );
        AuthRegistry.setPermission(
            address(LedgerInstance),
            setExchangeRateDenominatorSelector,
            ledgerManagerRole
        );
        AuthRegistry.setPermission(address(LedgerInstance), refundSelector, ledgerManagerRole);
        AuthRegistry.setPermission(
            address(LedgerInstance),
            setInvestmentPausedSelector,
            ledgerManagerRole
        );

        ledgerDomainSeparator = LedgerInstance.DOMAIN_SEPARATOR();
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
            sampleKycAddress
        );
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
            sampleKycAddress
        );

        //round start timestamp is off by one second
        params.investmentRoundStartTimestamp += 1;

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
            sampleKycAddress
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
            sampleKycAddress
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
            sampleKycAddress
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
            sampleKycAddress
        );

        uint256 numberOfInvestments = 10;

        for (uint256 i = 0; i < numberOfInvestments; i++) {
            investAsUser(sampleUser, params);
        }

        assertTrue(
            PaymentTokenInstance.balanceOf(address(LedgerInstance)) ==
                params.amountToInvest * numberOfInvestments
        );
    }

    /**
     * @notice Tests that a user cannot invest multiple times in a single round to exceed their limits
     * @dev in generateInvestParamsWithSignature, the user is allocated 1000 tokens, and the round limit is 10000 tokens
     * @dev so 10 investments work, but 11 won't
     */
    function testTooManyInvestmentsInSingleRound() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            sampleKycAddress
        );

        uint256 numberOfInvestments = 10;

        for (uint256 i = 0; i < numberOfInvestments; i++) {
            investAsUser(sampleUser, params);
        }

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCInvestmentLedger.ExceedsAllocation.selector);
        LedgerInstance.invest(params);
        vm.stopPrank();

        assertTrue(
            PaymentTokenInstance.balanceOf(address(LedgerInstance)) ==
                params.amountToInvest * numberOfInvestments
        );
    }

    /**
     * @notice Tests investment function call by user with invalid signature
     * @dev defines an InvestParams struct, creates a signature for it, changes a param and should fail to invest
     */
    function testFailInvestWithInvalidSignature() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            sampleKycAddress
        );

        params.investmentRoundStartTimestamp += 1;

        investAsUser(sampleUser, params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == 0);
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) == userPaymentTokenDefaultAllocation);
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
            sampleKycAddress
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

    /* @notice Tests that a non-admin cannot withdraw ERC20 tokens
     * @notice used the "testFail" approach this time due to issues expecting a revert on the first external call (balance check) rather than the withdraw function itself. This is a bit less explicit, but still confirms the non-admin call to withdraw reverts.
     */
    function testFailNonAdminCannotWithdraw() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation,
            exchangeRateNumerator,
            sampleKycAddress
        );

        investAsUser(sampleUser, params);

        vm.startPrank(sampleUser, sampleUser);
        LedgerInstance.withdraw(
            params.paymentTokenAddress,
            deployer,
            PaymentTokenInstance.balanceOf(address(LedgerInstance))
        );

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
            sampleKycAddress
        );

        vm.startPrank(sampleUser, sampleUser);

        PaymentTokenInstance.approve(address(LedgerInstance), params.amountToInvest);
        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCInvestment(
            params.investmentRound,
            params.paymentTokenAddress,
            params.kycAddress,
            params.exchangeRateNumerator,
            LedgerInstance.exchangeRateDenominator(),
            params.amountToInvest
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

        uint256 amountToInvest = sampleAmountsToInvest[0];
        uint256 investmentRoundId = sampleInvestmentRoundIds[0];

        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCInvestment(
            investmentRoundId,
            address(0),
            sampleKycAddress,
            0,
            0,
            amountToInvest
        );
        LedgerInstance.addInvestmentRecord(sampleKycAddress, investmentRoundId, amountToInvest);
        vm.stopPrank();
    }

    /**
     * @notice Tests addition of investment record by admin
     */
    function testAdminAddInvestmentRecord() public {
        address kycAddress = sampleUser;
        uint256 investmentRound = sampleInvestmentRoundIds[0];
        uint256 investmentAmount = 1000;

        uint256 userInvested = LedgerInstance.kycAddressInvestedPerRound(kycAddress, investmentRound);
        uint256 totalInvested = LedgerInstance.totalInvestedPerRound(investmentRound);

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.addInvestmentRecord(kycAddress, investmentRound, investmentAmount);
        vm.stopPrank();

        assertTrue(
            LedgerInstance.kycAddressInvestedPerRound(kycAddress, investmentRound) ==
                userInvested + investmentAmount
        );

        assertTrue(
            LedgerInstance.totalInvestedPerRound(investmentRound) == totalInvested + investmentAmount
        );
    }

    /**
     * @notice Tests that a non-admin cannot add an investment record
     */
    function testUserCantAddInvestmentRecord() public {
        address kycAddress = sampleUser;
        uint256 investmentRound = sampleInvestmentRoundIds[0];
        uint256 investmentAmount = 1000;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        LedgerInstance.addInvestmentRecord(kycAddress, investmentRound, investmentAmount);
        vm.stopPrank();
    }

    /**
        @notice test that admin can set the stablecoin exchange rate denominator
     */
    function testSetExchangeRateDenominator() public {
        uint256 newExchangeRateDenominator = 1e18;

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.setExchangeRateDenominator(newExchangeRateDenominator);
        vm.stopPrank();

        assertTrue(LedgerInstance.exchangeRateDenominator() == newExchangeRateDenominator);
    }

    /**
        @notice tests that a non-admin cannot set the stablecoin exchange rate denominator
     */
    function testNonAdminSetExchangeRateDenominator() public {
        uint256 newExchangeRateDenominator = 1e18;

        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        LedgerInstance.setExchangeRateDenominator(newExchangeRateDenominator);
        vm.stopPrank();
    }

    /**
     * @notice Tests that an admin can refund an investment made by a user
     */
    function testAdminRefund() public {
        //invest as user
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation, //1e6
            exchangeRateNumerator,
            sampleKycAddress
        );

        uint256 preInvestBalance = PaymentTokenInstance.balanceOf(sampleUser);
        investAsUser(sampleUser, params);

        //refund same investment as admin
        vm.startPrank(ledgerManager, ledgerManager);
        uint256 stablecoinEquivalent = params.amountToInvest; //1:1 in this case
        LedgerInstance.refundUserInvestment(
            sampleKycAddress,
            sampleUser,
            params.investmentRound,
            address(PaymentTokenInstance),
            params.amountToInvest,
            stablecoinEquivalent
        );

        //confirm user is refunded, and no record of investment remains on the ledger contract
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) == preInvestBalance);
        assertTrue(
            LedgerInstance.kycAddressInvestedPerRound(sampleKycAddress, params.investmentRound) == 0
        );
        assertTrue(LedgerInstance.totalInvestedPerRound(params.investmentRound) == 0);
    }

    /**
     * @notice Tests that a non-admin cannot refund an investment made by a user
     */
    function testNonAdminCannotRefundInvestment() public {
        //invest as user
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature(
            sampleInvestmentRoundIds[0],
            investmentRoundSampleLimit,
            sampleAmountsToInvest[0],
            userPaymentTokenDefaultAllocation, //1e6
            exchangeRateNumerator,
            sampleKycAddress
        );

        investAsUser(sampleUser, params);

        //refund same investment as admin
        vm.startPrank(sampleUser, sampleUser);
        uint256 stablecoinEquivalent = params.amountToInvest; //1:1 in this case
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        LedgerInstance.refundUserInvestment(
            sampleKycAddress,
            sampleUser,
            params.investmentRound,
            address(PaymentTokenInstance),
            params.amountToInvest,
            stablecoinEquivalent
        );
    }

    /**
     * @notice Tests that the VCRefund event is emitted when a refund is made
     * @dev manually adds record, then "refunds" it, by only erasing the record of investment on the ledger (transfers 0 tokens)
     */
    function testEmitVCRefund() public {
        uint256 investmentRoundId = sampleInvestmentRoundIds[0];
        uint256 amountToInvest = 1000; //stablecoin amount in this case

        vm.startPrank(ledgerManager, ledgerManager);
        LedgerInstance.addInvestmentRecord(sampleKycAddress, investmentRoundId, amountToInvest);
        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCRefund(
            sampleKycAddress,
            sampleUser,
            investmentRoundId,
            address(PaymentTokenInstance),
            0,
            amountToInvest
        );
        //transfers 0 tokens, but erases the investment record
        LedgerInstance.refundUserInvestment(
            sampleKycAddress,
            sampleUser,
            investmentRoundId,
            address(PaymentTokenInstance),
            0,
            amountToInvest
        );
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
            sampleKycAddress
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
}
