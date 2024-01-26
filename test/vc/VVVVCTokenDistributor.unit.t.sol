//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";
import { VVVVCTokenDistributorBase } from "test/vc/VVVVCTokenDistributorBase.sol";

/**
 * @title VVVVCTokenDistributor Unit Tests
 * @dev use "forge test --match-contract VVVVCTokenDistributorUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCTokenDistributor" to run coverage
 */
contract VVVVCTokenDistributorUnitTests is VVVVCTokenDistributorBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, domainTag);
        ledgerDomainSeparator = LedgerInstance.DOMAIN_SEPARATOR();
        investmentTypehash = LedgerInstance.INVESTMENT_TYPEHASH();

        //supply users with payment token with which to invest
        PaymentTokenInstance = new MockERC20(6); //USDC/T
        PaymentTokenInstance.mint(sampleUser, 1_000_000 * 1e6);
        PaymentTokenInstance.mint(sampleKycAddress, 1_000_000 * 1e6);

        TokenDistributorInstance = new VVVVCTokenDistributor(
            testSigner,
            address(LedgerInstance),
            domainTag
        );
        distributorDomainSeparator = TokenDistributorInstance.DOMAIN_SEPARATOR();
        claimTypehash = TokenDistributorInstance.CLAIM_TYPEHASH();

        ProjectTokenInstance = new MockERC20(18);

        vm.stopPrank();

        //supply the proxy wallets with the project token to be withdrawn from them by investors
        //from each wallet, approve the token distributor to withdraw the project token
        for (uint256 i = 0; i < projectTokenProxyWallets.length; i++) {
            ProjectTokenInstance.mint(projectTokenProxyWallets[i], projectTokenAmountToProxyWallet);
            vm.startPrank(projectTokenProxyWallets[i], projectTokenProxyWallets[i]);
            ProjectTokenInstance.approve(
                address(TokenDistributorInstance),
                projectTokenAmountToProxyWallet
            );
            vm.stopPrank();
        }
    }

    function testDeployment() public {
        assertTrue(address(TokenDistributorInstance) != address(0));
    }

    function testValidateSignature() public {
        VVVVCTokenDistributor.ClaimParams memory params = generateClaimParamsWithSignature(
            sampleKycAddress
        );
        assertTrue(TokenDistributorInstance.isSignatureValid(params));
    }

    function testInvalidateSignature() public {
        VVVVCTokenDistributor.ClaimParams memory params = generateClaimParamsWithSignature(
            sampleKycAddress
        );
        params.projectTokenClaimFromWallets[0] = address(0);
        assertFalse(TokenDistributorInstance.isSignatureValid(params));
    }

    //test that the kyc address can claim tokens on its own behalf
    function testClaimWithKycAddress() public {
        //invest in rounds 1, 2, and 3 (sampleInvestmentRoundIds)
        batchInvestAsUser(sampleKycAddress, sampleInvestmentRoundIds, sampleAmountsToInvest);

        //claim for the same rounds
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleKycAddress
        );
        claimAsUser(sampleKycAddress, claimParams);
        assertTrue(ProjectTokenInstance.balanceOf(sampleKycAddress) == sum(sampleTokenAmountsToClaim));
    }

    //test that an alias of the kyc address can claim tokens on behalf of the kyc address
    function testClaimWithAlias() public {
        //invest in rounds 1, 2, and 3 (sampleInvestmentRoundIds)
        batchInvestAsUser(sampleUser, sampleInvestmentRoundIds, sampleAmountsToInvest);

        //claim for the same rounds
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser
        );
        claimAsUser(sampleUser, claimParams);

        emit log_named_uint("balance of sample user", ProjectTokenInstance.balanceOf(sampleUser));
        emit log_named_uint("sum of token amounts to claim", sum(sampleTokenAmountsToClaim));

        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == sum(sampleTokenAmountsToClaim));
    }

    // function testClaimMultipleRounds() public {}
    // function testClaimFullAllocation() public {}
    // function testClaimPartialAllocation() public {}
    // function testClaimMultipleTokens() public {}

    // function testClaimWithInvalidSignature() public {}
    // function testClaimMoreThanAllocation() public {}
    // function testClaimMoreThanProxyWalletBalance() public {}
    // function testClaimAfterClaimingFullAllocation() public {}
}
