//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CompleteMerkle } from "lib/murky/src/CompleteMerkle.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCReadOnlyInvestmentLedger } from "contracts/vc/VVVVCReadOnlyInvestmentLedger.sol";
import { VVVVCAlternateTokenDistributor } from "contracts/vc/VVVVCAlternateTokenDistributor.sol";
import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";

/**
 * @title VVVVCAlternateTokenDistributor Unit Tests
 * @dev use "forge test --match-contract VVVVCAlternateTokenDistributor" to run tests
 * @dev use "forge coverage --match-contract VVVVCAlternateTokenDistributor" to run coverage
 */
contract VVVVCAlternateTokenDistributorUnitTests is VVVVCTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        //instance of contract for creating merkle trees/proofs
        m = new CompleteMerkle();

        //placeholder address(0) for VVVAuthorizationRegistry
        ReadOnlyLedgerInstance = new VVVVCReadOnlyInvestmentLedger(testSignerArray, environmentTag);
        readOnlyLedgerDomainSeparator = ReadOnlyLedgerInstance.DOMAIN_SEPARATOR();
        setInvestmentRoundStateTypehash = ReadOnlyLedgerInstance.STATE_TYPEHASH();

        AlternateTokenDistributorInstance = new VVVVCAlternateTokenDistributor(
            testSigner,
            address(ReadOnlyLedgerInstance),
            environmentTag
        );
        alternateTokenDistributorDomainSeparator = AlternateTokenDistributorInstance.DOMAIN_SEPARATOR();
        alternateClaimTypehash = AlternateTokenDistributorInstance.CLAIM_TYPEHASH();

        ProjectTokenInstance = new MockERC20(18);

        vm.stopPrank();

        //supply the proxy wallets with the project token to be withdrawn from them by investors
        //from each wallet, approve the token distributor to withdraw the project token
        for (uint256 i = 0; i < projectTokenProxyWallets.length; i++) {
            ProjectTokenInstance.mint(projectTokenProxyWallets[i], projectTokenAmountToProxyWallet);
            vm.startPrank(projectTokenProxyWallets[i], projectTokenProxyWallets[i]);
            ProjectTokenInstance.approve(
                address(AlternateTokenDistributorInstance),
                projectTokenAmountToProxyWallet
            );
            vm.stopPrank();
        }

        //generate user list, deal ether (placeholder token)
        generateUserAddressListAndDealEtherAndToken(new MockERC20(18));

        //defines alternate caller address for this test set, within thet users array rather than separately defined as is the case for "sampleUser", etc.
        altDistributorTestKycAddress = users[1];
    }

    function testDeployment() public {
        assertTrue(address(AlternateTokenDistributorInstance) != address(0));
    }

    //validates the claim signature for claiming tokens
    function testValidateSignature() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

        //verify the claim signature for the user
        assertTrue(AlternateTokenDistributorInstance.isSignatureValid(params));
    }

    //test that signature is marked invalid if some parameter is altered
    function testInvalidSignature() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );
        params.deadline += 1;

        //ensure invalid signature
        assertFalse(AlternateTokenDistributorInstance.isSignatureValid(params));
    }

    //tests flow of validating a merkle proof involved in claiming tokens
    function testValidateMerkleProofViaDistributor() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

        //verify merkle proofs for the user for which the proofs are to be generated via the distributor contract
        assertTrue(AlternateTokenDistributorInstance.areMerkleProofsValid(params));
    }

    //tests that altered merkle proof will not pass as valid
    function testInvalidMerkleProof() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );
        params.investmentLeaves[0] = keccak256(abi.encodePacked(params.investmentLeaves[0], uint256(1)));

        //ensure invalid merkle proof
        assertFalse(AlternateTokenDistributorInstance.areMerkleProofsValid(params));
    }

    //test that the kyc address can claim tokens on its own behalf
    function testClaimWithKycAddress() public {
        uint256 totalUserClaimableTokens;

        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

        //find claimable amount of tokens
        for (uint256 i = 0; i < params.projectTokenProxyWallets.length; i++) {
            totalUserClaimableTokens += AlternateTokenDistributorInstance
                .calculateBaseClaimableProjectTokens(
                    params.projectTokenAddress,
                    params.projectTokenProxyWallets[i],
                    params.investmentRoundIds[i],
                    params.investedPerRound[i]
                );
        }

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();

        assertTrue(
            ProjectTokenInstance.balanceOf(altDistributorTestKycAddress) == params.tokenAmountToClaim
        );
    }

    //test that an alias of the kyc address can claim tokens on behalf of the kyc address
    function testClaimWithAlias() public {
        uint256 totalUserClaimableTokens;

        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            sampleUser
        );

        //find claimable amount of tokens
        for (uint256 i = 0; i < params.projectTokenProxyWallets.length; i++) {
            totalUserClaimableTokens += AlternateTokenDistributorInstance
                .calculateBaseClaimableProjectTokens(
                    params.projectTokenAddress,
                    params.projectTokenProxyWallets[i],
                    params.investmentRoundIds[i],
                    params.investedPerRound[i]
                );
        }

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(sampleUser, sampleUser);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();

        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == params.tokenAmountToClaim);
    }

    // function testClaimMultipleRound() public {}
    // function testClaimFullAllocation() public {}
    // function testClaimWithInvalidSignature() public {}
    // function testClaimMoreThanAllocation() public {}
    // function testClaimAfterClaimingFullAllocation() public {}
    // function testCalculateBaseClaimableProjectTokens() public {}
    // function testEmitVCClaim() public {}
}
