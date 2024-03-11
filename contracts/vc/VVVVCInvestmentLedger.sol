//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
/**
 * @title VVV VC Investment Ledger
 * @notice This contract facilitates investments in VVV VC projects
 */
contract VVVVCInvestmentLedger is VVVAuthorizationRegistryChecker {
    using SafeERC20 for IERC20;

    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant INVESTMENT_TYPEHASH =
        keccak256(
            bytes("VCInvestment(uint256 investmentRound,address kycAddress,uint256 investmentAmount)")
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

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

    /// @notice Error thrown when the caller or investment round allocation has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the investment round is inactive
    error InactiveInvestmentRound();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    /**
        @notice stores the signer address and initializes the EIP-712 domain separator
        @param _signer The address authorized to sign investment transactions
        @param _environmentTag The environment tag for the EIP-712 domain separator
     */
    constructor(
        address _signer,
        string memory _environmentTag,
        address _authorizationRegistryAddress
    ) VVVAuthorizationRegistryChecker(_authorizationRegistryAddress) {
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
     * @notice Facilitates a kyc address's investment in a project
     * @param _params An InvestParams struct containing the investment parameters
     */
    function invest(InvestParams memory _params) external {
        // check if signature is valid
        if (!_isSignatureValid(_params)) {
            revert InvalidSignature();
        }

        // check if the investment round is active
        if (
            block.timestamp < _params.investmentRoundStartTimestamp ||
            block.timestamp > _params.investmentRoundEndTimestamp
        ) {
            revert InactiveInvestmentRound();
        }

        // store kyc address and total amounts invested for this investment round
        uint256 kycAddressInvestedThisRound = kycAddressInvestedPerRound[_params.kycAddress][
            _params.investmentRound
        ];
        uint256 totalInvestedThisRound = totalInvestedPerRound[_params.investmentRound];

        // check if kyc address has already invested the max amount for this round,
        // or if the total invested for this round has reached the limit
        if (
            _params.amountToInvest > _params.kycAddressAllocation - kycAddressInvestedThisRound ||
            _params.amountToInvest > _params.investmentRoundLimit - totalInvestedThisRound
        ) {
            revert ExceedsAllocation();
        }

        // update kyc address and total amounts invested for this investment round
        kycAddressInvestedPerRound[_params.kycAddress][_params.investmentRound] += _params.amountToInvest;
        totalInvestedPerRound[_params.investmentRound] += _params.amountToInvest;

        // transfer tokens from msg.sender to this contract
        IERC20(_params.paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _params.amountToInvest
        );

        // emit VCInvestment event
        emit VCInvestment(_params.investmentRound, _params.kycAddress, _params.amountToInvest);
    }

    /**
     * @notice Checks if the provided signature is valid
     * @param _params An InvestParams struct containing the investment parameters
     * @return true if the signer address is recovered from the signature, false otherwise
     */
    function _isSignatureValid(InvestParams memory _params) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        INVESTMENT_TYPEHASH,
                        _params.investmentRound,
                        _params.investmentRoundLimit,
                        _params.investmentRoundStartTimestamp,
                        _params.investmentRoundEndTimestamp,
                        _params.paymentTokenAddress,
                        _params.kycAddress,
                        _params.kycAddressAllocation,
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

    /// @notice external wrapper for _isSignatureValid
    function isSignatureValid(InvestParams memory _params) external view returns (bool) {
        return _isSignatureValid(_params);
    }

    /// @notice Allows admin to withdraw ERC20 tokens from this contract
    function withdraw(address _tokenAddress, address _to, uint256 _amount) external onlyAuthorized {
        IERC20(_tokenAddress).safeTransfer(_to, _amount);
    }

    ///@notice Allows admin to add an investment record to the ledger
    function addInvestmentRecord(
        address _kycAddress,
        uint256 _investmentRound,
        uint256 _amountToInvest
    ) external onlyAuthorized {
        kycAddressInvestedPerRound[_kycAddress][_investmentRound] += _amountToInvest;
        totalInvestedPerRound[_investmentRound] += _amountToInvest;
        emit VCInvestment(_investmentRound, _kycAddress, _amountToInvest);
    }
}
