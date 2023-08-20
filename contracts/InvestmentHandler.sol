//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title InvestmentHandler
 * @author @vvvfund (@curi0n-s + @c0dejax + @kcper), audits by @marko1010, and [eventual audit firm/site(s)]
 * @notice Handles the investment process for vVv allocations' investments and claims
 *
 * @dev Assumptions:
 * 1. Project tokens deposited to this contract cannot be rebasing tokens/balances must remain static to ensure fair distribution of tokens to users regardless of time and frequency of token claims
 */

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PausableSelective } from "@uintgroup/pausable-selective/src/PausableSelective.sol";

contract InvestmentHandler is AccessControl, ReentrancyGuard, PausableSelective {
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // STORAGE & SETUP
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    using SafeERC20 for IERC20;

    /// @dev role for adding and modifying investment data
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant ADD_CONTRIBUTION_ROLE = keccak256("ADD_CONTRIBUTION_ROLE");
    bytes32 private constant INVESTMENT_MANAGER_ROLE = keccak256("ADD_INVESTMENT_ROLE");
    bytes32 private constant PAYMENT_TOKEN_TRANSFER_ROLE = keccak256("PAYMENT_TOKEN_TRANSFER_ROLE");
    bytes32 private constant REFUNDER_ROLE = keccak256("REFUNDER_ROLE");

    /// @dev global tracker for latest investment id
    uint16 public latestInvestmentId;

    /**
     * @notice Investment struct
     * @param signer address of the signer for this investment
     * @param contributionPhase phase index (0 = closed, 1 = whales, etc.)
     * @param projectToken address of the project token
     * @param paymentToken address of the payment token
     * @param totalInvestedPaymentToken total amount of payment token invested in this investment
     * @param totalAllocatedPaymentToken total amount of payment token allocated to this investment
     * @param totalTokensClaimed total amount of project token claimed from this investment
     * @param totalTokensAllocated total amount of project token allocated to this investment
     */
    struct Investment {
        address signer;
        IERC20 projectToken;
        IERC20 paymentToken;
        uint8 contributionPhase;
        uint128 totalInvestedPaymentToken;
        uint128 totalAllocatedPaymentToken;
        uint256 totalTokensClaimed;
        uint256 totalTokensAllocated;
    }

    /**
     * @dev struct for a single user's activity for one investment
     * @param totalInvestedPaymentToken total amount of payment token invested by user in this investment
     * @param pledgeDebt = pledgedAmount - totalInvestedPaymentToken for this investment
     * @param totalTokensClaimed total amount of project token claimed by user from this investment
     */
    struct UserInvestment {
        uint128 totalInvestedPaymentToken;
        uint128 pledgeDebt;
        uint256 totalTokensClaimed;
    }

    /**
     * @dev struct for the parameters for each claim
     * @param investmentId id of the investment
     * @param claimAmount amount of project token the user is claiming in this transaction
     * @param tokenRecipient address of the user's in-network kyc'd address
     * @param kycAddress address of the user's in-network kyc'd address
     */
    struct ClaimParams {
        uint16 investmentId;
        uint240 claimAmount;
        address tokenRecipient;
        address kycAddress;
    }

    /**
     * @dev struct for the parameters for each investment
     * @param investmentId id of the investment
     * @param maxInvestableAmount max amount of payment token the user can invest in this investment
     * @param thisInvestmentAmount amount of payment token the user is investing in this transaction
     * @param userPhase phase the user is investing in
     * @param kycAddress address of the user's in-network kyc'd address
     * @param signature signature of the user's kyc'd address
     */
    struct InvestParams {
        uint16 investmentId;
        uint120 thisInvestmentAmount;
        uint120 maxInvestableAmount;
        uint8 userPhase;
        address kycAddress;
        bytes signature;
    }

    /// @notice investmentId => investment
    mapping(uint256 => Investment) public investments;

    /// @notice user => investmentId => userInvestment
    mapping(address => mapping(uint256 => UserInvestment)) public userInvestments;
    mapping(address => uint256[]) public userInvestmentIds;

    /// @notice kyc address => in-network address => bool
    mapping(address => mapping(address => bool)) public isInKycAddressNetwork;
    mapping(address => address) public correspondingKycAddress;

    /// @dev signer address => bool, checks whether address has already been used as an investment's signer
    mapping(address => bool) public isSigner;

    // Events
    event ERC20Recovered(
        address indexed sender,
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event FunctionIsPausedUpdate(bytes4 indexed functionId, bool indexed isPaused);
    event InvestmentAdded(uint256 indexed investmentId);
    event InvestmentPaymentTokenAddressSet(uint256 indexed investmentId, address indexed paymentToken);
    event InvestmentPhaseSet(uint256 indexed investmentId, uint256 indexed phase);
    event InvestmentProjectTokenAddressSet(uint256 indexed investmentId, address indexed projectToken);
    event InvestmentProjectTokenAllocationSet(uint256 indexed investmentId, uint256 indexed amount);
    event UserInvestmentContribution(
        address indexed sender,
        address indexed kycAddress,
        uint256 indexed investmentId,
        uint256 amount
    );
    event UserInvestmentTransfer(
        address sender,
        address indexed oldKycAddress,
        address indexed newKycAddress,
        uint256 indexed investmentId,
        uint256 amount
    );
    event UserTokenClaim(
        address indexed sender,
        address tokenRecipient,
        address indexed kycAddress,
        uint256 indexed investmentId,
        uint256 amount
    );
    event UserRefunded(
        address indexed sender,
        address indexed kycAddress,
        uint256 indexed investmentId,
        uint256 amount
    );
    event AddressAddedToKycAddressNetwork(address indexed kycAddress, address indexed addedAddress);
    event AddressRemovedFromKycAddressNetwork(address indexed kycAddress, address indexed removedAddress);
    event PaymentTokenTransferred(
        address indexed sender,
        uint256 indexed investmentId,
        address indexed recipient,
        uint256 amount
    );

    // Errors
    error AddressAlreadyInKycNetwork();
    error AddressNotInKycNetwork();
    error ArrayLengthMismatch();
    error CantClaimZero();
    error CantInvestZero();
    error CantRefundZero();
    error CantTransferZero();
    error ClaimAmountExceedsTotalClaimable();
    error ERC20AmountExceedsBalance();
    error InvalidSignature();
    error InsufficientAllowance();
    error InvestmentAmountExceedsMax();
    error InvestmentDoesNotExist();
    error InvestmentIsNotOpen();
    error InvestmentTokenAlreadyDeposited();
    error NotInKycAddressNetwork();
    error NotKycAddress();
    error RefundAmountExceedsUserBalance();
    error SignerAlreadyUsed();
    error TooLateForRefund();
    error TransferAmountExceedsInvestmentBalance();
    error UserAlreadyClaimedTokens();

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INITIALIZATION & MODIFIERS
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /// @dev constructor handles role setup
    constructor(
        address _defaultAdminController,
        address _pauser,
        address _investmentManager,
        address _contributionAndRefundManager,
        address _refunder
    ) {
        //Deployer is default admin while setting up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdminController);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(INVESTMENT_MANAGER_ROLE, _investmentManager);
        _grantRole(ADD_CONTRIBUTION_ROLE, _contributionAndRefundManager);
        _grantRole(REFUNDER_ROLE, _refunder);
        _grantRole(PAYMENT_TOKEN_TRANSFER_ROLE, _investmentManager);

        //Pauses admin functions that should be unpaused to use for security
        defaultPauseConfig();

        //Deployer renounces default admin role
        _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev called from constructor to set default paused functions for security
    function defaultPauseConfig() private {
        _setFunctionIsPaused(this.manualAddContribution.selector, true);
        _setFunctionIsPaused(this.refundUser.selector, true);
        _setFunctionIsPaused(this.transferPaymentToken.selector, true);
        _setFunctionIsPaused(this.recoverERC20.selector, true);
    }

    /**
     * @dev modifier to check addresses involved in claim
     * @dev msg.sender and _params.tokenRecipient must be in network of _kycAddress
     */
    modifier claimChecks(
        ClaimParams memory _params
    ) {
        uint256 claimableTokens = computeUserClaimableAllocationForInvestment(_params.kycAddress, _params.investmentId);

        //function requirements
        if (_params.claimAmount == 0) {
            revert CantClaimZero();
        }

        if (_params.claimAmount > claimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        if (
            (
                !isInKycAddressNetwork[_params.kycAddress][_params.tokenRecipient] && 
                _params.tokenRecipient != _params.kycAddress
            ) 
            ||
            (
                !isInKycAddressNetwork[_params.kycAddress][msg.sender] && 
                msg.sender != _params.kycAddress
            )
        ) {
            revert NotInKycAddressNetwork();
        }

        _;
    }

    /**
     * @dev checks to make sure user is able to investment the amount, at this time
     *      1. investment phase is open
     *      2. signature validates user max investable amount and address
     *      3. user has approved spending of the investment amount in the desired paymentToken
     *      4. user investment amount + current proposed investment amount is less than max investable amount
     */
    modifier investChecks(InvestParams memory _params) {
        // function requirements
        if (!_signatureCheck(_params)) {
            revert InvalidSignature();
        } else if (!_phaseCheck(_params)) {
            revert InvestmentIsNotOpen();
        } else if (_params.thisInvestmentAmount == 0) {
            revert CantInvestZero();
        } else if (!_paymentTokenAllowanceCheck(_params)) {
            revert InsufficientAllowance();
        } else if (!_contributionLimitCheck(_params)) {
            revert InvestmentAmountExceedsMax();
        }

        _;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // USER WRITE FUNCTIONS (INVEST, CLAIM)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * @notice this function will be called by the user to claim their tokens
     * @notice allows any in-network address to claim tokens to any address on behalf of the kyc address
     * @notice UI can grab _kycAddress via correspondingKycAddress[msg.sender]
     * @notice both msg.sender and _tokenRecipient must be in network of _kycAddress, and msg.sender can be the same as _tokenRecipient
     * @param _params is a ClaimParams struct containing the parameters for the claim
     */
    function claim(
        ClaimParams memory _params
    )
        external
        nonReentrant
        whenNotPausedSelective(false)
        claimChecks(_params)
    {
        UserInvestment storage userInvestment = userInvestments[_params.kycAddress][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];

        userInvestment.totalTokensClaimed += _params.claimAmount;
        investment.totalTokensClaimed += _params.claimAmount;

        investment.projectToken.safeTransfer(_params.tokenRecipient, _params.claimAmount);

        emit UserTokenClaim(msg.sender, _params.tokenRecipient, _params.kycAddress, _params.investmentId, _params.claimAmount);
    }

    /**
     * @notice this function will be called by the user to invest in the project
     * @param _params the parameters for the investment as specified in InvestParams
     * @notice adds to users total usd invested for investment + total usd in investment overall
     * @notice adjusts user's pledge debt (pledged - contributed)
     */
    function invest(
        InvestParams memory _params
    ) external nonReentrant whenNotPausedSelective(false) investChecks(_params) {
        UserInvestment storage userInvestment = userInvestments[_params.kycAddress][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];

        investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        userInvestment.totalInvestedPaymentToken += uint128(_params.thisInvestmentAmount);
        userInvestment.pledgeDebt = uint128(
            _params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken
        );

        userInvestmentIds[_params.kycAddress].push(_params.investmentId);
        investment.paymentToken.safeTransferFrom(msg.sender, address(this), _params.thisInvestmentAmount);

        emit UserInvestmentContribution(
            msg.sender,
            _params.kycAddress,
            _params.investmentId,
            _params.thisInvestmentAmount
        );
    }

    /**
     * @notice this function will be called by a kyc'd address to add a address to its network
     * @notice allows any address to add any other address to its network, but this is only is of use to addresss who are kyc'd and able to invest/claim
     * @param _newAddress the address of the address to be added to the network
     */
    function addAddressToKycAddressNetwork(
        address _newAddress
    ) external nonReentrant whenNotPausedSelective(false) {
        if (correspondingKycAddress[_newAddress] != address(0)) {
            revert AddressAlreadyInKycNetwork();
        }

        isInKycAddressNetwork[msg.sender][_newAddress] = true;
        correspondingKycAddress[_newAddress] = msg.sender;

        emit AddressAddedToKycAddressNetwork(msg.sender, _newAddress);
    }

    /**
     * @notice this function will be called by a kyc'd address to remove a address from its network
     * @notice allows any address to remove any other address from its network, but this is only is of use to addresss who are kyc'd and able to invest/claim
     * @param _networkAddress the address of the address to be removed from the network, must be in the network of the calling kyc address
     */
    function removeAddressFromKycAddressNetwork(
        address _networkAddress
    ) external nonReentrant whenNotPausedSelective(false) {
        if (correspondingKycAddress[_networkAddress] != msg.sender) {
            revert AddressNotInKycNetwork();
        }

        isInKycAddressNetwork[msg.sender][_networkAddress] = false;
        delete correspondingKycAddress[_networkAddress];

        emit AddressRemovedFromKycAddressNetwork(msg.sender, _networkAddress);
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // USER READ FUNCTIONS (USER INVESTMENTS, USER CLAIMABLE ALLOCATION, USER TOTAL ALLOCATION)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * @dev returns user's total invested payment token for an investment
     */
    function getTotalInvestedForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) external view returns (uint256) {
        return userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken;
    }

    /**
     * @dev returns user's total claimed project tokens for an investment
     */
    function getTotalClaimedForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) external view returns (uint256) {
        return userInvestments[_kycAddress][_investmentId].totalTokensClaimed;
    }

    /**
     * @dev for frontend - returns the total amount of project tokens a user can claim for an investment
     */
    function computeUserTotalAllocationForInvesment(
        address _kycAddress,
        uint16 _investmentId
    ) external view returns (uint256) {
        UserInvestment storage userInvestment = userInvestments[_kycAddress][_investmentId];
        Investment storage investment = investments[_investmentId];

        uint256 totalInvestedPaymentToken = investment.totalInvestedPaymentToken;
        if (totalInvestedPaymentToken == 0) return 0;

        uint256 totalTokenAllocated = investment.totalTokensAllocated;
        uint256 userTotalInvestedPaymentToken = userInvestment.totalInvestedPaymentToken;

        return Math.mulDiv(totalTokenAllocated, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
    }

    /**
     * @notice function to compute current amount claimable by user for an investment
     * @dev contractTokenBalnce + totalTokensClaimed is used to preserve user's claimable balance regardless of order
     * @param _kycAddress the address on whose behalf the claim is being made by msg.sender
     * @param _investmentId the id of the investment the user is claiming from
     */
    function computeUserClaimableAllocationForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) public view returns (uint256) {
        uint256 totalInvestedPaymentToken = investments[_investmentId].totalInvestedPaymentToken;
        if (totalInvestedPaymentToken == 0) return 0;

        uint256 totalTokensClaimed = investments[_investmentId].totalTokensClaimed;
        uint256 userTotalInvestedPaymentToken = userInvestments[_kycAddress][_investmentId]
            .totalInvestedPaymentToken;
        uint256 userTokensClaimed = userInvestments[_kycAddress][_investmentId].totalTokensClaimed;

        uint256 contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));

        uint256 userBaseClaimableTokens = Math.mulDiv(
            contractTokenBalance + totalTokensClaimed,
            userTotalInvestedPaymentToken,
            totalInvestedPaymentToken
        );

        return userBaseClaimableTokens - userTokensClaimed;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * @dev for frontend and _phaseCheck use, returns true if investment is open for a user based on their assigned phase
     * @param _investmentId the id of the investment the user is checking
     * @param _userPhase the phase the user is assigned to for the investment
     * @return true if the user's assigned phase matches the investment at _investmentId's current investment phase, false otherwise
     */
    function investmentIsOpen(uint16 _investmentId, uint8 _userPhase) public view returns (bool) {
        return investments[_investmentId].contributionPhase == _userPhase;
    }

    /**
     * @dev ensures signature is valid for the investment id specified in _params
     * @return bool true if the signature is valid, false otherwise
     */
    function _signatureCheck(InvestParams memory _params) private view returns (bool) {
        address _signer = investments[_params.investmentId].signer;

        return
            SignatureChecker.isValidSignatureNow(
                _signer,
                ECDSA.toEthSignedMessageHash(
                    keccak256(
                        abi.encodePacked(
                            _params.investmentId,
                            _params.kycAddress,
                            _params.maxInvestableAmount,
                            _params.userPhase,
                            block.chainid
                        )
                    )
                ),
                _params.signature
            );
    }

    /**
     * @dev confirms the user's phase is open for the investment while calling invest function
     * @return bool true if current phase of user's desired investment matches the user's assigned investment phase for that same investment, else false
     */
    function _phaseCheck(InvestParams memory _params) private view returns (bool) {
        return investmentIsOpen(_params.investmentId, _params.userPhase);
    }

    /**
     * @dev confirms the calling address's payment token allocation is sufficient for the amount they're trying to invest
     * @return bool true if the user's token allowance for the project token of investment of investmentId is sufficient for their proposed investment amount, else false
     */
    function _paymentTokenAllowanceCheck(InvestParams memory _params) private view returns (bool) {
        return
            investments[_params.investmentId].paymentToken.allowance(msg.sender, address(this)) >=
            _params.thisInvestmentAmount;
    }

    /**
     * @dev confirms the calling address's payment token allocation is sufficient for the amount they're trying to invest
     * @dev accuracy of maxInvestableAmount relies on integrity of _signatureCheck, in which maxInvestableAmount is validated before this function is called
     * @return bool true if the sum of the proposed contribution to investment of investmentId and any existing contribution to the same investment is less than or equal to the maximum allowed investable amount for that user
     */
    function _contributionLimitCheck(InvestParams memory _params) private view returns (bool) {
        uint256 proposedTotalContribution = _params.thisInvestmentAmount +
            userInvestments[_params.kycAddress][_params.investmentId].totalInvestedPaymentToken;
        bool withinLimit = proposedTotalContribution <= _params.maxInvestableAmount;
        return withinLimit;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // ADMIN WRITE FUNCTIONS (ADD INVESTMENT, REMOVE INVESTMENT, MODIFY INVESTMENT, SET INVESTMENT PHASE
    // ADD CONTRIBUTION MANUALLY, REFUND USER)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * @notice this function will be used to add a new investment to the contract
     * @dev the first investment's index will be 1, not 0
     * @dev signer, payment token, and total allocated payment token are set at the time of investment creation, rest are default amounts to be added before claim is opened (phase=closed=0, everything else 0's)
     * @param _signer is the admin address whose private key will be used to generate signatures for validating user's investment permissions
     * @param _paymentToken is the address of the token used to collect investment funds. this will usually be USDC (ETH: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
     * @param _totalAllocatedPaymentToken is the total amount of payment token allocated by a project for the entire investment. amount in the defined decimals of _paymentToken
     */
    function addInvestment(
        address _signer,
        address _paymentToken,
        uint128 _totalAllocatedPaymentToken,
        bool _pauseAfterCall
    ) external nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(INVESTMENT_MANAGER_ROLE) {
        //increment latestInvestmentId while creating new Investment struct with default parameters other than those specified in function inputs
        investments[++latestInvestmentId] = Investment({
            signer: _signer,
            projectToken: IERC20(address(0)),
            paymentToken: IERC20(_paymentToken),
            contributionPhase: 0,
            totalInvestedPaymentToken: 0,
            totalAllocatedPaymentToken: _totalAllocatedPaymentToken,
            totalTokensClaimed: 0,
            totalTokensAllocated: 0
        });

        emit InvestmentAdded(latestInvestmentId);
    }

    /**
     * @notice sets the current phase of the investment. phases can be 0-max uint8 value, but 0=closed, 1=whales, 2=sharks, 3=fcfs, so 4-max uint8 can be used for custom phases
     */
    function setInvestmentContributionPhase(
        uint16 _investmentId,
        uint8 _investmentPhase,
        bool _pauseAfterCall
    ) external nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].contributionPhase = _investmentPhase;
        emit InvestmentPhaseSet(_investmentId, _investmentPhase);
    }

    /**
     * @notice sets the token address of the payment token for the investment
     * @notice this function can only be called before any investment funds are deposited for the investment
     */
    function setInvestmentPaymentTokenAddress(
        uint16 _investmentId,
        address _paymentTokenAddress,
        bool _pauseAfterCall
    ) external nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(INVESTMENT_MANAGER_ROLE) {
        if (investments[_investmentId].totalInvestedPaymentToken != 0) {
            revert InvestmentTokenAlreadyDeposited();
        }

        investments[_investmentId].paymentToken = IERC20(_paymentTokenAddress);

        emit InvestmentPaymentTokenAddressSet(_investmentId, _paymentTokenAddress);
    }

    /**
     * @notice sets project token address for an investment
     */
    function setInvestmentProjectTokenAddress(
        uint16 _investmentId,
        address projectTokenAddress,
        bool _pauseAfterCall
    ) external nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].projectToken = IERC20(projectTokenAddress);
        emit InvestmentProjectTokenAddressSet(_investmentId, projectTokenAddress);
    }

    /**
     * @dev sets the amount of project token allocated for the investent - used in computeUserTotalAllocationForInvesment
     */
    function setInvestmentProjectTokenAllocation(
        uint16 _investmentId,
        uint256 totalTokensAllocated,
        bool _pauseAfterCall
    ) external nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].totalTokensAllocated = totalTokensAllocated;
        emit InvestmentProjectTokenAllocationSet(_investmentId, totalTokensAllocated);
    }

    /**
     * @dev admin-only for pausing/unpausing any function in the contract. this function cannot be paused itself.
     */
    function setFunctionIsPaused(
        bytes4 _selector,
        bool _isPaused
    ) external nonReentrant onlyRole(PAUSER_ROLE) {
        _setFunctionIsPaused(_selector, _isPaused);
    }

    /**
     * @dev admin-only for pausing/unpausing multiple functions. can be used as a safety measure to pause all functions in the contract. this function cannot be paused itself.
     */
    function batchSetFunctionIsPaused(
        bytes4[] calldata _selectors,
        bool[] calldata _isPaused
    ) external onlyRole(PAUSER_ROLE) {
        _batchSetFunctionIsPaused(_selectors, _isPaused);
    }

    /**
     * @dev this function will be used to manually add contributions to an investment, assuming paymentTokens were provided outside of the contract
     * @param _kycAddress address of user to add contribution to
     * @param _investmentId id of investment to add contribution to
     * @param _paymentTokenAmount amount of payment tokens to add to user's contribution
     */
    function manualAddContribution(
        address _kycAddress,
        uint16 _investmentId,
        uint128 _paymentTokenAmount,
        bool _pauseAfterCall
    ) public nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(ADD_CONTRIBUTION_ROLE) {
        if (_investmentId > latestInvestmentId || _investmentId == 0) {
            revert InvestmentDoesNotExist();
        }

        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken += uint128(
            _paymentTokenAmount
        );
        investments[_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;

        emit UserInvestmentContribution(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }

    /// @dev batch version of manualAddContribution for larger past activity imports
    function batchManualAddContribution(
        address[] memory _kycAddresses,
        uint16[] memory _investmentIds,
        uint128[] memory _paymentTokenAmount,
        bool _pauseAfterCall
    ) external {
        if (
            _kycAddresses.length != _investmentIds.length ||
            _kycAddresses.length != _paymentTokenAmount.length
        ) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _kycAddresses.length; ++i) {
            manualAddContribution(
                _kycAddresses[i],
                _investmentIds[i],
                uint128(_paymentTokenAmount[i]),
                _pauseAfterCall
            );
        }
    }

    /**
     * @dev manually refunds user
     * @param _kycAddress address of user to refund
     * @param _investmentId id of investment to refund from
     * @param _paymentTokenAmount amount of payment tokens to refund
     */
    function refundUser(
        address _kycAddress,
        uint16 _investmentId,
        uint128 _paymentTokenAmount,
        bool _pauseAfterCall
    ) public nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(REFUNDER_ROLE) {
        // refund is not 0
        if (_paymentTokenAmount == 0) {
            revert CantRefundZero();
        }

        // refund amount must not be more than the user has invested. this will also catch wrong investmentId inputs
        if (_paymentTokenAmount > userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken) {
            revert RefundAmountExceedsUserBalance();
        }

        // contract must not contain project token, to avoid manipulation of refunds based on token price
        if (investments[_investmentId].projectToken.balanceOf(address(this)) > 0) {
            revert TooLateForRefund();
        }

        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken -= uint128(
            _paymentTokenAmount
        );
        investments[_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;
        investments[_investmentId].paymentToken.safeTransfer(_kycAddress, _paymentTokenAmount);

        emit UserRefunded(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }

    /**
     * @dev transfers payment token for investment to desired destination address (i.e. a project's wallet)
     */
    function transferPaymentToken(
        uint16 _investmentId,
        address _destinationAddress,
        uint128 _paymentTokenAmount,
        bool _pauseAfterCall
    ) public nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(PAYMENT_TOKEN_TRANSFER_ROLE) {
        if (_investmentId > latestInvestmentId || _investmentId == 0) {
            revert InvestmentDoesNotExist();
        }

        if (_paymentTokenAmount == 0) {
            revert CantTransferZero();
        }

        if (_paymentTokenAmount > investments[_investmentId].totalInvestedPaymentToken) {
            revert TransferAmountExceedsInvestmentBalance();
        }

        investments[_investmentId].paymentToken.safeTransfer(_destinationAddress, _paymentTokenAmount);

        emit PaymentTokenTransferred(msg.sender, _investmentId, _destinationAddress, _paymentTokenAmount);
    }

    /**
     * @dev recovers ERC20 tokens sent to this contract by mistake. Paused by default, can only be opened by PAUSER_ROLE and called by PAYMENT_TOKEN_TRANSFER_ROLE.
     */
    function recoverERC20(
        address _tokenAddress,
        address _destinationAddress,
        uint256 _tokenAmount,
        bool _pauseAfterCall
    ) public nonReentrant whenNotPausedSelective(_pauseAfterCall) onlyRole(PAYMENT_TOKEN_TRANSFER_ROLE) {
        if (_tokenAmount > IERC20(_tokenAddress).balanceOf(address(this))) {
            revert ERC20AmountExceedsBalance();
        }
        IERC20(_tokenAddress).safeTransfer(_destinationAddress, _tokenAmount);
        emit ERC20Recovered(msg.sender, _tokenAddress, _destinationAddress, _tokenAmount);
    }
}
