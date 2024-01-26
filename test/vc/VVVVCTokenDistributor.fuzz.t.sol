//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";
import { VVVVCTokenDistributorBase } from "test/vc/VVVVCTokenDistributorBase.sol";

/**
 * @title VVVVCTokenDistributor Fuzz Tests
 * @dev use "forge test --match-contract VVVVCTokenDistributorFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCTokenDistributor" to run coverage
 */
contract VVVVCTokenDistributorUnitTests is VVVVCTokenDistributorBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        LedgerInstance = new VVVVCInvestmentLedger(testSigner, domainTag);
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
            domainTag
        );
        distributorDomainSeparator = TokenDistributorInstance.DOMAIN_SEPARATOR();
        claimTypehash = TokenDistributorInstance.CLAIM_TYPEHASH();

        vm.stopPrank();
    }

    // function testFuzz_Claim(
    //     address _callerAddress,
    //     address _kycAddress,
    //     address _projectTokenAddress,
    //     address[] memory _projectTokenClaimFromWallets,
    //     uint256[] memory _investmentRoundIds,
    //     uint256[] memory _tokenAmountsToClaim,
    //     uint256 _deadline,
    //     bytes memory _signature
    // ) public {}
}
