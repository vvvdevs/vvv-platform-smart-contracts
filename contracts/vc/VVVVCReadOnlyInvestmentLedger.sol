//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract VVVVCReadOnlyInvestmentLedger is AccessControl {
    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant SET_STATE_TYPEHASH =
        keccak256(
            bytes("ContractStateSet(address caller, bytes32 stateHash, uint256 timestamp, uint256 nonce)")
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice stores kyc address amounts invested for each investment round
    mapping(address => mapping(uint256 => uint256)) public kycAddressInvestedPerRound;

    /// @notice stores total amounts invested for each investment round
    mapping(uint256 => uint256) public totalInvestedPerRound;

    /// @notice emitted when a contract state is set
    event ContractStateSet(address caller, bytes32 stateHash, uint256 timestamp, uint256 nonce);

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
    }

    /**
     * @notice Sets the state of the contract
     * @dev overwrites the previous storage state using a known
     * @param _state The state to set
     * @param _signature The signature of the state
     */
    function setContractState(
        bytes calldata _state,
        bytes calldata _signature,
        uint256 _deadline
    ) external {
        if (!_isSignatureValid(_state, _signature, _deadline)) revert InvalidSignature();

        // state here

        emit ContractStateSet(msg.sender, keccak256(_state), block.timestamp, 0);
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
        bytes calldata _state,
        bytes calldata _signature,
        uint256 _deadline
    ) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(SET_STATE_TYPEHASH, msg.sender, _state, _deadline, block.chainid))
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _signature);
        bool isSigner = recoveredAddress == signer;
        bool isExpired = block.timestamp > _deadline;

        return isSigner && !isExpired;
    }
}
