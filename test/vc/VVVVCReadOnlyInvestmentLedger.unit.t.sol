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
        ReadOnlyLedgerInstance = new VVVVCReadOnlyInvestmentLedger(testSigner, environmentTag);
        readOnlyLedgerDomainSeparator = ReadOnlyLedgerInstance.DOMAIN_SEPARATOR();
        setInvestmentRoundRootsTypehash = ReadOnlyLedgerInstance.SET_ROOTS_TYPEHASH();

        vm.stopPrank();
    }

    //Tests deployment of VVVVCReadOnlyInvestmentLedger
    function testDeployment() public {
        assertTrue(address(ReadOnlyLedgerInstance) != address(0));
    }

    //Tests that an admin can set the roots for an investment round
    function testAdminSetInvestmentRoundRoots() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        bytes32 totalInvestedRoot = keccak256(abi.encodePacked(uint256(2)));
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round roots
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundRoots(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundRootsTypehash,
            deployer,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            deadline
        );

        //Set the roots for the investment round
        vm.startPrank(deployer, deployer);
        ReadOnlyLedgerInstance.setInvestmentRoundRoots(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            setRootsSignature,
            deadline
        );
        vm.stopPrank();

        //Verify that the roots were set
        assertEq(ReadOnlyLedgerInstance.kycAddressInvestedRoots(investmentRound), kycAddressInvestedRoot);
        assertEq(ReadOnlyLedgerInstance.totalRoots(investmentRound), totalInvestedRoot);
    }

    //Tests that an admin without a valid signature cannot set the roots for an investment round
    function testAdminWithoutValidSignatureCannotSetInvestmentRoundRoots() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        bytes32 totalInvestedRoot = keccak256(abi.encodePacked(uint256(2)));
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round roots with altered deadline
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundRoots(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundRootsTypehash,
            deployer,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            deadline - 1
        );

        //Attempt to set the roots for the investment round as deployer, reverts via InvalidSignature
        vm.startPrank(deployer, deployer);
        vm.expectRevert(VVVVCReadOnlyInvestmentLedger.InvalidSignature.selector);
        ReadOnlyLedgerInstance.setInvestmentRoundRoots(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            setRootsSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that a non-admin cannot set the roots for an investment round
    function testNonAdminCannotSetInvestmentRoundRoots() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        bytes32 totalInvestedRoot = keccak256(abi.encodePacked(uint256(2)));
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round roots
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundRoots(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundRootsTypehash,
            deployer,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            deadline
        );

        //Attempt to set the roots for the investment round as sampleUser, reverts via AccessControl
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        ReadOnlyLedgerInstance.setInvestmentRoundRoots(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            setRootsSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that the RoundStateSet event is emitted when the roots for an investment round are set
    function testEmitRoundStateSetEvent() public {
        //sample values
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        bytes32 totalInvestedRoot = keccak256(abi.encodePacked(uint256(2)));
        uint256 deadline = block.timestamp + 1000;
        uint256 roundNonce = 1;
        uint256 totalNonce = 1;

        //Generate signature for the round roots
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundRoots(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundRootsTypehash,
            deployer,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            deadline
        );

        //Verify the RoundStateSet event is emitted as defined with the above values
        vm.startPrank(deployer, deployer);
        vm.expectEmit();
        emit VVVVCReadOnlyInvestmentLedger.RoundStateSet(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            block.timestamp,
            roundNonce,
            totalNonce
        );
        ReadOnlyLedgerInstance.setInvestmentRoundRoots(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvestedRoot,
            setRootsSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that an admin can set the signer address
    function testAdminCanSetSignerAddress() public {
        //new signer address
        address newSigner = address(0x1234);

        //set the new signer address
        vm.startPrank(deployer, deployer);
        ReadOnlyLedgerInstance.setSigner(newSigner);
        vm.stopPrank();

        //verify that the signer address was set
        assertEq(ReadOnlyLedgerInstance.signer(), newSigner);
    }

    //Tests that a non-admin cannot set the signer address
    function testNonAdminCannotSetSignerAddress() public {
        //new signer address
        address newSigner = address(0x1234);

        //attempt to set signer as sampleUser, reverts via AccessControl
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        ReadOnlyLedgerInstance.setSigner(newSigner);
        vm.stopPrank();
    }
}
