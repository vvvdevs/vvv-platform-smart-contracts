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
    }

    function testDeployment() public {
        assertTrue(address(AlternateTokenDistributorInstance) != address(0));
    }

    //validates the claim signature for claiming tokens
    function testValidateSignature() public {
        VVVVCAlternateTokenDistributor.ClaimParams
            memory params = prepareAlternateDistributorClaimParams();

        //verify the claim signature for the user
        assertTrue(AlternateTokenDistributorInstance.isSignatureValid(params));
    }

    //test that signature is marked invalid if some parameter is altered
    function testInvalidSignature() public {
        VVVVCAlternateTokenDistributor.ClaimParams
            memory params = prepareAlternateDistributorClaimParams();
        params.deadline += 1;

        //ensure invalid signature
        assertFalse(AlternateTokenDistributorInstance.isSignatureValid(params));
    }

    //tests flow of validating a merkle proof involved in claiming tokens
    function testValidateMerkleProofViaDistributor() public {
        VVVVCAlternateTokenDistributor.ClaimParams
            memory params = prepareAlternateDistributorClaimParams();

        //verify merkle proofs for the user for which the proofs are to be generated via the distributor contract
        assertTrue(AlternateTokenDistributorInstance.areMerkleProofsValid(params));
    }

    //tests that altered merkle proof will not pass as valid
    function testInvalidMerkleProof() public {
        VVVVCAlternateTokenDistributor.ClaimParams
            memory params = prepareAlternateDistributorClaimParams();
        params.investmentLeaves[0] = keccak256(abi.encodePacked(params.investmentLeaves[0], uint256(1)));

        //ensure invalid merkle proof
        assertFalse(AlternateTokenDistributorInstance.areMerkleProofsValid(params));
    }

    // function testClaimWithKycAddress() public {}
    // function testClaimWithAlias() public {}
    // function testClaimMultipleRound() public {}
    // function testClaimFullAllocation() public {}

    //function to prepare token claim params and avoid duplicating code. for a set of investment rounds: creates trees, sets roots on read-only ledger, creates merkle proofs for the given user indices (position in that investment round's array of investor kyc addresses), creates valid claim signature for that user, and returns a ClaimParams object containing all info to validate a user's prior investment(s) and currently permitted claim(s)
    function prepareAlternateDistributorClaimParams()
        public
        returns (VVVVCAlternateTokenDistributor.ClaimParams memory)
    {
        uint256[] memory investedAmountsArray = new uint256[](users.length);
        uint256[] memory placeholderArray = new uint256[](10);
        AlternateDistributorInvestmentDetails memory details = AlternateDistributorInvestmentDetails({
            investedAmounts: investedAmountsArray,
            userIndices: placeholderArray,
            investmentRoundIds: placeholderArray,
            totalInvested: 0,
            investmentRounds: placeholderArray.length,
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
            details.investmentRoundIds[i] = i + 1;
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

        return params;
    }
}
