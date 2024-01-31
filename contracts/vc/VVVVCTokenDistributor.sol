//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVVVVCInvestmentLedger } from "./IVVVVCInvestmentLedger.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVVCTokenDistributor is Ownable {
    using SafeERC20 for IERC20;

    IVVVVCInvestmentLedger public ledger;

    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        );
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256(
            bytes(
                "VCClaim(address userKycAddress,address projectTokenAddress, address projectTokenClaimFromWallet, uint256 investmentRoundId, uint256 claimedTokenAmount)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice Mapping of user's KYC address to project token address to investment round id to claimable token amount
    mapping(address => mapping(uint256 => uint256)) public userClaimedTokensForRound;

    /// @notice Mapping of the round ID to the round's total claimed tokens
    mapping(uint256 => uint256) public totalClaimedTokensForRound;

    /**
        @notice Parameters for claim function
        @param callerAddress Address of the caller (alias for KYC address)
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallets Array of addresses of the wallets from which the project token is to be claimed
        @param investmentRoundIds Array of investment round ids, corresponding to the project token claim from wallets
        @param tokenAmountsToClaim Array of token amounts to be claimed, corresponding to the project token claim from wallets
        @param deadline Deadline for signature validity
        @param signature Signature of the user's KYC wallet address
     */
    struct ClaimParams {
        address callerAddress;
        address userKycAddress;
        address projectTokenAddress;
        address[] projectTokenClaimFromWallets;
        uint256[] investmentRoundIds;
        uint256[] tokenAmountsToClaim;
        uint256 deadline;
        bytes signature;
    }

    /**
        @notice Emitted when a user claims tokens
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallet Address of the wallet from which the project token is to be claimed
        @param investmentRoundId Id of the investment round for which the claimable token amount is to be calculated
     */
    event VCClaim(
        address indexed userKycAddress,
        address indexed projectTokenAddress,
        address indexed projectTokenClaimFromWallet,
        uint256 investmentRoundId,
        uint256 claimedTokenAmount
    );

    /// @notice Error thrown when the caller's allocation or proxy wallet balance has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    constructor(address _signer, address _ledger, string memory _environmentTag) Ownable(msg.sender) {
        signer = _signer;
        ledger = IVVVVCInvestmentLedger(_ledger);

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(abi.encodePacked("VVV_", _environmentTag)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
        @notice Allows any address which is an alias of a KYC address to claim tokens for an investment
        @param _params A ClaimParams struct describing the desired claim(s)
     */
    function claim(ClaimParams memory _params) public {
        //ensure caller (msg.sender) is an alias of the KYC address
        _params.callerAddress = msg.sender;

        if (!_isSignatureValid(_params)) {
            revert InvalidSignature();
        }

        //for each wallet (corresponding to each investment round), check if desired claim amount is not more than claimable amount
        for (uint256 i = 0; i < _params.projectTokenClaimFromWallets.length; ++i) {
            //KYC address's claimable tokens for round, considering those already claimed
            uint256 thisClaimableAmount = _calculateBaseClaimableProjectTokens(
                _params.userKycAddress,
                _params.projectTokenAddress,
                _params.projectTokenClaimFromWallets[i],
                _params.investmentRoundIds[i]
            ) - userClaimedTokensForRound[_params.userKycAddress][_params.investmentRoundIds[i]];

            //check desired claim amount is not more than claimable amount
            if (_params.tokenAmountsToClaim[i] > thisClaimableAmount) {
                revert ExceedsAllocation();
            }

            //update tokens claimed, transfer project tokens from proxy wallet
            userClaimedTokensForRound[_params.userKycAddress][_params.investmentRoundIds[i]] += _params
                .tokenAmountsToClaim[i];

            totalClaimedTokensForRound[_params.investmentRoundIds[i]] += _params.tokenAmountsToClaim[i];

            IERC20(_params.projectTokenAddress).safeTransferFrom(
                _params.projectTokenClaimFromWallets[i],
                _params.callerAddress,
                _params.tokenAmountsToClaim[i]
            );

            emit VCClaim(
                _params.callerAddress,
                _params.projectTokenAddress,
                _params.projectTokenClaimFromWallets[i],
                _params.investmentRoundIds[i],
                _params.tokenAmountsToClaim[i]
            );
        }
    }

    /**
        @notice Reads the VVVVCInvestmentLedger contract to calculate the base claimable token amount, which does not consider the amount already claimed by the KYC address
        @dev uses fraction of invested funds to determine fraction of claimable tokens
        @param _userKycAddress Address of the user's KYC wallet
        @param _projectTokenAddress Address of the project token to be claimed
        @param _proxyWalletAddress Address of the wallet from which the project token is to be claimed
        @param _investmentRoundId Id of the investment round for which the claimable token amount is to be calculated
     */
    function _calculateBaseClaimableProjectTokens(
        address _userKycAddress,
        address _projectTokenAddress,
        address _proxyWalletAddress,
        uint256 _investmentRoundId
    ) internal view returns (uint256) {
        uint256 totalInvestedPaymentTokens = ledger.totalInvestedPerRound(_investmentRoundId);
        uint256 userInvestedPaymentTokens = ledger.kycAddressInvestedPerRound(
            _userKycAddress,
            _investmentRoundId
        );

        //total pool of claimable tokens is balance of proxy wallet + total claimed tokens from that same wallet
        uint256 totalProjectTokensDepositedToProxyWallet = IERC20(_projectTokenAddress).balanceOf(
            _proxyWalletAddress
        ) + totalClaimedTokensForRound[_investmentRoundId];

        //return fraction of total pool of claimable tokens, based on fraction of invested funds
        return
            (userInvestedPaymentTokens * totalProjectTokensDepositedToProxyWallet) /
            totalInvestedPaymentTokens;
    }

    /**
     * @notice Checks if the provided signature is valid
     * @param _params A ClaimParams struct containing the investment parameters
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(ClaimParams memory _params) internal view returns (bool) {
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
                        _params.projectTokenClaimFromWallets,
                        _params.investmentRoundIds,
                        _params.deadline,
                        block.chainid
                    )
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _params.signature);

        bool isSigner = recoveredAddress == signer;
        bool isExpired = block.timestamp > _params.deadline;
        return isSigner && !isExpired;
    }

    /// @notice external wrapper for _calculateBaseClaimableProjectTokens
    function calculateBaseClaimableProjectTokens(
        address _userKycAddress,
        address _projectTokenAddress,
        address _proxyWalletAddress,
        uint256 _investmentRoundId
    ) external view returns (uint256) {
        return
            _calculateBaseClaimableProjectTokens(
                _userKycAddress,
                _projectTokenAddress,
                _proxyWalletAddress,
                _investmentRoundId
            );
    }

    /// @notice external wrapper for _isSignatureValid
    function isSignatureValid(ClaimParams memory _params) external view returns (bool) {
        return _isSignatureValid(_params);
    }
}
