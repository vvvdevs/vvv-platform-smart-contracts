//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title VVV VC Investment Ledger
 * @notice This contract facilitates investments in VVV VC projects
 */
contract VVVVCInvestmentLedger is Ownable {
    using SafeERC20 for IERC20;

    /// @notice EIP-712 standard definitions
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256(
            bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        );
    bytes32 private constant INVESTMENT_TYPEHASH =
        keccak256(
            bytes("VCInvestment(bytes32 investmentRound,address kycAddress,uint256 investmentAmount)")
        );
    bytes32 private immutable DOMAIN_SEPARATOR;
    
    
    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice stores kyc address amounts invested for each investment round
    mapping(address => mapping(uint256 => uint256)) public kycAddressInvestedPerRound;
    
    /// @notice stores total amounts invested for each investment round
    mapping(uint256 => uint256) public totalInvestedPerRound;

    /**
     * @notice Struct for investment parameters
     * @param investmentRound The round of the investment
     * @param investmentRoundLimit The limit of the investment round
     * @param investmentRoundStartTimestamp The start timestamp of the investment round
     * @param investmentRoundEndTimestamp The end timestamp of the investment round
     * @param investmentCustodian The custodian of the investment
     * @param paymentTokenAddress The address of the payment token
     * @param kycAddress The address of the kyc address
     * @param kycAddressAllocation The max amount the kyc address can invest
     * @param amountToInvest The amount to invest
     * @param deadline The deadline for the investment
     * @param signature The signature of the investment
     */
    struct InvestParams {
        uint256 investmentRound;
        uint256 investmentRoundLimit;
        uint256 investmentRoundStartTimestamp;
        uint256 investmentRoundEndTimestamp;
        address investmentCustodian;
        address paymentTokenAddress;
        address kycAddress;
        uint256 kycAddressAllocation;
        uint256 amountToInvest;
        uint256 deadline;
        bytes signature;
    }

    /**
     * @notice Event emitted when a VC investment is made
     * @param investmentRound The round of the investment
     * @param kycAddress The address of the kyc address
     * @param investmentAmount The amount invested
     */
    event VCInvestment(
        uint256 indexed investmentRound,
        address indexed kycAddress,
        uint256 investmentAmount
    );

    /// @notice Error thrown when the caller is not a KYC address
    error CallerIsNotKYCAddress();

    /// @notice Error thrown when the caller or investment round allocation has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the investment round is inactive
    error InactiveInvestmentRound();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    /// @notice Error thrown when transferring ETH or ERC20 tokens fails
    error TransferFailed();

    /// @notice stores the signer address and initializes the EIP-712 domain separator
    constructor(address _signer) Ownable(msg.sender) {
        signer = _signer;

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("VVV VC Investment Ledger")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Facilitates a kyc address's investment in a project
     * @param p An InvestParams struct containing the investment parameters
     */
    function invest(InvestParams memory p) external {
        // check if signature is valid
        if (!_isSignatureValid(p)) {
            revert InvalidSignature();
        }

        // check if the investment round is active
        if (
            block.timestamp < p.investmentRoundStartTimestamp ||
            block.timestamp > p.investmentRoundEndTimestamp
        ) {
            revert InactiveInvestmentRound();
        }

        // store kyc address and total amounts invested for this investment round
        uint256 kycAddressInvestedThisRound = kycAddressInvestedPerRound[p.kycAddress][p.investmentRound];
        uint256 totalInvestedThisRound = totalInvestedPerRound[p.investmentRound];

        // check if kyc address has already invested the max amount for this round,
        // or if the total invested for this round has reached the limit
        if (
            p.amountToInvest > p.kycAddressAllocation - kycAddressInvestedThisRound ||
            p.amountToInvest > p.investmentRoundLimit - totalInvestedThisRound
        ) {
            revert ExceedsAllocation();
        }

        // update kyc address and total amounts invested for this investment round
        kycAddressInvestedPerRound[p.kycAddress][p.investmentRound] += p.amountToInvest;
        totalInvestedPerRound[p.investmentRound] += p.amountToInvest;

        // transfer tokens from msg.sender to investmentCustodian
        IERC20(p.paymentTokenAddress).safeTransferFrom(
            msg.sender,
            p.investmentCustodian,
            p.amountToInvest
        );

        // emit VCInvestment event
        emit VCInvestment(p.investmentRound, p.kycAddress, p.amountToInvest);
    }

    /**
     * @notice Checks if the provided signature is valid
     * @param p An InvestParams struct containing the investment parameters
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(InvestParams memory p) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        INVESTMENT_TYPEHASH,
                        p.investmentRound,
                        p.investmentRoundLimit,
                        p.investmentRoundStartTimestamp,
                        p.investmentRoundEndTimestamp,
                        p.investmentCustodian,
                        p.paymentTokenAddress,
                        p.kycAddress,
                        p.kycAddressAllocation,
                        p.deadline,
                        block.chainid
                    )
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, p.signature);
        return recoveredAddress == signer && recoveredAddress != address(0);
    }

    /// @notice external wrapper for _isSignatureValid
    function isSignatureValid(InvestParams memory p) external view returns (bool) {
        return _isSignatureValid(p);
    }

    /// @notice Allows admin to transfer ERC20 tokens from this contract
    function transferERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(_to, _amount);
    }

    /// @notice Allows admin to transfer ETH from this contract
    function transferETH(address payable _to, uint256 _amount) external onlyOwner {
        (bool os, ) = _to.call{ value: _amount }("");
        if (!os) {
            revert TransferFailed();
        }
    }
}
