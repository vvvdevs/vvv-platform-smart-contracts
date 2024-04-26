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

    // //corresponds to testFuzz_InvestAndClaimSuccess in VVVVCTokenDistributor.fuzz.t.sol
    // function testFuzz_ClaimSuccess(
    //     address _callerAddress,
    //     address _kycAddress,
    //     uint256 _seed,
    //     uint256 _length
    // ) public {

    // }

    // /**
    //     address(ProjectTokenInstance) is used so this address is not fuzzed
    //     Other than that, this tests for an expected revert given random inputs
    //     as a check that the logic that requires a prior investment is solid
    //  */
    // function testFuzz_ClaimRevert(
    //     address _callerAddress,
    //     address _kycAddress,
    //     uint256 _seed,
    //     uint256 _length
    // ) public {}

    // // Tests that the distributor always returns zero when there is not an investment made + project token balance in "claim from" or proxy wallet
    // function testFuzz_CalculateBaseClaimableProjectTokensAlwaysZero(
    //     address _caller,
    //     uint256 _seed
    // ) public {}

    // // Tests that distributor returns correct amount in proportion to invested amount in all cases
    // function testFuzz_CalculateBaseClaimableProjectTokens(address _caller, uint256 _seed) public {}
}
