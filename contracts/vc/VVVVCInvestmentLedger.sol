//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
import { IERC20WithDecimals } from "contracts/tokens/IERC20WithDecimals.sol";
import { VVVVCRewardToken } from "contracts/vc/VVVVCRewardToken.sol";

/**
 * @title VVV VC Investment Ledger
 * @notice This contract facilitates investments in VVV VC projects
 */
contract VVVVCInvestmentLedger is VVVAuthorizationRegistryChecker {
    using SafeERC20 for IERC20WithDecimals;

    /// @notice EIP-712 standard definitions
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
    bytes32 public constant INVESTMENT_TYPEHASH =
        keccak256(
            bytes(
                "InvestParams(uint256 investmentRound,uint256 investmentRoundLimit,uint256 investmentRoundStartTimestamp,uint256 investmentRoundEndTimestamp,address paymentTokenAddress,address kycAddress,uint256 kycAddressAllocation,uint256 exchangeRateNumerator,uint256 feeNumerator,uint256 deadline,address sender)"
            )
        );

    ///@notice the denominator used to apply a fee to invested tokens
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @notice The address authorized to sign investment transactions
    address public signer;

    /// @notice flag to pause investments
    bool public investmentIsPaused;

    /// @notice Environment tag used in the domain separator
    string public environmentTag;

    /// @notice Amount of decimals of the amounts stored in this contract
    uint8 public decimals = 18;

    /// @notice the denominator used to convert units of payment tokens to units of $STABLE (i.e. USDC/T)
    uint256 public immutable exchangeRateDenominator;

    /// @notice The reward token contract address
    VVVVCRewardToken public rewardToken;

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
     * @param feeNumerator The numerator of the fee subtracted from the investment stable-equivalent amount
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
        uint256 feeNumerator;
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
     * @param feeNumerator The numerator of the fee subtracted from the investment stable-equivalent amount
     * @param investmentAmount The amount invested in stablecoin terms
     * @param mintedTokenId The ID of the minted reward token (0 if no token was minted)
     */
    event VCInvestment(
        uint256 indexed investmentRound,
        address indexed paymentTokenAddress,
        address indexed kycAddress,
        uint256 exchangeRateNumerator,
        uint256 exchangeRateDenominator,
        uint256 feeNumerator,
        uint256 investmentAmount,
        uint8 paymentTokenDecimals,
        uint8 ledgerDecimals,
        uint256 mintedTokenId
    );

    /// @notice Error thrown when the input arrays do not have the same length
    error ArrayLengthMismatch();

    /// @notice Error thrown when the caller or investment round allocation has been exceeded
    error ExceedsAllocation();

    /// @notice Error thrown when the investment round is inactive
    error InactiveInvestmentRound();

    /// @notice Error thrown when the signer address is not recovered from the provided signature
    error InvalidSignature();

    /// @notice Error thrown when an attempt to invest is made while investment is paused
    error InvestmentPaused();

    /// @notice Error thrown when the number of payment token decimals exceeds the number of decimals used by the ledger
    error UnsupportedPaymentTokenDecimals();

    /// @notice Error thrown when reward token contract is not set
    error RewardTokenNotSet();

    /**
        @notice stores the signer address and initializes the EIP-712 domain separator
        @param _signer The address authorized to sign investment transactions
        @param _environmentTag The environment tag for the EIP-712 domain separator
        @param _authorizationRegistryAddress The address of the authorization registry
        @param _exchangeRateDenominator The denominator used to convert units of payment tokens to units of $STABLE
     */
    constructor(
        address _signer,
        string memory _environmentTag,
        address _authorizationRegistryAddress,
        uint256 _exchangeRateDenominator
    ) VVVAuthorizationRegistryChecker(_authorizationRegistryAddress) {
        signer = _signer;
        environmentTag = _environmentTag;
        exchangeRateDenominator = _exchangeRateDenominator;
    }

    /**
     * @notice Public function to invest without minting a reward token
     * @notice Facilitates a kyc address's investment in a project
     * @param _params An InvestParams struct containing the investment parameters
     */
    function invest(InvestParams memory _params) external {
        _invest(_params);
        emit VCInvestment(
            _params.investmentRound,
            _params.paymentTokenAddress,
            _params.kycAddress,
            _params.exchangeRateNumerator,
            exchangeRateDenominator,
            _params.feeNumerator,
            _calculatePostFeeStableAmountEquivalent(_params),
            IERC20WithDecimals(_params.paymentTokenAddress).decimals(),
            decimals,
            0 // No reward token minted
        );
    }

    /**
     * @notice Public function to invest and mint a reward token
     * @param _params An InvestParams struct containing the investment parameters
     */
    function getRewardToken(InvestParams memory _params) external {
        _invest(_params);
        if (address(rewardToken) == address(0)) {
            revert RewardTokenNotSet();
        }
        rewardToken.mint(msg.sender, _params.investmentRound);
        uint256 mintedTokenId = rewardToken.currentTokenId();
        emit VCInvestment(
            _params.investmentRound,
            _params.paymentTokenAddress,
            _params.kycAddress,
            _params.exchangeRateNumerator,
            exchangeRateDenominator,
            _params.feeNumerator,
            _calculatePostFeeStableAmountEquivalent(_params),
            IERC20WithDecimals(_params.paymentTokenAddress).decimals(),
            decimals,
            mintedTokenId
        );
    }

    /**
     * @notice Internal function to facilitate a kyc address's investment in a project
     * @param _params An InvestParams struct containing the investment parameters
     */
    function _invest(InvestParams memory _params) internal {
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

        uint8 paymentTokenDecimals = IERC20WithDecimals(_params.paymentTokenAddress).decimals();
        if (decimals < paymentTokenDecimals) {
            revert UnsupportedPaymentTokenDecimals();
        }

        uint8 decimalDifference = decimals - paymentTokenDecimals;

        // the stablecoin amount equivalent to the payment token amount supplied at the current exchange rate
        uint256 preFeeStableAmountEquivalent = ((_params.amountToInvest * _params.exchangeRateNumerator) /
            exchangeRateDenominator) * 10 ** decimalDifference;

        // the post-fee stableAmountEquivalent, to contribute toward user and round limits
        uint256 postFeeStableAmountEquivalent = preFeeStableAmountEquivalent -
            (preFeeStableAmountEquivalent * _params.feeNumerator + FEE_DENOMINATOR - 1) /
            FEE_DENOMINATOR;

        // check if kyc address has already invested the max stablecoin-equivalent amount for this round,
        // or if the total invested for this round has reached the limit
        if (
            postFeeStableAmountEquivalent > _params.kycAddressAllocation - kycAddressInvestedThisRound ||
            postFeeStableAmountEquivalent > _params.investmentRoundLimit - totalInvestedThisRound
        ) {
            revert ExceedsAllocation();
        }

        // update kyc address and total amounts invested for this investment round (in stablecoin terms)
        kycAddressInvestedPerRound[_params.kycAddress][
            _params.investmentRound
        ] += postFeeStableAmountEquivalent;
        totalInvestedPerRound[_params.investmentRound] += postFeeStableAmountEquivalent;

        // transfer tokens from msg.sender to this contract (in payment token terms)
        IERC20WithDecimals(_params.paymentTokenAddress).safeTransferFrom(
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
            _params.feeNumerator,
            postFeeStableAmountEquivalent,
            paymentTokenDecimals,
            decimals
        );
    }

    function _calculatePostFeeStableAmountEquivalent(
        InvestParams memory _params
    ) internal view returns (uint256) {
        uint8 paymentTokenDecimals = IERC20WithDecimals(_params.paymentTokenAddress).decimals();
        uint8 decimalDifference = decimals - paymentTokenDecimals;
        uint256 preFeeStableAmountEquivalent = ((_params.amountToInvest * _params.exchangeRateNumerator) /
            exchangeRateDenominator) * 10 ** decimalDifference;
        return
            preFeeStableAmountEquivalent -
            (preFeeStableAmountEquivalent * _params.feeNumerator + FEE_DENOMINATOR - 1) /
            FEE_DENOMINATOR;
    }

    /// @notice computes DOMAIN_SEPARATOR for investment transactions
    function _computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(abi.encodePacked("VVV", environmentTag)),
                    block.chainid,
                    address(this)
                )
            );
    }

    /// @notice external wrapper for _computeDomainSeparator
    function computeDomainSeparator() external view returns (bytes32) {
        return _computeDomainSeparator();
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
                _computeDomainSeparator(),
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
                        _params.feeNumerator,
                        _params.deadline,
                        msg.sender
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
        IERC20WithDecimals(_tokenAddress).safeTransfer(_to, _amount);
    }

    /**
        @notice Allows admin to add multiple investment records to the ledger
        @dev does not account for a nominal payment token / exchange rate - only modifies stablecoin equivalent invested
     */
    function addInvestmentRecords(
        address[] calldata _kycAddresses,
        uint256[] calldata _investmentRounds,
        uint256[] calldata _amountsToInvest
    ) external onlyAuthorized {
        if (
            _kycAddresses.length != _investmentRounds.length ||
            _investmentRounds.length != _amountsToInvest.length
        ) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _kycAddresses.length; i++) {
            address kycAddress = _kycAddresses[i];
            uint256 investmentRound = _investmentRounds[i];
            uint256 amountToInvest = _amountsToInvest[i];

            kycAddressInvestedPerRound[kycAddress][investmentRound] += amountToInvest;
            totalInvestedPerRound[investmentRound] += amountToInvest;
            emit VCInvestment(
                investmentRound,
                address(0),
                kycAddress,
                0,
                0,
                0,
                amountToInvest,
                decimals,
                decimals,
                0
            );
        }
    }

    /// @notice admin function to pause investment
    function setInvestmentIsPaused(bool _isPaused) external onlyAuthorized {
        investmentIsPaused = _isPaused;
    }

    /// @notice admin function to set decimals value
    function setDecimals(uint8 _decimals) external onlyAuthorized {
        decimals = _decimals;
    }

    /// @notice admin function to set reward token contract
    function setRewardToken(address _rewardToken) external onlyAuthorized {
        rewardToken = VVVVCRewardToken(_rewardToken);
    }
}
