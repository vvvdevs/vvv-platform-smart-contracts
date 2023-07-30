//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title InvestmentHandler
 * @author @vvvfund (@curi0n-s + @kcper + @c0dejax)
 * @notice Handles the investment process for vVv allocations from contributing the payment token to claiming the project token
 * @notice Any address can invest on behalf of a kyc address, but only "in-network" addresses can claim on behalf of a kyc address
 */

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvestmentHandler is 
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // STORAGE & SETUP
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    /// @dev role for adding and modifying investment data
    bytes32 private constant INVESTMENT_MANAGER_ROLE = keccak256("ADD_INVESTMENT_ROLE");
    bytes32 private constant ADD_CONTRIBUTION_ROLE = keccak256("ADD_CONTRIBUTION_ROLE");
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
        uint totalTokensClaimed;
        uint totalTokensAllocated;
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
        uint totalTokensClaimed;
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
    mapping(uint => Investment) public investments;

    /// @notice user => investmentId => userInvestment
    mapping(address => mapping(uint => UserInvestment)) public userInvestments;
    mapping(address => uint[]) public userInvestmentIds;

    /// @notice kyc address => in-network address => bool
    mapping(address => mapping(address => bool)) public isInKycAddressNetwork;
    mapping(address => address) public correspondingKycAddress;
    
    // Events
    event InvestmentAdded(uint indexed investmentId);
    event InvestmentPaymentTokenAddressSet(uint indexed investmentId, address indexed paymentToken);
    event InvestmentPhaseSet(uint indexed investmentId, uint indexed phase);
    event InvestmentProjectTokenAddressSet(uint indexed investmentId, address indexed projectToken);
    event InvestmentProjectTokenAllocationSet(uint indexed investmentId, uint indexed amount);
    event UserInvestmentContribution(address indexed sender, address indexed kycAddress, uint indexed investmentId, uint amount);
    event UserInvestmentTransfer(address sender, address indexed oldKycAddress, address indexed newKycAddress, uint indexed investmentId, uint amount);
    event UserTokenClaim(address indexed sender, address tokenRecipient, address indexed kycAddress, uint indexed investmentId, uint amount);
    event UserRefunded(address indexed sender, address indexed kycAddress, uint indexed investmentId, uint amount);
    event AddressAddedToKycAddressNetwork(address indexed kycAddress, address indexed addedAddress);
    event AddressRemovedFromKycAddressNetwork(address indexed kycAddress, address indexed removedAddress);
    
    // Errors
    error AddressAlreadyInKycNetwork();
    error AddressNotInKycNetwork();
    error ClaimAmountExceedsTotalClaimable();
    error InvalidSignature();
    error InsufficientAllowance();
    error InvestmentAmountExceedsMax();
    error InvestmentDoesNotExist();
    error InvestmentIsNotOpen();
    error InvestmentTokenAlreadyDeposited();
    error NotInKycAddressNetwork();
    error NotKycAddress();
    error RefundAmountExceedsUserBalance();
    error UserAlreadyClaimedTokens();


    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INITIALIZATION & MODIFIERS
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    /**
     * @dev constructor handles role setup
     */
    constructor(
         address _defaultAdminController, 
         address _investmentManager,
         address _contributionAndRefundManager,
         address _refunder
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdminController);
        _grantRole(INVESTMENT_MANAGER_ROLE, _investmentManager);
        _grantRole(ADD_CONTRIBUTION_ROLE, _contributionAndRefundManager);
        _grantRole(REFUNDER_ROLE, _refunder);
    }    

    /**
     * @dev modifier to check addresses involved in claim
     * @dev msg.sender and _tokenRecipient must be in network of _kycAddress
     */
    modifier claimChecks(uint _investmentId, uint _thisClaimAmount, address _tokenRecipient, address _kycAddress) {        
        uint claimableTokens = computeUserClaimableAllocationForInvestment(_kycAddress, _investmentId);
        
        if(_thisClaimAmount > claimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        if(
            (
                !isInKycAddressNetwork[_kycAddress][_tokenRecipient] &&
                _tokenRecipient != _kycAddress
            ) || (
                !isInKycAddressNetwork[_kycAddress][msg.sender] &&
                msg.sender != _kycAddress
            )
        ){
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
     *  
     *      1. will users have to supply pledged amount in one txn? or can they contribute multiple times? --> Multiple is OK
     *      2. consider the case where user contributes initial allocation, then allocation is increased --> No problem, just new pledge debt.
     *      3. could track "pledge debt" as a metric of whether the user follows thru on pledges of X amount --> include.
     */
    modifier investChecks(InvestParams memory _params) {
        if(!_signatureCheck(_params)) {
            revert InvalidSignature();
        } else if(!_phaseCheck(_params)) {
            revert InvestmentIsNotOpen();
        } else if(!_paymentTokenAllowanceCheck(_params)) {
            revert InsufficientAllowance();
        } else if(!_contributionLimitCheck(_params)) {
            revert InvestmentAmountExceedsMax();
        }
        _;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // USER WRITE FUNCTIONS (INVEST, CLAIM)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    /** 
     * @dev this function will be called by the user to claim their tokens
     * @param _investmentId the id of the investment the user is claiming from
     * @param _claimAmount the amount of tokens the user is claiming
     * @param _tokenRecipient the address the address which will receive the tokens
     * @notice allows any in-network address to claim tokens to any address on behalf of the kyc address
     * @notice UI can grab _kycAddress via correspondingKycAddress[msg.sender]
     * @notice both msg.sender and _tokenRecipient must be in network of _kycAddress, and msg.sender 
     *  can be the same as _tokenRecipient
     */
    function claim(
        uint _investmentId, 
        uint _claimAmount, 
        address _tokenRecipient, 
        address _kycAddress
    ) external whenNotPaused claimChecks(
        _investmentId, 
        _claimAmount, 
        _tokenRecipient, 
        _kycAddress
    ) {
        UserInvestment storage userInvestment = userInvestments[_kycAddress][_investmentId];
        Investment storage investment = investments[_investmentId];
        
        userInvestment.totalTokensClaimed += _claimAmount;
        investment.totalTokensClaimed += _claimAmount;            

        investment.projectToken.safeTransfer(_tokenRecipient, _claimAmount);

        emit UserTokenClaim(msg.sender, _tokenRecipient, _kycAddress, _investmentId, _claimAmount);
    }

    /**
     * @dev this function will be called by the user to invest in the project
     * @param _params the parameters for the investment as specified in InvestParams
     * @notice adds to users total usd invested for investment + total usd in investment overall
     * @notice adjusts user's pledge debt (pledged - contributed)
     */
    function invest(
        InvestParams memory _params
    ) external nonReentrant whenNotPaused investChecks(_params) {
        UserInvestment storage userInvestment = userInvestments[_params.kycAddress][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];

        investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        userInvestment.totalInvestedPaymentToken += uint128(_params.thisInvestmentAmount);
        userInvestment.pledgeDebt = uint128(_params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken);
        
        userInvestmentIds[_params.kycAddress].push(_params.investmentId);
        investment.paymentToken.safeTransferFrom(msg.sender, address(this), _params.thisInvestmentAmount);

        emit UserInvestmentContribution(msg.sender, _params.kycAddress, _params.investmentId, _params.thisInvestmentAmount);

    }

    /**
     * @dev this function will be called by a kyc'd address to add a address to its network
     * @param _newAddress the address of the address to be added to the network
     * @notice allows any address to add any other address to its network, but this is 
     *         only is of use to addresss who are kyc'd and able to invest/claim
     */
    function addAddressToKycAddressNetwork(address _newAddress) external {
        if(correspondingKycAddress[_newAddress] != address(0)) {
            revert AddressAlreadyInKycNetwork();
        }

        isInKycAddressNetwork[msg.sender][_newAddress] = true;
        correspondingKycAddress[_newAddress] = msg.sender;

        emit AddressAddedToKycAddressNetwork(msg.sender, _newAddress);
    }

    /**
     * @dev this function will be called by a kyc'd address to remove a address from its network
     * @param _networkAddress the address of the address to be removed from the network, must be
     *                       in the network of the calling kyc address
     * @notice allows any address to remove any other address from its network, but this is
     *         only is of use to addresss who are kyc'd and able to invest/claim
     */
    function removeAddressFromKycAddressNetwork(address _networkAddress) external {
        if(correspondingKycAddress[_networkAddress] != msg.sender) {
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
     * @dev returns user's total claimed project tokens for an investment
     */
    function getTotalClaimedForInvestment(address _kycAddress, uint _investmentId) external view returns (uint) {
        return userInvestments[_kycAddress][_investmentId].totalTokensClaimed;
    }

    /**
     * @dev for frontend - returns the total amount of project tokens a user can claim for an investment
     */
    function computeUserTotalAllocationForInvesment(address _kycAddress, uint _investmentId) external view returns (uint) {
        UserInvestment storage userInvestment = userInvestments[_kycAddress][_investmentId];
        Investment storage investment = investments[_investmentId];

        uint totalTokenAllocated = investment.totalTokensAllocated;
        uint userTotalInvestedPaymentToken = userInvestment.totalInvestedPaymentToken;
        uint totalInvestedPaymentToken = investment.totalInvestedPaymentToken;

        return Math.mulDiv(totalTokenAllocated, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
    }


    /**
     * @dev function to compute current amount claimable by user for an investment
     * @param _kycAddress the address on whose behalf the claim is being made by msg.sender
     * @param _investmentId the id of the investment the user is claiming from
     * @notice contractTokenBalnce + totalTokensClaimed is used to preserve user's claimable balance regardless of order
     */
    function computeUserClaimableAllocationForInvestment(address _kycAddress, uint _investmentId) public view returns (uint) {
        uint totalInvestedPaymentToken = investments[_investmentId].totalInvestedPaymentToken;
        uint totalTokensClaimed = investments[_investmentId].totalTokensClaimed;
        uint userTotalInvestedPaymentToken = userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken;
        uint userTokensClaimed = userInvestments[_kycAddress][_investmentId].totalTokensClaimed;

        uint claimableTokens;
        uint contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));
        
        uint userBaseClaimableTokens = Math.mulDiv(contractTokenBalance+totalTokensClaimed, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
        claimableTokens = userBaseClaimableTokens - userTokensClaimed;
        
        return claimableTokens;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    /**
     * @dev returns true if investment is open for a user based on their assigned phase
     * @param _investmentId the id of the investment the user is checking
     * @param _userPhase the phase the user is assigned to for the investment
     */
    function investmentIsOpen(uint _investmentId, uint _userPhase) public view returns (bool) {
        return investments[_investmentId].contributionPhase == _userPhase;
    }

    /**
     * @dev private helpers for investChecks to avoid stack-too-deep errors
     * @notice ensures signature is valid for the investment id specified in _params
     */
    function _signatureCheck(InvestParams memory _params) private view returns (bool) {
        address _signer = investments[_params.investmentId].signer;
        
        return SignatureChecker.isValidSignatureNow(
                _signer,
                ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_params.kycAddress, _params.maxInvestableAmount, _params.userPhase))),
                _params.signature
        );
    }

    /**
     * @dev confirms the user's phase is open for the investment while calling invest function
     */
    function _phaseCheck(InvestParams memory _params) private view returns (bool) {
        return investmentIsOpen(_params.investmentId, _params.userPhase);
    }

    /**
     * @dev confirms the calling address's payment token allocation is sufficient for the amount they're trying to invest
     */
    function _paymentTokenAllowanceCheck(InvestParams memory _params) private view returns (bool) {
        return investments[_params.investmentId].paymentToken.allowance(msg.sender, address(this)) >= _params.thisInvestmentAmount;
    }
    
    /**
     * @dev confirms the calling address's payment token allocation is sufficient for the amount they're trying to invest
     */
    function _contributionLimitCheck(InvestParams memory _params) private view returns (bool) {
        uint proposedTotalContribution = _params.thisInvestmentAmount + userInvestments[_params.kycAddress][_params.investmentId].totalInvestedPaymentToken;        
        return  proposedTotalContribution <= _params.maxInvestableAmount;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // ADMIN WRITE FUNCTIONS (ADD INVESTMENT, REMOVE INVESTMENT, MODIFY INVESTMENT, SET INVESTMENT PHASE 
    // ADD CONTRIBUTION MANUALLY, REFUND USER)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * @dev this function will be used to add a new investment to the contract
     * @notice the first investment's index will be 1, not 0
     * @notice signer, payment token, and total allocated payment token are set at the time of investment creation, 
     *         rest are default amounts to be added before claim is opened (phase=closed=0, everything else 0's)
     */
    function addInvestment(
        address _signer,
        address _paymentToken,
        uint128 _totalAllocatedPaymentToken
    ) external nonReentrant onlyRole(INVESTMENT_MANAGER_ROLE) {
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
     * @dev sets the current phase of the investment. phases can be 0-max uintN value, but
     *      0=closed, 1=whales, 2=sharks, 3=fcfs, so 4-max uintN can be used for custom phases    
     */
    function setInvestmentContributionPhase(uint _investmentId, uint8 _investmentPhase) external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].contributionPhase = _investmentPhase;
        emit InvestmentPhaseSet(_investmentId, _investmentPhase);
    }

    /**
     * @dev sets the token address of the payment token for the investment
     * @notice this function can only be called before any investment funds are deposited for the investment
     */
    function setInvestmentPaymentTokenAddress(uint _investmentId, address _paymentTokenAddress) external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        if(investments[_investmentId].totalInvestedPaymentToken != 0){
            revert InvestmentTokenAlreadyDeposited();
        }
        
        investments[_investmentId].paymentToken = IERC20(_paymentTokenAddress);
        emit InvestmentPaymentTokenAddressSet(_investmentId, _paymentTokenAddress);
    }

    /**
     * @dev caller is admin, sets project token address for an investment
     */
    function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].projectToken = IERC20(projectTokenAddress);
        emit InvestmentProjectTokenAddressSet(_investmentId, projectTokenAddress);
    }

    /**
     * @dev sets the amount of project token allocated for the investent - used in computeUserTotalAllocationForInvesment
     */
    function setInvestmentProjectTokenAllocation(uint _investmentId, uint totalTokensAllocated) external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        investments[_investmentId].totalTokensAllocated = totalTokensAllocated;
        emit InvestmentProjectTokenAllocationSet(_investmentId, totalTokensAllocated);
    }


    /**
     * @dev admin-only for pausing/unpausing all user-facing functions
     */
    function pause() external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        _pause();
    }

    function unPause() external payable onlyRole(INVESTMENT_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev this function will be used to manually add contributions to an investment, assuming paymentTokens were provided outside of the contract
     * @param _kycAddress address of user to add contribution to
     * @param _investmentId id of investment to add contribution to
     * @param _paymentTokenAmount amount of payment tokens to add to user's contribution
     */
    function manualAddContribution(address _kycAddress, uint _investmentId, uint128 _paymentTokenAmount) external payable nonReentrant onlyRole(ADD_CONTRIBUTION_ROLE) {
        
        if(_investmentId > latestInvestmentId){
            revert InvestmentDoesNotExist();
        }
        
        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken += uint128(_paymentTokenAmount);
        investments[_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;            

        emit UserInvestmentContribution(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }
    
    /**
     * @dev manually refunds user
     * @param _kycAddress address of user to refund
     * @param _investmentId id of investment to refund from
     * @param _paymentTokenAmount amount of payment tokens to refund
     */
    function refundUser(address _kycAddress, uint _investmentId, uint128 _paymentTokenAmount) external payable nonReentrant onlyRole(REFUNDER_ROLE) {
        if(userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken < _paymentTokenAmount){
            revert RefundAmountExceedsUserBalance();
        }       

        if(_investmentId > latestInvestmentId){
            revert InvestmentDoesNotExist();
        }
        
        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken -= uint128(_paymentTokenAmount);
        investments[_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;            

        investments[_investmentId].paymentToken.safeTransfer(_kycAddress, _paymentTokenAmount);
        emit UserRefunded(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }

}
