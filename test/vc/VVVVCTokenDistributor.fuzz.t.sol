//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";
import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";

/**
 * @title VVVVCTokenDistributor Fuzz Tests
 * @dev use "forge test --match-contract VVVVCTokenDistributorFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCTokenDistributor" to run coverage
 */
contract VVVVCTokenDistributorFuzzTests is VVVVCTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, environmentTag);
        ledgerDomainSeparator = LedgerInstance.DOMAIN_SEPARATOR();
        investmentTypehash = LedgerInstance.INVESTMENT_TYPEHASH();

        //supply users with payment token with which to invest
        PaymentTokenInstance = new MockERC20(6); //USDC/T
        PaymentTokenInstance.mint(sampleUser, 1_000_000 * 1e6);
        PaymentTokenInstance.mint(sampleKycAddress, 1_000_000 * 1e6);

        //supply the proxy wallets with the project token to be withdrawn from them by investors
        ProjectTokenInstance = new MockERC20(18);
        for (uint256 i = 0; i < projectTokenProxyWallets.length; i++) {
            ProjectTokenInstance.mint(projectTokenProxyWallets[i], projectTokenAmountToProxyWallet);
        }

        TokenDistributorInstance = new VVVVCTokenDistributor(
            testSigner,
            address(LedgerInstance),
            environmentTag
        );
        distributorDomainSeparator = TokenDistributorInstance.DOMAIN_SEPARATOR();
        claimTypehash = TokenDistributorInstance.CLAIM_TYPEHASH();

        vm.stopPrank();
    }

    function testFuzz_InvestAndClaimSuccess(
        address _callerAddress,
        address _kycAddress,
        address[] memory _projectTokenClaimFromWallets,
        uint256[] memory _investmentRoundIds,
        uint256[] memory _tokenAmountsToInvest,
        uint256[] memory _tokenAmountsToClaim
    ) public {
        {
            uint256 investmentRountIdsLengthLimit = 100;

            //constraints
            if (
                _callerAddress == address(0) ||
                _projectTokenClaimFromWallets.length == 0 ||
                _investmentRoundIds.length == 0 ||
                _investmentRoundIds.length > investmentRountIdsLengthLimit ||
                _tokenAmountsToClaim.length == 0 ||
                _tokenAmountsToInvest.length == 0 ||
                _tokenAmountsToInvest.length != _tokenAmountsToClaim.length ||
                _tokenAmountsToInvest.length != _investmentRoundIds.length
            ) {
                return;
            }

            // Dynamically use fuzzed addresses and amounts for investment
            for (uint256 i = 0; i < _investmentRoundIds.length; i++) {
                investAsUser(
                    _callerAddress,
                    generateInvestParamsWithSignature(
                        _investmentRoundIds[i],
                        sampleAmountsToInvest[i], // Use fuzzed token amounts
                        _kycAddress // Use fuzzed KYC address
                    )
                );
            }
        }
        {
            uint256 totalClaimAmount = 0;
            uint256 balanceTotalBefore = ProjectTokenInstance.balanceOf(_callerAddress);
            for (uint256 i = 0; i < _projectTokenClaimFromWallets.length; i++) {
                // Calculate claimable tokens for each wallet
                uint256 claimAmount = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
                    _kycAddress,
                    address(ProjectTokenInstance),
                    _projectTokenClaimFromWallets[i],
                    _investmentRoundIds[i % _investmentRoundIds.length] // Ensure index is within bounds
                );
                totalClaimAmount += claimAmount;

                uint256[] memory claimAmounts = new uint256[](1);
                claimAmounts[0] = claimAmount;

                // Generate claim params for each wallet
                VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
                    _callerAddress,
                    _kycAddress,
                    _projectTokenClaimFromWallets,
                    _investmentRoundIds,
                    claimAmounts
                );

                // Attempt to claim for each wallet
                uint256 balanceBefore = ProjectTokenInstance.balanceOf(_callerAddress);
                claimAsUser(_callerAddress, claimParams);
                uint256 balanceAfter = ProjectTokenInstance.balanceOf(_callerAddress);
                assertTrue(balanceAfter == balanceBefore + claimAmount);
            }

            // Check if the total claimed amount matches expected
            assertTrue(
                ProjectTokenInstance.balanceOf(_callerAddress) == balanceTotalBefore + totalClaimAmount
            );
        }
    }

    /**
        address(ProjectTokenInstance) is used so this address is not fuzzed
        Other than that, this tests for an expected revert given random inputs
        as a check that the logic that requires a prior investment is solid
     */
    function testFuzz_ClaimRevert(
        address _callerAddress,
        address _kycAddress,
        address[] memory _projectTokenClaimFromWallets,
        uint256[] memory _investmentRoundIds,
        uint256[] memory _tokenAmountsToClaim
    ) public {
        //constraints
        if (
            _callerAddress == address(0) ||
            _kycAddress == address(0) ||
            _projectTokenClaimFromWallets.length == 0 ||
            _investmentRoundIds.length == 0 ||
            _tokenAmountsToClaim.length == 0 ||
            _tokenAmountsToClaim.length != _investmentRoundIds.length
        ) {
            return;
        }

        // Generate claim params for each wallet
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            _callerAddress,
            _kycAddress,
            _projectTokenClaimFromWallets,
            _investmentRoundIds,
            _tokenAmountsToClaim
        );

        // Attempt to claim for each wallet
        // Expect any revert
        vm.expectRevert();
        claimAsUser(_callerAddress, claimParams);
    }
}
