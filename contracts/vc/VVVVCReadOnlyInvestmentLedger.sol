//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract VVVVCReadOnlyInvestmentLedger is AccessControl {
    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant SET_ROOTS_TYPEHASH =
        keccak256(
            bytes(
                "RoundStateSet(uint256 investmentRound, bytes32 kycAddressInvestedRoot, bytes32 totalInvestedRoot, uint256 timestamp, uint256 roundNonce, uint256 totalNonce)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant ROOT_SETTER_ROLE = keccak256("ROOT_SETTER_ROLE");

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice nonce for all combined round state updates
    uint256 public totalNonce;

    /// @notice root for each round which validates kyc address amounts invested
    mapping(uint256 => bytes32) public kycAddressInvestedRoots;

    /// @notice root for each round which validates total amounts invested
    mapping(uint256 => bytes32) public totalRoots;

    /// @notice nonce for each round's state
    mapping(uint256 => uint256) public roundNonces;

    /// @notice emitted when a round's state is set (for both per-user and total invested amounts)
    event RoundStateSet(
        uint256 investmentRound,
        bytes32 kycAddressInvestedRoot,
        bytes32 totalInvestedRoot,
        uint256 timestamp,
        uint256 roundNonce,
        uint256 totalNonce
    );

    /// @notice thrown when a signature is invalid
    error InvalidSignature();

    constructor(address _signer, string memory _environmentTag) {
        signer = _signer;

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(abi.encodePacked("VVV", _environmentTag)),
                block.chainid,
                address(this)
            )
        );

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ROOT_SETTER_ROLE, _msgSender());
    }

    /**
     * @notice Sets the roots for the kyc address invested amounts and total invested amounts for a given round
     * @dev
     */
    function setInvestmentRoundRoots(
        uint256 _investmentRound,
        bytes32 _kycAddressInvestedRoot,
        bytes32 _totalInvestedRoot,
        bytes calldata _signature,
        uint256 _deadline
    ) external onlyRole(ROOT_SETTER_ROLE) {
        if (!_isSignatureValid(_kycAddressInvestedRoot, _totalInvestedRoot, _signature, _deadline))
            revert InvalidSignature();

        kycAddressInvestedRoots[_investmentRound] = _kycAddressInvestedRoot;
        totalRoots[_investmentRound] = _totalInvestedRoot;
        ++roundNonces[_investmentRound];
        ++totalNonce;

        emit RoundStateSet(
            _investmentRound,
            _kycAddressInvestedRoot,
            _totalInvestedRoot,
            block.timestamp,
            roundNonces[_investmentRound],
            totalNonce
        );
    }

    ///@notice allows admin to set the signer address
    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    /**
     * @notice Checks if the provided signature is valid
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(
        bytes32 _kycAddressInvestedRoot,
        bytes32 _totalInvestedRoot,
        bytes calldata _signature,
        uint256 _deadline
    ) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        SET_ROOTS_TYPEHASH,
                        msg.sender,
                        _kycAddressInvestedRoot,
                        _totalInvestedRoot,
                        _deadline,
                        block.chainid
                    )
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _signature);
        bool isSigner = recoveredAddress == signer;
        bool isExpired = block.timestamp > _deadline;

        return isSigner && !isExpired;
    }
}
