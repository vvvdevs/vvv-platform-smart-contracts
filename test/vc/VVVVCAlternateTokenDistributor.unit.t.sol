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
        ledgerDomainSeparator = ReadOnlyLedgerInstance.DOMAIN_SEPARATOR();
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
    }

    function testDeployment() public {
        assertTrue(address(AlternateTokenDistributorInstance) != address(0));
    }

    // function testValidateSignature() public {}
    // function testInvalidSignature() public {}

    // tests flow of validating a merkle proof. creates trees, sets roots on read-only ledger, creates merkle proofs for the given user indices (position in that investment round's array of investor kyc addresses), creates valid signature for that user, verifies merkle proofs via VVVVCAlternateTokenDistributor
    //just container to avoid stack-too-deep
    struct InvestmentDetails {
        uint256[] investedAmounts;
        uint256[] userIndices;
        uint256[] investmentRoundIds;
        uint256 totalInvested;
        uint256 investmentRounds;
        uint256 deadline;
        uint256 userIndex;
        address selectedUser;
        //TODO: need to be better defined?
        uint256 tokenAmountToClaim;
    }
    function testValidateMerkleProof() public {
        uint256[] memory placeholderArray;
        InvestmentDetails memory details = InvestmentDetails({
            investedAmounts: placeholderArray,
            userIndices: placeholderArray,
            investmentRoundIds: placeholderArray,
            totalInvested: 0,
            investmentRounds: 10,
            deadline: block.timestamp + 1000,
            userIndex: 1,
            selectedUser: users[1],
            tokenAmountToClaim: 1e18
        });

        //give each user in users a sample invested amount, applies to all rounds
        for (uint256 i = 0; i < users.length; ++i) {
            details.investedAmounts[i] = i * 1e18;
            details.totalInvested += details.investedAmounts[i];
        }

        //the user whose investments are being proven occupies an index for each round. user is assumed to occupy same index for all rounds, so that same address of users[i] is obtained for all rounds
        for (uint256 i = 0; i < details.investmentRounds; ++i) {
            details.userIndices[i] = details.userIndex;
            details.investmentRoundIds[i] = i;
        }

        //output root, leaf, and proof for each investment round
        (
            bytes32[] memory roots,
            bytes32[] memory leaves,
            bytes32[][] memory proofs
        ) = getMerkleRootLeafProofArrays(users, details.investedAmounts, details.userIndices);

        //set merkle roots on read-only ledger for all rounds
        vm.startPrank(deployer, deployer);
        for (uint256 i = 0; i < details.investmentRounds; i++) {
            //Generate signature for the round state
            bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
                readOnlyLedgerDomainSeparator,
                setInvestmentRoundStateTypehash,
                details.investmentRoundIds[i],
                roots[i],
                details.totalInvested,
                details.deadline
            );

            ReadOnlyLedgerInstance.setInvestmentRoundState(
                details.investmentRoundIds[i],
                roots[i],
                details.totalInvested,
                testSigner,
                setStateSignature,
                details.deadline
            );
        }
        vm.stopPrank();

        //create ClaimParams for VVVVCAlternateTokenDistributor.areMerkleProofsValid()
        VVVVCAlternateTokenDistributor.ClaimParams
            memory params = generateAlternateClaimParamsWithSignature(
                details.selectedUser,
                details.selectedUser,
                projectTokenProxyWallets,
                details.investmentRoundIds,
                details.tokenAmountToClaim,
                details.investedAmounts,
                leaves,
                proofs
            );

        //finally, verify merkle proofs for the user for which the proofs are to be generated
        assertTrue(AlternateTokenDistributorInstance.areMerkleProofsValid(params));
    }

    // function testInvalidMerkleProof() public {}

    // function testClaimWithKycAddress() public {}
    // function testClaimWithAlias() public {}
    // function testClaimMultipleRound() public {}
    // function testClaimFullAllocation() public {}
}
