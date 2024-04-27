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
        assertTrue(AlternateTokenDistributorInstance.areMerkleProofsAndInvestedAmountsValid(params));
    }

    //tests that altered merkle proof will not pass as valid
    function testInvalidMerkleProof() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );
        params.investmentLeaves[0] = keccak256(abi.encodePacked(params.investmentLeaves[0], uint256(1)));

        //ensure invalid merkle proof
        assertFalse(AlternateTokenDistributorInstance.areMerkleProofsAndInvestedAmountsValid(params));
    }

    //test that the kyc address can claim tokens on its own behalf
    function testClaimWithKycAddress() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

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
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            sampleUser
        );

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(sampleUser, sampleUser);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();

        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == params.tokenAmountToClaim);
    }

    //tests that the distributor can claim tokens for multiple rounds. already passes based on logic in above tests (claim params are generated for multiple rounds by default in VVVVCTestBase:prepareAlternateDistributorClaimParams), so including just for parity with tests in VVVVCTokenDistributor.unit.t.sol
    function testClaimMultipleRound() public {
        testClaimWithKycAddress();
        testClaimWithAlias();
    }

    // test claiming the exact full allocation in a single round
    function testClaimFullAllocation() public {
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

        params.tokenAmountToClaim = totalUserClaimableTokens;

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();

        assertTrue(
            ProjectTokenInstance.balanceOf(altDistributorTestKycAddress) == params.tokenAmountToClaim &&
                ProjectTokenInstance.balanceOf(altDistributorTestKycAddress) == totalUserClaimableTokens
        );
    }

    // tests any claim that includes a parameter value that invalidates the signature
    function testClaimWithInvalidSignature() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

        //this should invalidate the signature
        params.deadline += 1;

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        vm.expectRevert(VVVVCAlternateTokenDistributor.InvalidSignature.selector);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();
    }

    // tests that user cannot claim more than their total allocation based on their investment
    function testClaimMoreThanAllocation() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );

        //claim more than the user allocation
        params.tokenAmountToClaim = type(uint256).max;

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        vm.expectRevert(VVVVCAlternateTokenDistributor.ExceedsAllocation.selector);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();
    }

    //test that user cannot claim again after claiming their full allocation
    function testClaimAfterClaimingFullAllocation() public {
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

        params.tokenAmountToClaim = totalUserClaimableTokens;

        //altDistributorTestKycAddress is used because prepareAlternateDistributorClaimParams() uses the 'users' array to create the merkle tree, so it's convenient to have the caller be a member of the tree
        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        AlternateTokenDistributorInstance.claim(params);

        //claim an additional one token
        params.tokenAmountToClaim = 1;
        vm.expectRevert(VVVVCAlternateTokenDistributor.ExceedsAllocation.selector);
        AlternateTokenDistributorInstance.claim(params);

        vm.stopPrank();
    }

    // Test that calculateBaseClaimableProjectTokens returns the correct amount
    // adds claimable tokens from one round for all members of `users` array and checks that this sum is equal to the balance of the corresponding proxy wallet holding the project tokens
    function testCalculateBaseClaimableProjectTokens() public {
        uint256 sumOfInvestedAmounts;
        uint256 sumOfClaimAmounts;
        uint256 proxyWalletBalance = ProjectTokenInstance.balanceOf(projectTokenProxyWallets[0]);
        uint256 usersLength = users.length;

        for (uint256 i = 0; i < usersLength; i++) {
            //obtain this user's investment info
            VVVVCAlternateTokenDistributor.ClaimParams
                memory params = prepareAlternateDistributorClaimParams(users[i], i);

            //add this user's investment amount to the sum of all users' investment amounts
            sumOfInvestedAmounts += params.investedPerRound[0];
        }

        for (uint256 i = 0; i < usersLength; i++) {
            //obtain this user's investment info
            VVVVCAlternateTokenDistributor.ClaimParams
                memory params = prepareAlternateDistributorClaimParams(users[i], i);

            //calculate the claimable amount of tokens for this user, add to sum of all users' claimable amounts
            uint256 userClaimableTokens = AlternateTokenDistributorInstance
                .calculateBaseClaimableProjectTokens(
                    params.projectTokenAddress,
                    params.projectTokenProxyWallets[0],
                    params.investmentRoundIds[0],
                    params.investedPerRound[0]
                );

            //additional reference calculation of claimable amount for the same user
            uint256 referenceUserClaimableTokens = (params.investedPerRound[0] * proxyWalletBalance) /
                sumOfInvestedAmounts;

            //assert that the two calculations are equal
            assertEq(userClaimableTokens, referenceUserClaimableTokens);

            sumOfClaimAmounts += userClaimableTokens;
        }

        /**
            assumes that truncation errors are less than 1/1e18 of the proxy wallet balance.
            this is arbitrary based on observing the truncation that happens, and assumed negligible
         */
        assertTrue(sumOfClaimAmounts > proxyWalletBalance - (proxyWalletBalance / 1e18));
        assertTrue(sumOfClaimAmounts <= proxyWalletBalance);
    }

    // Test that VCClaim is correctly emitted when project tokens are claimed
    function testEmitVCClaim() public {
        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            altDistributorTestKycAddress
        );
        uint256 tokenAmountToClaim = 1;
        params.tokenAmountToClaim = tokenAmountToClaim;

        vm.startPrank(altDistributorTestKycAddress, altDistributorTestKycAddress);
        vm.expectEmit(address(AlternateTokenDistributorInstance));
        emit VVVVCAlternateTokenDistributor.VCClaim(
            altDistributorTestKycAddress,
            altDistributorTestKycAddress,
            params.projectTokenAddress,
            params.projectTokenProxyWallets,
            params.tokenAmountToClaim
        );
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();
    }
}
