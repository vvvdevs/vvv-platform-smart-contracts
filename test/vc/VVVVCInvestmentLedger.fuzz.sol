//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCInvestmentLedgerTestBase } from "test/vc/VVVVCInvestmentLedgerTestBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";

/**
 * @title VVVVCInvestmentLedger Fuzz Tests
 * @dev use "forge test --match-contract VVVVCInvestmentLedgerFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCInvestmentLedger" to run coverage
 */
contract VVVVCInvestmentLedgerFuzzTests is VVVVCInvestmentLedgerTestBase {
    /// @notice sets up project and payment tokens, and an instance of the investment ledger
    function setUp() public {
        vm.startPrank(deployer, deployer);

        ProjectTokenInstance = new MockERC20(18);
        PaymentTokenInstance = new MockERC20(6); //usdc has 6 decimals

        LedgerInstance = new VVVVCInvestmentLedger(testSigner);

        PaymentTokenInstance.mint(sampleUser, paymentTokenMintAmount); //10k tokens

        generateUserAddressListAndDealEtherAndToken(PaymentTokenInstance);

        vm.stopPrank();
    }

    ///@notice tests investment with varying input params, and checks that the investment ledger state is updated correctly
    function testFuzzInvest(
        uint256 _investmentRound,
        uint256 _investmentRoundLimit,
        uint256 _investmentRoundStartTimestamp,
        uint256 _investmentRoundEndTimestamp,
        address _paymentTokenAddress,
        address _kycAddress,
        uint256 _kycAddressAllocation,
        uint256 _amountToInvest,
        uint256 _deadline
    ) public {
        VVVVCInvestmentLedger.InvestParams memory params = VVVVCInvestmentLedger.InvestParams({
            investmentRound: _investmentRound,
            investmentRoundLimit: _investmentRoundLimit,
            investmentRoundStartTimestamp: _investmentRoundStartTimestamp,
            investmentRoundEndTimestamp: _investmentRoundEndTimestamp,
            paymentTokenAddress: _paymentTokenAddress,
            kycAddress: _kycAddress,
            kycAddressAllocation: _kycAddressAllocation,
            amountToInvest: _amountToInvest,
            deadline: _deadline,
            signature: bytes("placeholder")
        });

        bytes32 domainSeparator = keccak256(
            abi.encode(
                domainTypehash,
                keccak256(bytes("VVV VC Investment Ledger")),
                keccak256(bytes("1")),
                chainId,
                address(LedgerInstance)
            )
        );

        params.signature = getEIP712SignatureForInvest(domainSeparator, investmentTypehash, params);

        //check that the investment ledger state is updated correctly given these conditions,
        //which should yield successful investments
        if (
            _kycAddress != address(0) &&
            _paymentTokenAddress == address(PaymentTokenInstance) &&
            block.timestamp >= _investmentRoundStartTimestamp &&
            block.timestamp <= _investmentRoundEndTimestamp &&
            block.timestamp <= _deadline &&
            _amountToInvest <= _kycAddressAllocation &&
            _amountToInvest <= _investmentRoundLimit
        ) {
            LedgerInstance.invest(params);
            assertEq(LedgerInstance.totalInvestedPerRound(_investmentRound), _amountToInvest);
            assertEq(
                LedgerInstance.kycAddressInvestedPerRound(_kycAddress, _investmentRound),
                _amountToInvest
            );
        } else {
            //check that the investment ledger state is not updated given these conditions,
            //which should yield reverts
            vm.expectRevert();
            LedgerInstance.invest(params);
            assertEq(LedgerInstance.totalInvestedPerRound(_investmentRound), 0);
            assertEq(LedgerInstance.kycAddressInvestedPerRound(_kycAddress, _investmentRound), 0);
        }
    }
}