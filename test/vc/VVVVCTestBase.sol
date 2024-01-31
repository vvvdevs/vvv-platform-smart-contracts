//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "lib/forge-std/src/Test.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { VVVVCInvestmentLedger } from "contracts/vc/VVVVCInvestmentLedger.sol";
import { VVVVCTokenDistributor } from "contracts/vc/VVVVCTokenDistributor.sol";

/**
    @title VVVVC Test Base
 */
abstract contract VVVVCTestBase is Test {
    VVVVCInvestmentLedger LedgerInstance;
    MockERC20 PaymentTokenInstance;
    MockERC20 ProjectTokenInstance;
    VVVVCTokenDistributor TokenDistributorInstance;

    //placeholders for eip712 variables before they are defined
    //by reading the token distributor contract
    bytes32 ledgerDomainSeparator;
    bytes32 distributorDomainSeparator;
    bytes32 investmentTypehash;
    bytes32 claimTypehash;

    //wallet setup
    uint256 deployerKey = 1234;
    uint256 testSignerKey = 12345;
    uint256 sampleUserKey = 1234567;
    uint256 sampleKycAddressKey = 12345678;
    uint256 projectTokenProxyWalletKey = 12345679;

    address deployer = vm.addr(deployerKey);
    address testSigner = vm.addr(testSignerKey);
    address sampleUser = vm.addr(sampleUserKey);
    address sampleKycAddress = vm.addr(sampleKycAddressKey);
    address[] projectTokenProxyWallets = [
        vm.addr(projectTokenProxyWalletKey),
        vm.addr(projectTokenProxyWalletKey + 1),
        vm.addr(projectTokenProxyWalletKey + 2)
    ];
    address[] users = new address[](100); // 100 users

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainId = 31337; //test chain id - leave this alone

    string environmentTag = "development";

    //claim contract-specific values
    uint256 projectTokenAmountToProxyWallet = 1_000_000 * 1e18; //1 million tokens
    uint256[] sampleInvestmentRoundIds = [1, 2, 3];

    // sample invest/claim amounts, keeping relative proportions equal for both
    uint256[] sampleAmountsToInvest = [1000 * 1e6, 2000 * 1e6, 3000 * 1e6];
    uint256[] sampleTokenAmountsToClaim = [1111 * 1e18, 2222 * 1e18, 3333 * 1e18];

    //investment payment tokens
    uint256 paymentTokenMintAmount = 10_000 * 1e6;
    uint256 userPaymentTokenDefaultAllocation = 10_000 * 1e6;
    uint256 investmentRoundSampleLimit = 1_000_000 * 1e6;

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

    function sum(uint256[] memory _array) public pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < _array.length; i++) {
            total += _array[i];
        }
        return total;
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

    function generateInvestParamsWithSignature(
        uint256 _investmentRound,
        uint256 _investmentAmount,
        address _kycAddress
    ) public view returns (VVVVCInvestmentLedger.InvestParams memory) {
        VVVVCInvestmentLedger.InvestParams memory params = VVVVCInvestmentLedger.InvestParams({
            investmentRound: _investmentRound,
            investmentRoundLimit: investmentRoundSampleLimit,
            investmentRoundStartTimestamp: block.timestamp,
            investmentRoundEndTimestamp: block.timestamp + 1 days,
            paymentTokenAddress: address(PaymentTokenInstance),
            kycAddress: _kycAddress,
            kycAddressAllocation: userPaymentTokenDefaultAllocation,
            amountToInvest: _investmentAmount,
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        bytes memory sig = getEIP712SignatureForInvest(ledgerDomainSeparator, investmentTypehash, params);

        params.signature = sig;

        return params;
    }

    function investAsUser(address _investor, VVVVCInvestmentLedger.InvestParams memory _params) public {
        vm.startPrank(_investor, _investor);
        PaymentTokenInstance.approve(address(LedgerInstance), _params.amountToInvest);
        LedgerInstance.invest(_params);
        vm.stopPrank();
    }

    function batchInvestAsUser(
        address _investor,
        uint256[] memory _investmentRoundIds,
        uint256[] memory _amountsToInvest
    ) public {
        VVVVCInvestmentLedger.InvestParams memory investParams;
        for (uint256 i = 0; i < sampleInvestmentRoundIds.length; i++) {
            investParams = generateInvestParamsWithSignature(
                _investmentRoundIds[i],
                _amountsToInvest[i],
                sampleKycAddress
            );
            investAsUser(_investor, investParams);
        }
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

    function generateClaimParamsWithSignature(
        address _callerAddress,
        address[] memory _projectTokenClaimFromWallets,
        uint256[] memory _investmentRoundIds,
        uint256[] memory _tokenAmountsToClaim
    ) public view returns (VVVVCTokenDistributor.ClaimParams memory) {
        VVVVCTokenDistributor.ClaimParams memory params = VVVVCTokenDistributor.ClaimParams({
            callerAddress: _callerAddress,
            userKycAddress: sampleKycAddress,
            projectTokenAddress: address(ProjectTokenInstance),
            projectTokenClaimFromWallets: _projectTokenClaimFromWallets,
            investmentRoundIds: _investmentRoundIds,
            tokenAmountsToClaim: _tokenAmountsToClaim,
            deadline: block.timestamp + 1 hours,
            signature: bytes("placeholder")
        });

        bytes memory sig = getEIP712SignatureForClaim(distributorDomainSeparator, claimTypehash, params);

        params.signature = sig;

        return params;
    }

    function claimAsUser(address _claimant, VVVVCTokenDistributor.ClaimParams memory _params) public {
        vm.startPrank(_claimant, _claimant);
        TokenDistributorInstance.claim(_params);
        vm.stopPrank();
    }
}
