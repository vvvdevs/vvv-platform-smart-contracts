//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";

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

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, environmentTag);
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

        vm.startPrank(deployer, deployer);
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
}