//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract VVVVCReadOnlyInvestmentLedger is AccessControl {
    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant STATE_TYPEHASH =
        keccak256(
            bytes(
                "RoundState(uint256 investmentRound,bytes32 kycAddressInvestedRoot,uint256 totalInvested,uint256 deadline,uint256 nonce)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice nonce for all combined round state updates
    uint256 public nonce;

    /// @notice root for each round which validates kyc address amounts invested
    mapping(uint256 => bytes32) public kycAddressInvestedRoots;

    /// @notice stable-equivalent invested for each round
    mapping(uint256 => uint256) public totalInvestedPerRound;

    /// @notice emitted when a round's state is set (for both per-user and total invested amounts)
    event RoundStateSet(
        uint256 investmentRound,
        bytes32 kycAddressInvestedRoot,
        uint256 totalInvested,
        uint256 nonce
    );

    /// @notice thrown when a signature is invalid
    error InvalidSignature();

    /// @notice thrown when the signer input argument does not hold SIGNER_ROLE
    error UnauthorizedSigner();

    constructor(address[] memory _signers, string memory _environmentTag) {
        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(abi.encodePacked("VVV", _environmentTag)),
                block.chainid,
                address(this)
            )
        );

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _signers.length; i++) {
            _grantRole(SIGNER_ROLE, _signers[i]);
        }
    }

    /**
     * @notice Sets the root for the kyc address invested amounts + the total invested amount for a given round
     */
    function setInvestmentRoundState(
        uint256 _investmentRound,
        bytes32 _kycAddressInvestedRoot,
        uint256 _totalInvested,
        address _signer,
        bytes calldata _signature,
        uint256 _deadline
    ) external {
        if (!hasRole(SIGNER_ROLE, _signer)) {
            revert UnauthorizedSigner();
        }

        if (
            !_isSignatureValid(
                _investmentRound,
                _kycAddressInvestedRoot,
                _totalInvested,
                _signer,
                _signature,
                _deadline
            )
        ) {
            revert InvalidSignature();
        }

        kycAddressInvestedRoots[_investmentRound] = _kycAddressInvestedRoot;
        totalInvestedPerRound[_investmentRound] = _totalInvested;

        ++nonce;

        emit RoundStateSet(_investmentRound, _kycAddressInvestedRoot, _totalInvested, nonce);
    }

    ///@notice outputs array of investment roots for given round ids
    function getInvestmentRoots(uint256[] calldata _roundIds) external view returns (bytes32[] memory) {
        bytes32[] memory investmentRoots = new bytes32[](_roundIds.length);
        for (uint256 i = 0; i < _roundIds.length; i++) {
            investmentRoots[i] = kycAddressInvestedRoots[_roundIds[i]];
        }
        return investmentRoots;
    }

    /**
     * @notice Checks if the provided signature is valid
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(
        uint256 _investmentRound,
        bytes32 _kycAddressInvestedRoot,
        uint256 _totalInvested,
        address _signer,
        bytes calldata _signature,
        uint256 _deadline
    ) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        STATE_TYPEHASH,
                        _investmentRound,
                        _kycAddressInvestedRoot,
                        _totalInvested,
                        _deadline,
                        nonce
                    )
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _signature);
        bool isSigner = recoveredAddress == _signer;
        bool isExpired = block.timestamp > _deadline;

        return isSigner && !isExpired;
    }
}
