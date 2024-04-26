//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVVVVCReadOnlyInvestmentLedger } from "./IVVVVCReadOnlyInvestmentLedger.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVVCAlternateTokenDistributor {
    using SafeERC20 for IERC20;

    IVVVVCReadOnlyInvestmentLedger public readOnlyLedger;

    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256(
            bytes(
                "ClaimParams(address callerAddress,address userKycAddress,address projectTokenAddress,address[] projectTokenProxyWallets,uint256[] investmentRoundIds,uint256 deadline,bytes32[] investmentLeaves,bytes32[][] investmentProofs)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice Mapping of user's KYC address to investment round to claimed amount
    mapping(address => mapping(uint256 => uint256)) public userClaimedTokensForRound;

    /// @notice Mapping of the round ID to the token's total claimed amount
    mapping(uint256 => uint256) public totalClaimedTokensForRound;

    /**
        @notice Parameters for claim function
        @param callerAddress Address of the caller (alias for KYC address)
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenProxyWallets Array of addresses of the wallets from which the project token is to be claimed
        @param investmentRoundIds Array of read-only ledger investment round ids involved in the claim
        @param tokenAmountToClaim Total (combined across all rounds) amount of project tokens to claim
        @param deadline Deadline for signature validity
        @param signature Signature of the user's KYC wallet address
        @param investedPerRound Array of the user's stable equivalent amount invested per round
        @param investmentLeaves array of merkle tree leaves, one for each round for which to verify invested amount on read-only ledger
        @param investmentProofs array of merkle tree proofs, one for each round for which to verify invested amount on read-only ledger
     */
    struct ClaimParams {
        address callerAddress;
        address userKycAddress;
        address projectTokenAddress;
        address[] projectTokenProxyWallets;
        uint256[] investmentRoundIds;
        uint256 tokenAmountToClaim;
        uint256 deadline;
        bytes signature;
        uint256[] investedPerRound;
        bytes32[] investmentLeaves;
        bytes32[][] investmentProofs;
    }

    /**
        @notice Emitted when a user claims tokens
        @param userKycAddress Address of the user's KYC wallet
        @param callerAddress Address of the caller (alias for KYC address)
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenProxyWallets Addresses of the wallets from which the project token is to be claimed
        @param claimedTokenAmount Total amount of project tokens claimed
     */
    event VCClaim(
        address indexed userKycAddress,
        address indexed callerAddress,
        address indexed projectTokenAddress,
        address[] projectTokenProxyWallets,
        uint256 claimedTokenAmount
    );

    /// @notice Error thrown when the caller's allocation or proxy wallet balance has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    ///@notice Error thrown when the merkle proof is invalid
    error InvalidMerkleProof();

    constructor(address _signer, address _readOnlyLedger, string memory _environmentTag) {
        signer = _signer;
        readOnlyLedger = IVVVVCReadOnlyInvestmentLedger(_readOnlyLedger);

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
        @notice Allows any address which is an alias of a KYC address to claim tokens across multiple rounds which provide that token
        @param _params A ClaimParams struct describing the desired claim(s) and associated merkle proof(s) for amount(s) invested
     */
    function claim(ClaimParams memory _params) public {
        //ensure caller (msg.sender) is an alias of the KYC address
        _params.callerAddress = msg.sender;

        if (!_areMerkleProofsValid(_params)) {
            revert InvalidMerkleProof();
        }

        if (!_isSignatureValid(_params)) {
            revert InvalidSignature();
        }

        IERC20 projectToken = IERC20(_params.projectTokenAddress);

        //transfer the full claimable amount per round to the caller, unless
        //the remainder of the target claim amount is less than the claimable amount
        uint256 remainingAmountToClaim = _params.tokenAmountToClaim;
        for (uint256 i = 0; i < _params.investmentRoundIds.length; i++) {
            address thisProxyWallet = _params.projectTokenProxyWallets[i];
            uint256 thisInvestmentRoundId = _params.investmentRoundIds[i];

            uint256 baseClaimableFromWallet = _calculateBaseClaimableProjectTokens(
                _params.projectTokenAddress,
                thisProxyWallet,
                thisInvestmentRoundId,
                _params.investedPerRound[i]
            );
            uint256 claimableFromWallet = baseClaimableFromWallet -
                userClaimedTokensForRound[_params.userKycAddress][thisInvestmentRoundId];

            uint256 amountToClaim = claimableFromWallet > remainingAmountToClaim
                ? remainingAmountToClaim
                : claimableFromWallet;

            userClaimedTokensForRound[_params.userKycAddress][thisInvestmentRoundId] += amountToClaim;
            totalClaimedTokensForRound[thisInvestmentRoundId] += amountToClaim;
            remainingAmountToClaim -= amountToClaim;

            projectToken.safeTransferFrom(thisProxyWallet, _params.callerAddress, amountToClaim);

            if (remainingAmountToClaim == 0) {
                break;
            }
        }

        //if an amount is remaining, the caller is attempting to exceed their allocation
        if (remainingAmountToClaim != 0) {
            revert ExceedsAllocation();
        }

        emit VCClaim(
            _params.userKycAddress,
            _params.callerAddress,
            _params.projectTokenAddress,
            _params.projectTokenProxyWallets,
            _params.tokenAmountToClaim
        );
    }

    /**
        @notice external wrapper for _calculateBaseClaimableProjectTokens
        @dev does not validate the invested amount, assumes it is validated in the call to claim()
     */
    function calculateBaseClaimableProjectTokens(
        address _projectTokenAddress,
        address _proxyWalletAddress,
        uint256 _investmentRoundId,
        uint256 _userInvestedPaymentTokens
    ) external view returns (uint256) {
        return
            _calculateBaseClaimableProjectTokens(
                _projectTokenAddress,
                _proxyWalletAddress,
                _investmentRoundId,
                _userInvestedPaymentTokens
            );
    }

    /// @notice external wrapper for _isSignatureValid
    function isSignatureValid(ClaimParams memory _params) external view returns (bool) {
        return _isSignatureValid(_params);
    }

    /// @notice external wrapper for _areMerkleProofsValid
    function areMerkleProofsValid(ClaimParams memory _params) external view returns (bool) {
        return _areMerkleProofsValid(_params);
    }

    /**
        @notice Reads the VVVVCInvestmentLedger contract to calculate the base claimable token amount, which does not consider the amount already claimed by the KYC address
        @dev uses fraction of invested funds to determine fraction of claimable tokens
        @dev ensure _proxyWalletAddress corresponds to the _investmentRoundId
        @param _projectTokenAddress Address of the project token to be claimed
        @param _proxyWalletAddress Address of the wallet from which the project token is to be claimed
        @param _investmentRoundId Investment round ID for which to calculate claimable tokens
        @param _userInvestedPaymentTokens Amount of payment tokens the user has invested in this round, assumed to be validated in the call to claim() via Merkle proof
     */
    function _calculateBaseClaimableProjectTokens(
        address _projectTokenAddress,
        address _proxyWalletAddress,
        uint256 _investmentRoundId,
        uint256 _userInvestedPaymentTokens
    ) private view returns (uint256) {
        if (_userInvestedPaymentTokens == 0) return 0;

        uint256 totalInvestedPaymentTokens = readOnlyLedger.totalInvestedPerRound(_investmentRoundId);

        //total pool of claimable tokens is balance of proxy wallets + total claimed for this token address
        uint256 totalProjectTokensDepositedToProxyWallet = IERC20(_projectTokenAddress).balanceOf(
            _proxyWalletAddress
        ) + totalClaimedTokensForRound[_investmentRoundId];

        //return fraction of total pool of claimable tokens, based on fraction of invested funds
        return
            (_userInvestedPaymentTokens * totalProjectTokensDepositedToProxyWallet) /
            totalInvestedPaymentTokens;
    }

    /**
     * @notice Checks if the provided signature is valid
     * @param _params A ClaimParams struct containing the investment parameters
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(ClaimParams memory _params) private view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        CLAIM_TYPEHASH,
                        _params.callerAddress,
                        _params.userKycAddress,
                        _params.projectTokenAddress,
                        _params.projectTokenProxyWallets,
                        _params.investmentRoundIds,
                        _params.deadline,
                        _params.investmentLeaves,
                        _params.investmentProofs
                    )
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _params.signature);

        bool isSigner = recoveredAddress == signer;
        bool isExpired = block.timestamp > _params.deadline;
        return isSigner && !isExpired;
    }

    ///@notice verifies user investment assertions at time of claim with merkle proofs. returns false if any of the proofs are invalid
    function _areMerkleProofsValid(ClaimParams memory _params) private view returns (bool) {
        bytes32[] memory investmentRoots = readOnlyLedger.getInvestmentRoots(_params.investmentRoundIds);

        for (uint256 i = 0; i < _params.investmentRoundIds.length; i++) {
            if (
                !MerkleProof.verify(
                    _params.investmentProofs[i],
                    investmentRoots[i],
                    _params.investmentLeaves[i]
                )
            ) {
                return false;
            }
        }

        return true;
    }
}
