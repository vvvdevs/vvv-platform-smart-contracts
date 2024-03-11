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

        //placeholder address(0) for VVVAuthorizationRegistry
        LedgerInstance = new VVVVCInvestmentLedger(testSigner, environmentTag, address(0));
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
        vm.assume(_callerAddress != address(0));
        vm.assume(_kycAddress != address(0));
        vm.assume(_seed != 0);
        vm.assume(_length != 0);

        TestParams memory testParams;
        uint256 maxLength = 100;
        uint256 arrayLength = bound(_length, 1, maxLength);

        PaymentTokenInstance.mint(_callerAddress, paymentTokenMintAmount);

        testParams.investmentRoundIds = new uint256[](arrayLength);
        testParams.tokenAmountsToInvest = new uint256[](arrayLength);
        testParams.projectTokenProxyWallets = new address[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            testParams.projectTokenProxyWallets[i] = address(
                uint160(uint256(keccak256(abi.encodePacked(_callerAddress, i))))
            );

            //mint a ton to the proxy wallets so there's no issue with not enough to claim
            ProjectTokenInstance.mint(testParams.projectTokenProxyWallets[i], 10000 * 1e18);

            testParams.investmentRoundIds[i] = bound(_seed, 0, arrayLength);
            testParams.tokenAmountsToInvest[i] = bound(
                _seed,
                0,
                IERC20(address(PaymentTokenInstance)).balanceOf(_callerAddress) / arrayLength
            );
        }

        // ensure proxy wallets have approved the distributor to withdraw tokens
        approveProjectTokenForDistributor(testParams.projectTokenProxyWallets, type(uint256).max);

        // invest using generated addresses
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

            testParams.claimAmount += TokenDistributorInstance.calculateBaseClaimableProjectTokens(
                _kycAddress,
                address(ProjectTokenInstance),
                testParams.projectTokenProxyWallets[i],
                testParams.investmentRoundIds[i]
            );
        }

        uint256 balanceTotalBefore = ProjectTokenInstance.balanceOf(_callerAddress);

        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            _callerAddress,
            _kycAddress,
            testParams.projectTokenProxyWallets,
            testParams.investmentRoundIds,
            testParams.claimAmount
        );

        // Attempt to claim across all wallets for the calling address
        claimAsUser(_callerAddress, claimParams);

        // Check if the total claimed amount matches expected
        assertTrue(
            ProjectTokenInstance.balanceOf(_callerAddress) == balanceTotalBefore + testParams.claimAmount
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
        address[] memory _projectTokenProxyWallets = new address[](arrayLength);
        uint256 _tokenAmountToClaim = bound(_seed, 0, type(uint256).max);

        for (uint256 i = 0; i < arrayLength; i++) {
            _projectTokenProxyWallets[i] = address(
                uint160(uint256(keccak256(abi.encodePacked(_callerAddress, i))))
            );
            _investmentRoundIds[i] = bound(_seed, 0, arrayLength);
        }

        VVVVCTokenDistributor.ClaimParams memory claimParams = generateClaimParamsWithSignature(
            _callerAddress,
            _kycAddress,
            _projectTokenProxyWallets,
            _investmentRoundIds,
            _tokenAmountToClaim
        );

        // Attempt to claim for each wallet
        // Expect any revert
        vm.expectRevert();
        claimAsUser(_callerAddress, claimParams);
    }

    // Tests that the distributor always returns zero when there is not an investment made + project token balance in "claim from" or proxy wallet
    function testFuzz_CalculateBaseClaimableProjectTokensAlwaysZero(
        address _caller,
        uint256 _seed
    ) public {
        vm.assume(_caller != address(0));
        vm.assume(_seed != 0);
        uint256 investmentRoundId = bound(_seed, 0, type(uint256).max);

        uint256 claimableAmount = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
            _caller,
            address(ProjectTokenInstance),
            _caller,
            investmentRoundId
        );

        assertTrue(claimableAmount == 0);
    }

    // Tests that distributor returns correct amount in proportion to invested amount in all cases
    function testFuzz_CalculateBaseClaimableProjectTokens(address _caller, uint256 _seed) public {
        vm.assume(_caller != address(0));
        // should avoid overflow and still be a reasonable upper bound
        // must be > 0 to make assertion true
        uint256 investedAmount = bound(_seed, 1, type(uint128).max);

        uint256 thisInvestmentRoundId = sampleInvestmentRoundIds[0];
        address thisProjectTokenProxyWallet = projectTokenProxyWallets[0];
        uint256 projectTokenWalletBalance = ProjectTokenInstance.balanceOf(thisProjectTokenProxyWallet);

        PaymentTokenInstance.mint(_caller, investedAmount);

        investAsUser(
            _caller,
            generateInvestParamsWithSignature(
                thisInvestmentRoundId,
                type(uint256).max, //sample very high round limit to avoid this error
                investedAmount, // invested amounts
                type(uint256).max, //sample very high allocation
                _caller
            )
        );

        uint256 claimableAmount = TokenDistributorInstance.calculateBaseClaimableProjectTokens(
            _caller,
            address(ProjectTokenInstance),
            thisProjectTokenProxyWallet,
            thisInvestmentRoundId
        );

        emit log_named_uint(
            "User invested: ",
            LedgerInstance.kycAddressInvestedPerRound(_caller, thisInvestmentRoundId)
        );
        emit log_named_uint("claimableAmount", claimableAmount);
        emit log_named_uint("projectTokenWalletBalance", projectTokenWalletBalance);

        assertTrue(claimableAmount == projectTokenWalletBalance);
    }
}
