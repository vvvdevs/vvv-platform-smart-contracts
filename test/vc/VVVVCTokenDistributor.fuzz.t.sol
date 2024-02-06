//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    // NOTE: this uses type(uint256).max as investment round and user allocations,
    // so these are effectively not tested here
    function testFuzz_InvestAndClaimSuccess(
        address _callerAddress,
        address _kycAddress,
        uint256 _seed,
        uint256 _length
    ) public {
        TestParams memory testParams;

        uint256 maxLength = 100;
        uint256 arrayLength = bound(_length, 1, maxLength);

        vm.assume(_callerAddress != address(0));
        vm.assume(_kycAddress != address(0));
        vm.assume(_seed != 0);

        PaymentTokenInstance.mint(_callerAddress, paymentTokenMintAmount);

        testParams.investmentRoundIds = new uint256[](arrayLength);
        testParams.tokenAmountsToInvest = new uint256[](arrayLength);
        testParams.projectTokenClaimFromWallets = new address[](arrayLength);
        testParams.claimAmounts = new uint256[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            testParams.projectTokenClaimFromWallets[i] = address(
                uint160(uint256(keccak256(abi.encodePacked(_callerAddress, i))))
            );

            //mint a ton to the proxy wallets so there's no issue with not enough to claim
            ProjectTokenInstance.mint(testParams.projectTokenClaimFromWallets[i], 10000 * 1e18);

            testParams.investmentRoundIds[i] = bound(_seed, 0, arrayLength);
            testParams.tokenAmountsToInvest[i] = bound(
                _seed,
                0,
                IERC20(address(PaymentTokenInstance)).balanceOf(_callerAddress) / arrayLength
            );
        }

        // ensure proxy wallets have approved the distributor to withdraw tokens
        approveProjectTokenForDistributor(testParams.projectTokenClaimFromWallets, type(uint256).max);

        // Dynamically use fuzzed addresses and amounts for investment
        for (uint256 i = 0; i < arrayLength; i++) {
            investAsUser(
                _callerAddress,
                generateInvestParamsWithSignature(
                    testParams.investmentRoundIds[i],
                    type(uint256).max, //sample very high round limit to avoid this error
                    testParams.tokenAmountsToInvest[i], // invested amounts
                    type(uint256).max, //sample very high allocation
                    _kycAddress
                )
            );
        }

        uint256 balanceTotalBefore = ProjectTokenInstance.balanceOf(_callerAddress);
        for (uint256 i = 0; i < arrayLength; i++) {
            // Calculate claimable tokens for each wallet
            testParams.claimAmounts[i] = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
                _kycAddress,
                address(ProjectTokenInstance),
                testParams.projectTokenClaimFromWallets[i],
                testParams.investmentRoundIds[i]
            );
            testParams.totalClaimAmount += testParams.claimAmounts[i];
        }

        // Generate claim params for each wallet
        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            _callerAddress,
            _kycAddress,
            testParams.projectTokenClaimFromWallets,
            testParams.investmentRoundIds,
            testParams.claimAmounts
        );

        // Attempt to claim for each wallet
        claimAsUser(_callerAddress, claimParams);

        // Check if the total claimed amount matches expected
        assertTrue(
            ProjectTokenInstance.balanceOf(_callerAddress) ==
                balanceTotalBefore + testParams.totalClaimAmount
        );
    }

    /**
        address(ProjectTokenInstance) is used so this address is not fuzzed
        Other than that, this tests for an expected revert given random inputs
        as a check that the logic that requires a prior investment is solid
     */
    function testFuzz_ClaimRevert(
        address _callerAddress,
        address _kycAddress,
        uint256 _seed,
        uint256 _length
    ) public {
        //constraints + setup for arrays
        uint256 lengthLimit = 100;
        uint256 arrayLength = bound(_length, 1, lengthLimit);

        vm.assume(_callerAddress != address(0));
        vm.assume(_kycAddress != address(0));
        vm.assume(_seed != 0);

        uint256[] memory _investmentRoundIds = new uint256[](arrayLength);
        uint256[] memory _tokenAmountsToClaim = new uint256[](arrayLength);
        address[] memory _projectTokenClaimFromWallets = new address[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            _projectTokenClaimFromWallets[i] = address(
                uint160(uint256(keccak256(abi.encodePacked(_callerAddress, i))))
            );
            _investmentRoundIds[i] = bound(_seed, 0, arrayLength);
            _tokenAmountsToClaim[i] = bound(_seed, 0, type(uint256).max);
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
