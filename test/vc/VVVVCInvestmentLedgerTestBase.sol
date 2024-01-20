//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @dev Base for testing VVVVCInvestmentLedger.sol
 */

import "lib/forge-std/src/Test.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";

abstract contract VVVVCInvestmentLedgerTestBase is Test {
    MockERC20 ProjectTokenInstance;
    MockERC20 PaymentTokenInstance;
    VVVVCInvestmentLedger LedgerInstance;

    //placeholders for eip712 variables before they are defined
    //by reading the investment ledger contract
    bytes32 domainSeparator;
    bytes32 investmentTypehash;

    string environmentTag = "development";

    uint256 deployerKey = 1234;
    uint256 testSignerKey = 12345;
    uint256 sampleUserKey = 1234567;
    uint256 sampleKycAddressKey = 12345678;

    address deployer = vm.addr(deployerKey);
    address testSigner = vm.addr(testSignerKey);
    address sampleKycAddress = vm.addr(sampleKycAddressKey);
    address sampleUser = vm.addr(sampleUserKey);
    address[] users = new address[](100); // 100 users

    uint256 paymentTokenMintAmount = 10_000 * 1e6;
    uint256 userPaymentTokenDefaultAllocation = 10_000 * 1e6;

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainId = 31337; //test chain id - leave this alone

    function advanceBlockNumberAndTimestampInBlocks(uint256 blocks) public {
        blockNumber += blocks;
        blockTimestamp += blocks * 12; //seconds per block
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    function advanceBlockNumberAndTimestampInSeconds(uint256 secondsToAdvance) public {
        blockNumber += secondsToAdvance / 12; //seconds per block
        blockTimestamp += secondsToAdvance;
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    // generate list of random addresses and deal them payment tokens and ETH
    function generateUserAddressListAndDealEtherAndToken(MockERC20 _token) public {
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
            _token.mint(users[i], paymentTokenMintAmount);
        }

        vm.deal(sampleUser, 10 ether);
        vm.deal(sampleKycAddress, 10 ether);
    }

    // create concat'd 65 byte signature that ethers would generate instead of r,s,v
    function toBytesConcat(bytes32 r, bytes32 s, uint8 v) public pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        for (uint256 i = 0; i < 32; i++) {
            signature[i] = r[i];
            signature[i + 32] = s[i];
        }
        signature[64] = bytes1(v);
        return signature;
    }

    function getEIP712SignatureForInvest(
        bytes32 _domainSeparator,
        bytes32 _investmentTypehash,
        VVVVCInvestmentLedger.InvestParams memory _params
    ) public view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                keccak256(
                    abi.encode(
                        _investmentTypehash,
                        _params.investmentRound,
                        _params.investmentRoundLimit,
                        _params.investmentRoundStartTimestamp,
                        _params.investmentRoundEndTimestamp,
                        _params.paymentTokenAddress,
                        _params.kycAddress,
                        _params.kycAddressAllocation,
                        _params.deadline,
                        chainId
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testSignerKey, digest);
        bytes memory signature = toBytesConcat(r, s, v);

        return signature;
    }

    function generateInvestParamsWithSignature()
        public
        view
        returns (VVVVCInvestmentLedger.InvestParams memory)
    {
        VVVVCInvestmentLedger.InvestParams memory params = VVVVCInvestmentLedger.InvestParams({
            investmentRound: 1,
            investmentRoundLimit: 100_000 * PaymentTokenInstance.decimals(),
            investmentRoundStartTimestamp: block.timestamp,
            investmentRoundEndTimestamp: block.timestamp + 1 days,
            paymentTokenAddress: address(PaymentTokenInstance),
            kycAddress: sampleUser,
            kycAddressAllocation: userPaymentTokenDefaultAllocation,
            amountToInvest: 1_000 * PaymentTokenInstance.decimals(),
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        bytes memory sig = getEIP712SignatureForInvest(domainSeparator, investmentTypehash, params);

        params.signature = sig;

        return params;
    }

    function investAsUser(address _investor, VVVVCInvestmentLedger.InvestParams memory _params) public {
        vm.startPrank(_investor, _investor);
        PaymentTokenInstance.approve(address(LedgerInstance), _params.amountToInvest);
        LedgerInstance.invest(_params);
        vm.stopPrank();
    }
}
