//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "lib/forge-std/src/Test.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";

/**
    @title VVVVCTokenDistributor Test Base
 */
abstract contract VVVVCTokenDistributorBase is Test {
    VVVVCInvestmentLedger LedgerInstance;
    MockERC20 ProjectTokenInstance;
    VVVVCTokenDistributor TokenDistributorInstance;

    //placeholders for eip712 variables before they are defined
    //by reading the token distributor contract
    bytes32 domainSeparator;
    bytes32 claimTypehash;

    //wallet setup
    uint256 deployerKey = 1234;
    uint256 testSignerKey = 12345;
    uint256 sampleUserKey = 1234567;
    uint256 projectTokenProxyWalletKey = 12345678;

    address deployer = vm.addr(deployerKey);
    address testSigner = vm.addr(testSignerKey);
    address sampleUser = vm.addr(sampleUserKey);
    address[] projectTokenProxyWallets = [
        vm.addr(projectTokenProxyWalletKey),
        vm.addr(projectTokenProxyWalletKey + 1),
        vm.addr(projectTokenProxyWalletKey + 2)
    ];

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainId = 31337; //test chain id - leave this alone

    string domainTag = "development";

    //contract-specific values
    uint256 projectTokenAmountToProxyWallet = 1_000_000 * 1e18; //1 million tokens
    uint256[] sampleInvestmentRoundIds = [1, 2, 3];
    uint256[] sampleTokenAmountsToClaim = [1111, 2222, 3333];

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

    function getEIP712SignatureForClaim(
        bytes32 _domainSeparator,
        bytes32 _investmentTypehash,
        VVVVCTokenDistributor.ClaimParams memory _params
    ) public view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                keccak256(
                    abi.encode(
                        _investmentTypehash,
                        _params.callerAddress,
                        _params.userKycAddress,
                        _params.projectTokenAddress,
                        _params.projectTokenClaimFromWallets,
                        _params.investmentRoundIds,
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

    function generateClaimParamsWithSignature()
        public
        view
        returns (VVVVCTokenDistributor.ClaimParams memory)
    {
        VVVVCTokenDistributor.ClaimParams memory params = VVVVCTokenDistributor.ClaimParams({
            callerAddress: sampleUser,
            userKycAddress: sampleUser,
            projectTokenAddress: address(ProjectTokenInstance),
            projectTokenClaimFromWallets: projectTokenProxyWallets,
            investmentRoundIds: sampleInvestmentRoundIds,
            tokenAmountsToClaim: sampleTokenAmountsToClaim,
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        bytes memory sig = getEIP712SignatureForClaim(domainSeparator, claimTypehash, params);

        params.signature = sig;

        return params;
    }

    function claimAsUser(address _claimant, VVVVCTokenDistributor.ClaimParams memory _params) public {
        vm.startPrank(_claimant, _claimant);
        TokenDistributorInstance.claim(_params);
        vm.stopPrank();
    }
}
