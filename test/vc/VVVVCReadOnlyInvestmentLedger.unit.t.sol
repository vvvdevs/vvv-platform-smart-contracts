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
        setInvestmentRoundStateTypehash = ReadOnlyLedgerInstance.SET_STATE_TYPEHASH();

        vm.stopPrank();
    }

    //Tests deployment of VVVVCReadOnlyInvestmentLedger
    function testDeployment() public {
        assertTrue(address(ReadOnlyLedgerInstance) != address(0));
    }

    //Tests that an admin can set the state for an investment round
    function testAdminSetInvestmentRoundState() public {
        //sample roots and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round state
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            deployer,
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
            setStateSignature,
            deadline
        );
        vm.stopPrank();

        //Verify that the state was set
        assertEq(ReadOnlyLedgerInstance.kycAddressInvestedRoots(investmentRound), kycAddressInvestedRoot);
        assertEq(ReadOnlyLedgerInstance.totalInvested(investmentRound), totalInvested);
    }

    //Tests that an admin without a valid signature cannot set the state for an investment round
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
            deployer,
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
            setStateSignature,
            deadline
        );
        vm.stopPrank();
    }

    //Tests that a non-admin cannot set the state for an investment round
    function testNonAdminCannotSetInvestmentRoundState() public {
        //sample state and deadline for investment round
        uint256 investmentRound = 1;
        bytes32 kycAddressInvestedRoot = keccak256(abi.encodePacked(uint256(1)));
        uint256 totalInvested = 2;
        uint256 deadline = block.timestamp + 1000;

        //Generate signature for the round state
        bytes memory setStateSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            deployer,
            kycAddressInvestedRoot,
            totalInvested,
            deadline
        );

        //Attempt to set the state for the investment round as sampleUser, reverts via AccessControl
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
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
        uint256 roundNonce = 1;
        uint256 totalNonce = 1;

        //Generate signature for the round state
        bytes memory setRootsSignature = getEIP712SignatureForSetInvestmentRoundState(
            readOnlyLedgerDomainSeparator,
            setInvestmentRoundStateTypehash,
            deployer,
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
            block.timestamp,
            roundNonce,
            totalNonce
        );
        ReadOnlyLedgerInstance.setInvestmentRoundState(
            investmentRound,
            kycAddressInvestedRoot,
            totalInvested,
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
