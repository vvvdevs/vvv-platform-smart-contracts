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

    /// @notice Tests deployment of VVVVCInvestmentLedger
    function testDeployment() public {
        assertTrue(address(LedgerInstance) != address(0));
    }

    /**
     * @notice Tests creation and validation of EIP712 signatures
     * @dev defines an InvestParams struct, creates a signature for it, and validates it with the same struct parameters
     */
    function testValidateSignature() public {
        VVVVCInvestmentLedger.InvestParams memory p = VVVVCInvestmentLedger.InvestParams({
            investmentRound: 1,
            investmentRoundLimit: 100_000 * PaymentTokenInstance.decimals(),
            investmentRoundStartTimestamp: block.timestamp,
            investmentRoundEndTimestamp: block.timestamp + 1 days,
            investmentCustodian: deployer,
            paymentTokenAddress: address(PaymentTokenInstance),
            kycAddress: sampleUser,
            kycAddressAllocation: userPaymentTokenDefaultAllocation,
            amountToInvest: 1_000 * PaymentTokenInstance.decimals(),
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        domainSeparator = 
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
            p
        );

        p.signature = sig;        
        assertTrue(LedgerInstance.isSignatureValid(p));
    }

}