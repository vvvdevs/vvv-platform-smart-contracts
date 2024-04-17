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
            bytes(
                "InvestParams(uint256 investmentRound,uint256 investmentRoundLimit,uint256 investmentRoundStartTimestamp,uint256 investmentRoundEndTimestamp,address paymentTokenAddress,address kycAddress,uint256 kycAddressAllocation,uint256 amountToInvest,uint256 exchangeRateNumerator,uint256 deadline)"
            )
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice flag to pause investments
    bool public investmentIsPaused;

    /// @notice the denominator used to convert units of payment tokens to units of $STABLE (i.e. USDC/T)
    uint256 public exchangeRateDenominator = 1e6;

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
     * @param amountToInvest The amount of paymentToken to invest
     * @param exchangeRateNumerator The numerator of the conversion of payment token to stablecoin (i.e. VVV to USDC)
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
        uint256 exchangeRateNumerator;
        uint256 deadline;
        bytes signature;
    }

    /**
     * @notice Event emitted when a VC investment is made
     * @param investmentRound The round of the investment
     * @param paymentTokenAddress The address of the payment token
     * @param kycAddress The address of the kyc address
     * @param exchangeRateNumerator The numerator of the conversion of payment token to stablecoin
     * @param exchangeRateDenominator The denominator of the conversion of payment token to stablecoin
     * @param investmentAmount The amount invested in stablecoin terms
     */
    event VCInvestment(
        uint256 indexed investmentRound,
        address indexed paymentTokenAddress,
        address indexed kycAddress,
        uint256 exchangeRateNumerator,
        uint256 exchangeRateDenominator,
        uint256 investmentAmount
    );

    /**
     * @notice Event emitted when a VC investment is refunded
     * @param userKycAddress The kyc address of the user to refund
     * @param tokenDestination The address to which to send the refund token
     * @param investmentRound The round of the investment to refund
     * @param refundTokenAddress The address of the token to refund
     * @param refundTokenAmount The amount of the token to refund
     * @param stablecoinEquivalent The equivalent amount of stablecoin to the token amount refunded
     */
    event VCRefund(
        address userKycAddress,
        address tokenDestination,
        uint256 investmentRound,
        address refundTokenAddress,
        uint256 refundTokenAmount,
        uint256 stablecoinEquivalent
    );

    /// @notice Error thrown when the caller or investment round allocation has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the investment round is inactive
    error InactiveInvestmentRound();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    /// @notice Error thrown when an attempt to invest is made while investment is paused
    error InvestmentPaused();

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
        //check if investments are paused
        if (investmentIsPaused) revert InvestmentPaused();

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

        //the stablecoin amount equivalent to the payment token amount supplied at the current exchange rate
        uint256 stableAmountEquivalent = (_params.amountToInvest * _params.exchangeRateNumerator) /
            exchangeRateDenominator;

        // check if kyc address has already invested the max stablecoin-equivalent amount for this round,
        // or if the total invested for this round has reached the limit
        if (
            stableAmountEquivalent > _params.kycAddressAllocation - kycAddressInvestedThisRound ||
            stableAmountEquivalent > _params.investmentRoundLimit - totalInvestedThisRound
        ) {
            revert ExceedsAllocation();
        }

        // update kyc address and total amounts invested for this investment round (in stablecoin terms)
        kycAddressInvestedPerRound[_params.kycAddress][_params.investmentRound] += stableAmountEquivalent;
        totalInvestedPerRound[_params.investmentRound] += stableAmountEquivalent;

        // transfer tokens from msg.sender to this contract (in payment token terms)
        IERC20(_params.paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _params.amountToInvest
        );

        // emit VCInvestment event (in stablecoin terms)
        emit VCInvestment(
            _params.investmentRound,
            _params.paymentTokenAddress,
            _params.kycAddress,
            _params.exchangeRateNumerator,
            exchangeRateDenominator,
            stableAmountEquivalent
        );
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
                        _params.exchangeRateNumerator,
                        _params.deadline
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

    /** 
        @notice Allows admin to add an investment record to the ledger
        @dev does not account for a nominal payment token / exchange rate - only modifies stablecoin equivalent invested
     */
    function addInvestmentRecord(
        address _kycAddress,
        uint256 _investmentRound,
        uint256 _amountToInvest
    ) external onlyAuthorized {
        kycAddressInvestedPerRound[_kycAddress][_investmentRound] += _amountToInvest;
        totalInvestedPerRound[_investmentRound] += _amountToInvest;
        emit VCInvestment(_investmentRound, address(0), _kycAddress, 0, 0, _amountToInvest);
    }

    ///@notice Allows admin to set the exchange rate denominator
    function setExchangeRateDenominator(uint256 _exchangeRateDenominator) external onlyAuthorized {
        exchangeRateDenominator = _exchangeRateDenominator;
    }

    /**
        @notice refunds a user's investment in units of the specified ERC20 token
        @dev ex. to refund user 1 $VVV which was invested at $10 per VVV, _refundTokenAmount = 1, _stablecoinEquivalent = 10
        @dev allows erasing manually added investment records
     */
    function refundUserInvestment(
        address _userKycAddress,
        address _tokenDestination,
        uint256 _investmentRound,
        address _refundTokenAddress,
        uint256 _refundTokenAmount,
        uint256 _stablecoinEquivalent
    ) external onlyAuthorized {
        kycAddressInvestedPerRound[_userKycAddress][_investmentRound] -= _stablecoinEquivalent;
        totalInvestedPerRound[_investmentRound] -= _stablecoinEquivalent;

        IERC20(_refundTokenAddress).safeTransfer(_tokenDestination, _refundTokenAmount);

        emit VCRefund(
            _userKycAddress,
            _tokenDestination,
            _investmentRound,
            _refundTokenAddress,
            _refundTokenAmount,
            _stablecoinEquivalent
        );
    }

    /// @notice admin function to pause investment
    function setInvestmentIsPaused(bool _isPaused) external onlyAuthorized {
        investmentIsPaused = _isPaused;
    }
}
