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

    // EIP-712 definitions, copied from VVVVCInvestmentLedger.sol 
    // because they are private/immutable there
    bytes32 domainTypehash =
        keccak256(
            bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        );
    bytes32 investmentTypehash =
        keccak256(
            bytes("VCInvestment(bytes32 investmentRound,address kycAddress,uint256 investmentAmount)")
        );
    bytes32 domainSeparator;

    uint256 deployerKey = 1234;
    uint256 testSignerKey = 12345;
    uint256 kycAddressKey = 123456;   
    uint256 sampleUserKey = 1234567;
    uint256 sampleKycAddressKey = 12345678;

    address deployer = vm.addr(deployerKey);
    address testSigner = vm.addr(testSignerKey);
    address kycAddress = vm.addr(kycAddressKey);
    address sampleKycAddress = vm.addr(sampleKycAddressKey);
    address sampleUser = vm.addr(sampleUserKey);
    address[] users = new address[](100); // 100 users


    uint256 initialPaymentTokenSupply = 1_000_000 * 1e6; // for both tokens
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
    function generateUserAddressListAndDealEtherAndMockStable(MockERC20 _token) public {
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
            _token.mint(users[i], paymentTokenMintAmount);
        }

        sampleKycAddress = users[0];
        sampleUser = users[1];
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
        bytes32 _eip712_domain_typehash,
        bytes32 _domain_separator,
        bytes32 _investment_typehash,
        VVVVCInvestmentLedger.InvestParams memory p
    ) public returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domain_separator,
                keccak256(
                    abi.encode(
                        _investment_typehash,
                        p.investmentRound,
                        p.investmentRoundLimit,
                        p.investmentRoundStartTimestamp,
                        p.investmentRoundEndTimestamp,
                        p.investmentCustodian,
                        p.paymentTokenAddress,
                        p.kycAddress,
                        p.kycAddressAllocation,
                        p.deadline,
                        chainId
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testSignerKey, digest);
        bytes memory signature = toBytesConcat(r, s, v);

        return signature;
    }


}
