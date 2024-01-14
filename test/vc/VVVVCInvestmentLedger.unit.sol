//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCInvestmentLedgerTestBase } from "test/vc/VVVVCInvestmentLedgerTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";

/**
 * @title VVVVCInvestmentLedger Unit Tests
 * @dev use "forge test --match-contract VVVVCInvestmentLedgerUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCInvestmentLedger" to run coverage
 */
contract VVVVCInvestmentLedgerUnitTests is VVVVCInvestmentLedgerTestBase {
    /// @notice sets up project and payment tokens, and an instance of the investment ledger
    function setUp() public {
        vm.startPrank(deployer, deployer);

        ProjectTokenInstance = new MockERC20(18);
        PaymentTokenInstance = new MockERC20(6); //usdc has 6 decimals

        LedgerInstance = new VVVVCInvestmentLedger(testSigner);

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
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature();
        assertTrue(LedgerInstance.isSignatureValid(params));
    }

    function investAsUser(address _investor, VVVVCInvestmentLedger.InvestParams memory _params) public {
        vm.startPrank(_investor, _investor);
        PaymentTokenInstance.approve(address(LedgerInstance), _params.amountToInvest);
        LedgerInstance.invest(_params);
        vm.stopPrank();
    }

    /**
     * @notice Tests investment function call by user
     * @dev defines an InvestParams struct, creates a signature for it, validates it, and invests some PaymentToken
     */
    function testInvest() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature();
        uint256 preInvestBalance = PaymentTokenInstance.balanceOf(sampleUser);

        investAsUser(sampleUser, params);

        //confirm that contract and user balances reflect the invested params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == params.amountToInvest);
        assertTrue(PaymentTokenInstance.balanceOf(sampleUser) + params.amountToInvest == preInvestBalance);
    }

    function testTransferERC20PostInvestment() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature();
        investAsUser(sampleUser, params);

        uint256 preTransferRecipientBalance = PaymentTokenInstance.balanceOf(deployer);
        uint256 preTransferContractBalance = PaymentTokenInstance.balanceOf(address(LedgerInstance));

        vm.startPrank(deployer, deployer);
        LedgerInstance.transferERC20(params.paymentTokenAddress, deployer, PaymentTokenInstance.balanceOf(address(LedgerInstance)));
        vm.stopPrank();

        uint256 postTransferRecipientBalance = PaymentTokenInstance.balanceOf(deployer);

        assertTrue((postTransferRecipientBalance - preTransferRecipientBalance) == preTransferContractBalance);
    }

    function testTransferETH() public {
        vm.startPrank(sampleUser);
        (bool os, ) = address(LedgerInstance).call{value: 1 ether}("");
        assertTrue(os);
        vm.stopPrank();

        uint256 postTransferSenderBalance = sampleUser.balance;

        uint256 preTransferRecipientBalance = deployer.balance;
        uint256 preTransferContractBalance = address(LedgerInstance).balance;

        vm.startPrank(deployer);
        LedgerInstance.transferETH(payable(deployer), preTransferContractBalance);
        vm.stopPrank();

        uint256 postTransferRecipientBalance = deployer.balance;

        emit log_named_uint("post-sender", postTransferSenderBalance);
        emit log_named_uint("pre-recipient", preTransferRecipientBalance);
        emit log_named_uint("pre-contract", preTransferContractBalance);
        emit log_named_uint("post-recipient", postTransferRecipientBalance);

        assertTrue((postTransferRecipientBalance - preTransferRecipientBalance) == preTransferContractBalance);

    }

}