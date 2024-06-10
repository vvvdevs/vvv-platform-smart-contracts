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
 * @title VVVVCAlternateTokenDistributor Fuzz Tests
 * @dev use "forge test --match-contract VVVVCAlternateTokenDistributor" to run tests
 * @dev use "forge coverage --match-contract VVVVCAlternateTokenDistributor" to run coverage
 */
contract VVVVCAlternateTokenDistributorFuzzTests is VVVVCTestBase {
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

    //corresponds to testFuzz_InvestAndClaimSuccess in VVVVCTokenDistributor.fuzz.t.sol
    function testFuzz_ClaimSuccess(address _callerAddress, address _kycAddress) public {
        vm.assume(_callerAddress != address(0));
        vm.assume(_kycAddress != address(0));

        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            _callerAddress,
            _kycAddress
        );

        uint256 callerBalanceBeforeClaim = ProjectTokenInstance.balanceOf(params.callerAddress);

        vm.startPrank(_callerAddress, _callerAddress);
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();

        uint256 balanceDifference = ProjectTokenInstance.balanceOf(params.callerAddress) -
            callerBalanceBeforeClaim;

        //check that the project token was withdrawn from the proxy wallet to the caller address
        assertEq(params.tokenAmountToClaim, balanceDifference);
    }

    /**
        tests for an expected revert given random inputs
        as a check that the logic that requires a prior investment is solid
     */
    function testFuzz_ClaimRevert(address _callerAddress, address _kycAddress, uint256 _seed) public {
        vm.assume(_callerAddress != address(0));
        vm.assume(_kycAddress != address(0));
        vm.assume(_seed != 0);

        VVVVCAlternateTokenDistributor.ClaimParams memory params = prepareAlternateDistributorClaimParams(
            _callerAddress,
            _kycAddress
        );

        //find claimable amount of tokens
        uint256 totalUserClaimableTokens;
        for (uint256 i = 0; i < params.investmentRoundIds.length; i++) {
            totalUserClaimableTokens += AlternateTokenDistributorInstance
                .calculateBaseClaimableProjectTokens(
                    params.projectTokenAddress,
                    params.projectTokenProxyWallets[i],
                    params.investmentRoundIds[i],
                    params.investedPerRound[i]
                );
        }
        params.tokenAmountToClaim = totalUserClaimableTokens;

        //altering various claim parameters based on _seed, bounding some values to ensure no intersection with existing addresses/values which will not revert
        uint256 paramToAlter = _seed % 7;
        if (paramToAlter == 0) {
            params.userKycAddress = address(uint160(uint256(keccak256(abi.encodePacked(_seed)))));
        } else if (paramToAlter == 1) {
            params.projectTokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(_seed)))));
        } else if (paramToAlter == 2) {
            uint256 boundSeed = bound(_seed, projectTokenProxyWalletKey + 1, type(uint256).max);
            params.projectTokenProxyWallets[0] = address(
                uint160(uint256(keccak256(abi.encodePacked(boundSeed))))
            );
        } else if (paramToAlter == 3) {
            params.investmentRoundIds[0] = bound(
                _seed,
                params.investmentRoundIds.length + 1,
                type(uint32).max
            );
        } else if (paramToAlter == 4) {
            params.tokenAmountToClaim = bound(_seed, params.tokenAmountToClaim + 1, type(uint256).max);
        } else if (paramToAlter == 5) {
            params.deadline = bound(_seed, 0, type(uint32).max);
        } else if (paramToAlter == 6) {
            params.investedPerRound[0] = bound(_seed, type(uint64).max, type(uint256).max);
        }

        vm.startPrank(_callerAddress, _callerAddress);
        vm.expectRevert();
        AlternateTokenDistributorInstance.claim(params);
        vm.stopPrank();
    }

    // Tests that the distributor always returns zero when there is not an investment made + project token balance in "claim from" or proxy wallet
    function testFuzz_CalculateBaseClaimableProjectTokensAlwaysZero(
        address _caller,
        uint256 _seed
    ) public {
        vm.assume(_caller != address(0));
        vm.assume(_seed != 0);
        uint256 investmentRoundId = bound(_seed, 1, type(uint128).max);
        uint256 investedAmount = bound(_seed, 1, type(uint256).max);

        uint256 claimableAmount = AlternateTokenDistributorInstance.calculateBaseClaimableProjectTokens(
            address(ProjectTokenInstance),
            _caller,
            investmentRoundId,
            investedAmount
        );

        assertTrue(claimableAmount == 0);
    }
}
