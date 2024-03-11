//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";

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
        AuthRegistry.setPermission(address(LedgerInstance), withdrawSelector, ledgerManagerRole);
        AuthRegistry.setPermission(
            address(LedgerInstance),
            addInvestmentRecordSelector,
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
            sampleKycAddress
        );

        uint256 preInvestBalance = PaymentTokenInstance.balanceOf(sampleUser);

        investAsUser(sampleUser, params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == params.amountToInvest);
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) + params.amountToInvest == preInvestBalance);
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
            sampleKycAddress
        );

        vm.startPrank(sampleUser, sampleUser);

        PaymentTokenInstance.approve(address(LedgerInstance), params.amountToInvest);
        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCInvestment(
            params.investmentRound,
            params.kycAddress,
            params.amountToInvest
        );
        LedgerInstance.invest(params);
        vm.stopPrank();
    }

    /**
     * @notice Tests emission of VCInvestment event upon admin investment
     */
    function testEmitVCInvestmentAdmin() public {
        vm.startPrank(ledgerManager, ledgerManager);

        uint256 amountToInvest = sampleAmountsToInvest[0];
        uint256 investmentRoundId = sampleInvestmentRoundIds[0];

        vm.expectEmit(address(LedgerInstance));
        emit VVVVCInvestmentLedger.VCInvestment(investmentRoundId, sampleKycAddress, amountToInvest);
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
}
