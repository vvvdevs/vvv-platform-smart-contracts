//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
                "VCClaim(address userKycAddress, address callerAddress, address projectTokenAddress, address[] projectTokenClaimFromWallets, uint256 claimedTokenAmount)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice Mapping of user's KYC address to project token address to user's claimed amount
    mapping(address => mapping(address => uint256)) public userClaimedTokensForToken;

    /// @notice Mapping of the round ID to the token's total claimed amount
    mapping(address => uint256) public totalClaimedTokensForToken;

    /**
        @notice Parameters for claim function
        @param callerAddress Address of the caller (alias for KYC address)
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallets Array of addresses of the wallets from which the project token is to be claimed
        @param investmentRoundIds Array of ledger investment round ids involved in the claim
        @param tokenAmountToClaim Total (combined across all rounds) amount of project tokens to claim
        @param deadline Deadline for signature validity
        @param signature Signature of the user's KYC wallet address
     */
    struct ClaimParams {
        address callerAddress;
        address userKycAddress;
        address projectTokenAddress;
        address[] projectTokenClaimFromWallets;
        uint256[] investmentRoundIds;
        uint256 tokenAmountToClaim;
        uint256 deadline;
        bytes signature;
    }

    /**
        @notice Emitted when a user claims tokens
        @param userKycAddress Address of the user's KYC wallet
        @param callerAddress Address of the caller (alias for KYC address)
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallets Addresses of the wallets from which the project token is to be claimed
        @param claimedTokenAmount Total amount of project tokens claimed
     */
    event VCClaim(
        address indexed userKycAddress,
        address indexed callerAddress,
        address indexed projectTokenAddress,
        address[] projectTokenClaimFromWallets,
        uint256 claimedTokenAmount
    );

    /// @notice Error thrown when the caller's allocation or proxy wallet balance has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when pool of wallets that holds project token does not have balance to fulfill claim
    error InsufficientPoolBalance();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    constructor(address _signer, address _ledger, string memory _environmentTag) Ownable(msg.sender) {
        signer = _signer;
        ledger = IVVVVCInvestmentLedger(_ledger);

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
        @param _params A ClaimParams struct describing the desired claim(s)
     */
    function claim(ClaimParams memory _params) public {
        //ensure caller (msg.sender) is an alias of the KYC address
        _params.callerAddress = msg.sender;

        if (!_isSignatureValid(_params)) {
            revert InvalidSignature();
        }

        IERC20 projectToken = IERC20(_params.projectTokenAddress);

        //check claimable amount for pool of wallets that all hold project token
        uint256 userClaimableBase = _calculateBaseClaimableProjectTokens(
            _params.userKycAddress,
            _params.projectTokenAddress,
            _params.projectTokenClaimFromWallets,
            _params.investmentRoundIds
        );
        uint256 userClaimable = userClaimableBase -
            userClaimedTokensForToken[_params.userKycAddress][_params.projectTokenAddress];

        if (_params.tokenAmountToClaim > userClaimable) {
            revert ExceedsAllocation();
        }

        userClaimedTokensForToken[_params.userKycAddress][_params.projectTokenAddress] += _params
            .tokenAmountToClaim;
        totalClaimedTokensForToken[_params.projectTokenAddress] += _params.tokenAmountToClaim;

        //transfer to caller starting with attempting full amount with the first
        //wallet, carrying remainder to the next wallets if needed
        uint256 remainingAmountToClaim = _params.tokenAmountToClaim;
        for (uint256 i = 0; i < _params.projectTokenClaimFromWallets.length; i++) {
            uint256 amountToClaim = remainingAmountToClaim;
            if (amountToClaim > projectToken.balanceOf(_params.projectTokenClaimFromWallets[i])) {
                amountToClaim = projectToken.balanceOf(_params.projectTokenClaimFromWallets[i]);
            }
            remainingAmountToClaim -= amountToClaim;
            projectToken.safeTransferFrom(
                _params.projectTokenClaimFromWallets[i],
                _params.callerAddress,
                amountToClaim
            );
            if (remainingAmountToClaim == 0) {
                break;
            }
        }

        //if full amount isn't available from the wallets, revert
        if (remainingAmountToClaim != 0) {
            revert InsufficientPoolBalance();
        }

        emit VCClaim(
            _params.userKycAddress,
            _params.callerAddress,
            _params.projectTokenAddress,
            _params.projectTokenClaimFromWallets,
            _params.tokenAmountToClaim
        );
    }

    /**
        @notice Reads the VVVVCInvestmentLedger contract to calculate the base claimable token amount, which does not consider the amount already claimed by the KYC address
        @dev uses fraction of invested funds to determine fraction of claimable tokens
        @dev applies to all wallets/rounds containing the project token
        @param _userKycAddress Address of the user's KYC wallet
        @param _projectTokenAddress Address of the project token to be claimed
        @param _proxyWalletAddresses Address array of the wallets from which the project token is to be claimed
        @param _investmentRoundIds Array of investment round IDs for which to calculate claimable tokens
     */
    function _calculateBaseClaimableProjectTokens(
        address _userKycAddress,
        address _projectTokenAddress,
        address[] memory _proxyWalletAddresses,
        uint256[] memory _investmentRoundIds
    ) internal view returns (uint256) {
        uint256 totalInvestedPaymentTokens;
        uint256 userInvestedPaymentTokens;
        uint256 totalProjectTokenBalanceAllWallets;

        for (uint256 i = 0; i < _investmentRoundIds.length; i++) {
            totalInvestedPaymentTokens += ledger.totalInvestedPerRound(_investmentRoundIds[i]);
            userInvestedPaymentTokens += ledger.kycAddressInvestedPerRound(
                _userKycAddress,
                _investmentRoundIds[i]
            );
            totalProjectTokenBalanceAllWallets += IERC20(_projectTokenAddress).balanceOf(
                _proxyWalletAddresses[i]
            );
        }

        if (userInvestedPaymentTokens == 0) return 0;

        //total pool of claimable tokens is balance of proxy wallets + total claimed for this token address
        uint256 totalProjectTokensDepositedToProxyWallet = totalProjectTokenBalanceAllWallets +
            totalClaimedTokensForToken[_projectTokenAddress];

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
        address[] memory _proxyWalletAddresses,
        uint256[] memory _investmentRoundIds
    ) external view returns (uint256) {
        return
            _calculateBaseClaimableProjectTokens(
                _userKycAddress,
                _projectTokenAddress,
                _proxyWalletAddresses,
                _investmentRoundIds
            );
    }

    /// @notice external wrapper for _isSignatureValid
    function isSignatureValid(ClaimParams memory _params) external view returns (bool) {
        return _isSignatureValid(_params);
    }
}
