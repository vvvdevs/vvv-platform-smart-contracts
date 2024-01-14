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

        vm.stopPrank();
    }

    function generateInvestParamsWithSignature() public view returns(VVVVCInvestmentLedger.InvestParams memory params) {
        VVVVCInvestmentLedger.InvestParams memory params = VVVVCInvestmentLedger.InvestParams({
            investmentRound: 1,
            investmentRoundLimit: 100_000 * PaymentTokenInstance.decimals(),
            investmentRoundStartTimestamp: block.timestamp,
            investmentRoundEndTimestamp: block.timestamp + 1 days,
            paymentTokenAddress: address(PaymentTokenInstance),
            kycAddress: sampleUser,
            kycAddressAllocation: userPaymentTokenDefaultAllocation,
            amountToInvest: 1_000 * PaymentTokenInstance.decimals(),
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        bytes32 domainSeparator = 
            keccak256(
                abi.encode(
                    domainTypehash,
                    keccak256(bytes("VVV VC Investment Ledger")),
                    keccak256(bytes("1")),
                    chainId,
                    address(LedgerInstance)
                )
            );

        bytes memory sig = getEIP712SignatureForInvest(
            domainSeparator, 
            investmentTypehash, 
            params
        );

        params.signature = sig;  

        return params;
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

    /**
     * @notice Tests investment function call by user
     * @dev defines an InvestParams struct, creates a signature for it, validates it, and invests some PaymentToken
     */
    function testInvest() public {
        VVVVCInvestmentLedger.InvestParams memory params = generateInvestParamsWithSignature();
        
        vm.startPrank(sampleUser, sampleUser);
        //approve amount to invest
        PaymentTokenInstance.approve(address(LedgerInstance), params.amountToInvest);
        
        //invest
        LedgerInstance.invest(params);
        vm.stopPrank();

        //confirm that contract balance reflects the added amount from params.amountToInvest
        assertTrue(PaymentTokenInstance.balanceOf(address(LedgerInstance)) == params.amountToInvest);
    }

}