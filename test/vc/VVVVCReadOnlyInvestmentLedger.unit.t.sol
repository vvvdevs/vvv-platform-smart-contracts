//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { VVVVCReadOnlyInvestmentLedger } from "contracts/vc/VVVVCReadOnlyInvestmentLedger.sol";

/**
 * @title VVVVCReadOnlyInvestmentLedger Unit Tests
 * @dev use "forge test --match-contract VVVVCReadOnlyInvestmentLedgerUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCReadOnlyInvestmentLedger" to run coverage
 */
contract VVVVCReadOnlyInvestmentLedgerUnitTests is VVVVCTestBase {
    function setUp() public {
        vm.startPrank(deployer, deployer);

        // deploy the read-only investment ledger
        address[] memory signers = new address[](1);
        signers[0] = testSigner;
        ReadOnlyLedgerInstance = new VVVVCReadOnlyInvestmentLedger(signers, environmentTag);
        readOnlyLedgerDomainSeparator = ReadOnlyLedgerInstance.DOMAIN_SEPARATOR();
        setInvestmentRoundStateTypehash = ReadOnlyLedgerInstance.STATE_TYPEHASH();

        vm.stopPrank();
    }

    //Tests deployment of VVVVCReadOnlyInvestmentLedger
    function testDeployment() public {
        assertTrue(address(ReadOnlyLedgerInstance) != address(0));
    }

    //Tests that the state for an investment round can be set with authorized signer and valid signature
    function testSetInvestmentRoundState() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round state
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deadline
        );

        //Set the state for the investment round
        vm.startPrank(deployer, deployer);
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            testSigner,
            setStateSignature,
            deadline
        );
        vm.stopPrank();

        //Verify that the state was set
        assertEq(ReadOnlyLedgerInstance.kycAddressInvestedRoots(investmentRound), kycAddressInvestedRoot);
        assertEq(ReadOnlyLedgerInstance.totalInvestedPerRound(investmentRound), totalInvested);
    }

    //Tests that an invalid signature will cause a revert with the InvalidSignature error
    function testAdminWithoutValidSignatureCannotSetInvestmentRoundState() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round state with altered deadline
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deadline - 1
        );

        //Attempt to set the state for the investment round as deployer, reverts via InvalidSignature
        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVCReadOnlyInvestmentLedger.InvalidSignature.selector);
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            testSigner,
            setStateSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that a call to setInvestmentRoundState with an unauthorized signer reverts even with a valid signature
    function testSetInvestmentRoundStateUnauthorizedSigner() public {
        //sample state and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate correct signature for the round state
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deadline
        );

        //Attempt to set the state, reverts as UnauthorizedSigner because deployer is supplied as signer
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCReadOnlyInvestmentLedger.UnauthorizedSigner.selector);
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deployer,
            setStateSignature,
            deadline
        );
        vm.stopPrank();
    }

    //tests that replay attacks are not possible via nonce update
    function testSetInvestmentRoundStateReplayAttack() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round state
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deadline
        );

        //Set the state for the investment round
        vm.startPrank(deployer, deployer);
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            testSigner,
            setStateSignature,
            deadline
        );

        //Attempt to replay w/ same signature, reverts with InvalidSignature()
        vm.expectRevert(VVVVCReadOnlyInvestmentLedger.InvalidSignature.selector);
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            testSigner,
            setStateSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that the RoundStateSet event is emitted when the state for an investment round is set
    function testEmitRoundStateSetEvent() public {
        //sample values
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;
        uint256 nonce = 1;

        //Generate signature for the round state
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            deadline
        );

        //Verify the RoundStateSet event is emitted as defined with the above values
        vm.startPrank(deployer, deployer);
        vm.expectEmit();
        emit VVVVCReadOnlyInvestmentLedger.RoundStateSet(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            nonce
        );
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
            testSigner,
            setRootsSignature,
            deadline
        );
        vm.stopPrank();
    }
}
