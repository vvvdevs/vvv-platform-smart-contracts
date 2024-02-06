//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";
import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";

/**
 * @title VVVVCTokenDistributor Unit Tests
 * @dev use "forge test --match-contract VVVVCTokenDistributorUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCTokenDistributor" to run coverage
 */
contract VVVVCTokenDistributorUnitTests is VVVVCTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, environmentTag);
        ledgerDomainSeparator = LedgerInstance.DOMAIN_SEPARATOR();
        investmentTypehash = LedgerInstance.INVESTMENT_TYPEHASH();

        //supply users with payment token with which to invest
        PaymentTokenInstance = new MockERC20(6); //USDC/T
        PaymentTokenInstance.mint(sampleUser, 1_000_000 * 1e6);
        PaymentTokenInstance.mint(sampleKycAddress, 1_000_000 * 1e6);

        TokenDistributorInstance = new VVVVCTokenDistributor(
            testSigner,
            address(LedgerInstance),
            environmentTag
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
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        VVVVCTokenDistributor.ClaimParams memory params = generateClaimParamsWithSignature(
            sampleKycAddress,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        assertTrue(TokenDistributorInstance.isSignatureValid(params));
    }

    function testInvalidateSignature() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleKycAddress,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        claimParams.projectTokenClaimFromWallets[0] = address(0);
        assertFalse(TokenDistributorInstance.isSignatureValid(claimParams));
    }

    //test that the kyc address can claim tokens on its own behalf
    function testClaimWithKycAddress() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        investAsUser(
            sampleKycAddress,
            generateInvestParamsWithSignature(
                sampleInvestmentRoundIds[0],
                investmentRoundSampleLimit,
                sampleAmountsToInvest[0],
                userPaymentTokenDefaultAllocation,
                sampleKycAddress
            )
        );

        //claim for the same singlen round
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleKycAddress,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );
        claimAsUser(sampleKycAddress, claimParams);
        assertTrue(ProjectTokenInstance.balanceOf(sampleKycAddress) == sampleTokenAmountToClaim);
    }

    //test that an alias of the kyc address can claim tokens on behalf of the kyc address
    function testClaimWithAlias() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        //invest in round 1 (sampleInvestmentRoundIds[0])
        investAsUser(
            sampleKycAddress,
            generateInvestParamsWithSignature(
                sampleInvestmentRoundIds[0],
                investmentRoundSampleLimit,
                sampleAmountsToInvest[0],
                userPaymentTokenDefaultAllocation,
                sampleKycAddress
            )
        );

        //claim for the same round
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        claimAsUser(sampleUser, claimParams);

        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == sampleTokenAmountToClaim);
    }

    // test claiming in multiple rounds with the same transaction
    function testClaimMultipleRounds() public {
        //invest in rounds 1, 2, and 3 (sampleInvestmentRoundIds)
        batchInvestAsUser(sampleUser, sampleInvestmentRoundIds, sampleAmountsToInvest);

        //claim for the same rounds
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            projectTokenProxyWallets,
            sampleInvestmentRoundIds,
            sampleTokenAmountToClaim
        );

        claimAsUser(sampleUser, claimParams);
        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == sampleTokenAmountToClaim);
    }

    // test claiming the exact full allocation in a single round
    function testClaimFullAllocation() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        //invest in round 1 (sampleInvestmentRoundIds[0])
        investAsUser(
            sampleUser,
            generateInvestParamsWithSignature(
                sampleInvestmentRoundIds[0],
                investmentRoundSampleLimit,
                sampleAmountsToInvest[0],
                userPaymentTokenDefaultAllocation,
                sampleKycAddress
            )
        );

        thisClaimAmount = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
            sampleKycAddress,
            address(ProjectTokenInstance),
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids
        );

        //claim for the same round
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        claimAsUser(sampleUser, claimParams);
        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == thisClaimAmount);
    }

    // tests any claim that includes a parameter value that invalidates the signature
    function testClaimWithInvalidSignature() public {
        //invest in rounds 1, 2, and 3 (sampleInvestmentRoundIds)
        batchInvestAsUser(sampleUser, sampleInvestmentRoundIds, sampleAmountsToInvest);

        //claim for the same rounds
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            projectTokenProxyWallets,
            sampleInvestmentRoundIds,
            sampleTokenAmountToClaim
        );

        //alter investment round ids to invalidate signature
        claimParams.investmentRoundIds[0] = 2;
        vm.expectRevert(VVVVCTokenDistributor.InvalidSignature.selector);
        claimAsUser(sampleUser, claimParams);
    }

    // tests that user cannot claim more than the allocation for a round based on their investment
    function testClaimMoreThanAllocation() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);
        uint256 thisClaimAmount = sampleTokenAmountToClaim;

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        //invest in round 1 (sampleInvestmentRoundIds[0])
        investAsUser(
            sampleUser,
            generateInvestParamsWithSignature(
                sampleInvestmentRoundIds[0],
                investmentRoundSampleLimit,
                sampleAmountsToInvest[0],
                userPaymentTokenDefaultAllocation,
                sampleKycAddress
            )
        );

        //claim one more unit than claimable amount
        thisClaimAmount =
            TokenDistributorInstance.calculateBaseClaimableProjectTokens(
                sampleKycAddress,
                address(ProjectTokenInstance),
                thisProjectTokenProxyWallets,
                thisInvestmentRoundids
            ) +
            1;

        //claim for the same round
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        vm.expectRevert(VVVVCTokenDistributor.ExceedsAllocation.selector);
        claimAsUser(sampleUser, claimParams);
    }

    //test that user cannot claim again after claiming their full allocation
    function testClaimAfterClaimingFullAllocation() public {
        address[] memory thisProjectTokenProxyWallets = new address[](1);
        uint256[] memory thisInvestmentRoundids = new uint256[](1);

        thisProjectTokenProxyWallets[0] = projectTokenProxyWallets[0];
        thisInvestmentRoundids[0] = sampleInvestmentRoundIds[0];

        //invest in round 1 (sampleInvestmentRoundIds[0])
        investAsUser(
            sampleUser,
            generateInvestParamsWithSignature(
                sampleInvestmentRoundIds[0],
                investmentRoundSampleLimit,
                sampleAmountsToInvest[0],
                userPaymentTokenDefaultAllocation,
                sampleKycAddress
            )
        );

        uint256 thisClaimAmount = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
            sampleKycAddress,
            address(ProjectTokenInstance),
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids
        );

        //claim for the same round
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            sampleUser,
            sampleKycAddress,
            thisProjectTokenProxyWallets,
            thisInvestmentRoundids,
            thisClaimAmount
        );

        claimAsUser(sampleUser, claimParams);
        assertTrue(ProjectTokenInstance.balanceOf(sampleUser) == thisClaimAmount);

        //claim for the same round again
        vm.expectRevert(VVVVCTokenDistributor.ExceedsAllocation.selector);
        claimAsUser(sampleUser, claimParams);
    }
}
