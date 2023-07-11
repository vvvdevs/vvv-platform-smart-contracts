//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title InvestmentHandler
 * @author @vvvfund (@curi0n-s + @kcper + @c0dejax)
 * @notice Handles the investment process for vVv allocations from contributing the payment token to claiming the project token
 * @notice Any wallet can invest on behalf of a kyc wallet, but only "in-network" addresses can claim on behalf of a kyc wallet
 * @dev This contract is upgradeable and pausable
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract InvestmentHandler is 
    Initializable, 
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // STORAGE & SETUP
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public deployer;
    
    /// @dev role for adding and modifying investments
    bytes32 public MANAGER_ROLE;
    
    /// @dev global tracker for latest investment id
    uint public latestInvestmentId; 

    /// @dev enum for investment phases
    enum Phase {
        CLOSED,
        WHALE,
        SHARK,
        FCFS
    } 

    /**
     * @notice Investment struct
     * @param signer address of the signer for this investment
     * @param contributionPhase struct containing phase and start/end times
     * @param projectToken address of the project token
     * @param paymentToken address of the payment token
     * @param totalInvestedPaymentToken total amount of payment token invested in this investment
     * @param totalAllocatedPaymentToken total amount of payment token allocated to this investment
     * @param totalTokensClaimed total amount of project token claimed from this investment
     * @param totalTokensAllocated total amount of project token allocated to this investment
     */
    struct Investment {
        address signer; 
        ContributionPhase contributionPhase;
        IERC20Upgradeable projectToken;
        IERC20Upgradeable paymentToken;
        uint totalInvestedPaymentToken;
        uint totalAllocatedPaymentToken;
        uint totalTokensClaimed;
        uint totalTokensAllocated;
    }

    /// @curi0n-s will start/end times have use still? 
    struct ContributionPhase {
        Phase phase;
        uint startTime;
        uint endTime;
    }

    struct UserInvestment {
        uint totalInvestedPaymentToken;
        uint pledgeDebt;
        uint totalTokensClaimed;
        uint[] tokenWithdrawalAmounts;
        uint[] tokenWithdrawalTimestamps;
    }

    struct InvestParams {
        uint investmentId;
        uint maxInvestableAmount;
        uint thisInvestmentAmount;
        Phase userPhase;
        address kycAddress;
        address signer;
        bytes signature;
    }

    /// @notice investmentId => investment
    mapping(uint => Investment) public investments;

    /// @notice user => investmentId => userInvestment
    mapping(address => mapping(uint => UserInvestment)) public userInvestments;

    /// @notice kyc address => in-network address => bool
    mapping(address => mapping(address => bool)) public isInKycWalletNetwork;
    mapping(address => address) public correspondingKycAddress;
    
    // @curi0n-s reserve space for upgrade if needed
    uint[48] __gap; 

    // Events
    event InvestmentAdded(uint indexed investmentId);
    event InvestmentPhaseSet(uint indexed investmentId, Phase indexed phase);
    event InvestmentProjectTokenAddressSet(uint indexed investmentId, address indexed projectToken);
    event InvestmentProjectTokenAllocationSet(uint indexed investmentId, uint indexed amount);
    event UserContributionToInvestment(address indexed sender, address indexed kycWallet, uint indexed investmentId, uint amount);
    event UserTokenClaim(address indexed sender, address tokenRecipient, address indexed kycWallet, uint indexed investmentId, uint amount);
    event WalletAddedToKycNetwork(address indexed kycWallet, address indexed wallet);
    event UserRefunded(address indexed sender, address indexed kycWallet, uint indexed investmentId, uint amount);

    error ClaimAmountExceedsTotalClaimable();
    error InsufficientAllowance();
    error InvestmentAmountExceedsMax();
    error InvestmentIsNotOpen();
    error InvalidSignature();
    error NotInKycWalletNetwork();
    error RefundAmountExceedsUserBalance();

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INITIALIZATION & MODIFIERS
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }    
    
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        deployer = msg.sender;
        MANAGER_ROLE = keccak256("MANAGER_ROLE");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
        
    }

    /**
     * @dev modifier to check addresses involved in claim
     * @dev msg.sender and _tokenRecipient must be in network of _kycAddress
     */
    
    modifier claimChecks(uint _investmentId, uint _thisClaimAmount, address _tokenRecipient, address _kycAddress) {        
        uint claimableTokens = computeUserClaimableAllocationForInvestment(_tokenRecipient, _investmentId);
        
        if(_thisClaimAmount > claimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        if(
            (
                !isInKycWalletNetwork[_kycAddress][_tokenRecipient] &&
                _tokenRecipient != _kycAddress
            ) || (
                !isInKycWalletNetwork[_kycAddress][msg.sender] &&
                msg.sender != _kycAddress
            )
        ){
            revert NotInKycWalletNetwork();
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
     * @param _tokenRecipient the address the wallet which will receive the tokens
     * @notice allows any in-network wallet to claim tokens to any wallet on behalf of the kyc wallet
     * @notice UI can grab _kycWallet via correspondingKycAddress[msg.sender]
     */
    
    function claim(
        uint _investmentId, 
        uint _claimAmount, 
        address _tokenRecipient, 
        address _kycAddress
    ) public whenNotPaused() claimChecks(
        _investmentId, 
        _claimAmount, 
        _tokenRecipient, 
        _kycAddress
    ) {
        UserInvestment storage userInvestment = userInvestments[_tokenRecipient][_investmentId];
        Investment storage investment = investments[_investmentId];

        userInvestment.totalTokensClaimed += _claimAmount;
        investment.totalTokensClaimed += _claimAmount;

        userInvestment.tokenWithdrawalAmounts.push(_claimAmount);
        userInvestment.tokenWithdrawalTimestamps.push(block.timestamp);

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
    ) public nonReentrant whenNotPaused investChecks(_params) {

        UserInvestment storage userInvestment = userInvestments[_params.kycAddress][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];
        userInvestment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        
        /// @curi0n-s [!] Confirm things will work in the case that _maxInvestableAmount changes, and user has already contributed
        /// note that userInvestment.totalInvestedPaymentToken is incremented above so the below includes
        /// both the previously invested amount as well as the current proposed investment amount
        userInvestment.pledgeDebt = _params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken;
        
        investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;

        investment.paymentToken.safeTransferFrom(msg.sender, address(this), _params.thisInvestmentAmount);

        emit UserContributionToInvestment(msg.sender, _params.kycAddress, _params.investmentId, _params.thisInvestmentAmount);

    }

    /**
     * @dev this function will be called by a kyc'd wallet to add a wallet to its network
     * @param _newWallet the address of the wallet to be added to the network
     * @notice allows any wallet to add any other wallet to its network, but this is 
     *         only is of use to wallets who are kyc'd and able to invest/claim
     */

    function addWalletToKycWalletNetwork(address _newWallet) external {
        isInKycWalletNetwork[msg.sender][_newWallet] = true;
        correspondingKycAddress[_newWallet] = msg.sender;
        emit WalletAddedToKycNetwork(msg.sender, _newWallet);
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // USER READ FUNCTIONS (USER INVESTMENTS, USER CLAIMABLE ALLOCATION, USER TOTAL ALLOCATION)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    /**
     * @dev function to return all investment ids for a user
     */
    function getUserInvestmentIds(address _kycAddress) public view returns (uint[] memory) {
        uint j;
        uint[] memory investmentIds;

        for(uint i = 0; i<latestInvestmentId; ++i){
            if(userInvestments[_kycAddress][i].totalInvestedPaymentToken > 0){
                investmentIds[j] = i;
                ++j;
            }
        }

        return investmentIds;
    }

    function getTotalClaimedForInvestment(address _kycAddress, uint _investmentId) public view returns (uint) {
        return userInvestments[_kycAddress][_investmentId].totalTokensClaimed;
    }

    function computeUserTotalAllocationForInvesment(address _kycAddress, uint _investmentId) public view returns (uint) {
        UserInvestment storage userInvestment = userInvestments[_kycAddress][_investmentId];
        Investment storage investment = investments[_investmentId];

        uint totalTokenAllocated = investment.totalTokensAllocated;
        uint userTotalInvestedPaymentToken = userInvestment.totalInvestedPaymentToken;
        uint totalInvestedPaymentToken = investment.totalInvestedPaymentToken;

        return MathUpgradeable.mulDiv(totalTokenAllocated, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
    }


    /**
     * @dev function to compute current amount claimable by user for an investment
     * @param _sender the address of the user claiming
     * @param _investmentId the id of the investment the user is claiming from
     * @notice contractTokenBalnce + totalTokensClaimed is used to preserve user's claimable balance regardless of order
     */

    /**
        NOTES:
        this will be a bit spicy - this will calculate claimable tokens, 
        based on users % share of allocation

        assumes that since they could invest, no further signature validation of the pledge amount is needed

        confirm that math works out regardless of claim timing and frequency!

        [confirm] contract balance of token + total tokens claimed is used to preserve user's claimable balance regardless of order

        no checks for math yet, but this assumes that (totalTokensAllocated*userTotalInvestedPaymentToken)/totalInvestedPaymentToken
        will work, i.e. num >> denom, when assigning to userTotalClaimableTokens. if not, maybe will need to add 
        the case for num < denom. same thing for userBaseClaimableTokens

        i.e. consider that we get 1 Investment Token for 1000 Payment Tokens (both 18 decimals), will rounding/truncation errors get significant?
     */

    function computeUserClaimableAllocationForInvestment(address _kycAddress, uint _investmentId) public view returns (uint) {
        
        uint totalInvestedPaymentToken = investments[_investmentId].totalInvestedPaymentToken;
        uint totalTokensClaimed = investments[_investmentId].totalTokensClaimed;
        uint userTotalInvestedPaymentToken = userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken;
        uint userTokensClaimed = userInvestments[_kycAddress][_investmentId].totalTokensClaimed;

        uint contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));
        uint userBaseClaimableTokens = MathUpgradeable.mulDiv(contractTokenBalance+totalTokensClaimed, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
        uint userClaimableTokens = userBaseClaimableTokens - userTokensClaimed;
        
        return userClaimableTokens;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    function investmentIsOpen(uint _investmentId, Phase _userPhase) public view returns (bool) {
        return investments[_investmentId].contributionPhase.phase == _userPhase;
    }

    /// @dev private helpers for investChecks to avoid stack-too-deep errors...
    function _signatureCheck(InvestParams memory _params) private view returns (bool) {
        return SignatureCheckerUpgradeable.isValidSignatureNow(
                _params.signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(_params.kycAddress, _params.maxInvestableAmount, _params.userPhase))),
                _params.signature
        );
    }

    function _phaseCheck(InvestParams memory _params) private view returns (bool) {
        return investmentIsOpen(_params.investmentId, _params.userPhase);
    }

    function _paymentTokenAllowanceCheck(InvestParams memory _params) private view returns (bool) {
        return investments[_params.investmentId].paymentToken.allowance(_params.kycAddress, address(this)) >= _params.thisInvestmentAmount;
    }
    
    function _contributionLimitCheck(InvestParams memory _params) private view returns (bool) {
        return _params.thisInvestmentAmount + userInvestments[_params.kycAddress][_params.investmentId].totalInvestedPaymentToken <= _params.maxInvestableAmount;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // ADMIN WRITE FUNCTIONS (ADD INVESTMENT, REMOVE INVESTMENT, MODIFY INVESTMENT, SET INVESTMENT PHASE 
    // ADD CONTRIBUTION MANUALLY, REFUND USER)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
     * For now, assuming MANAGER_ROLE will handle this all, and can be given to multiple addresses/roles
     * @dev this function will be used to add a new investment to the contract
     */

    function addInvestment(
        address _signer,
        IERC20Upgradeable _paymentToken,
        uint _totalAllocatedPaymentToken
    ) public onlyRole(MANAGER_ROLE) {
        investments[++latestInvestmentId] = Investment({
            signer: _signer,
            contributionPhase: ContributionPhase({
                phase: Phase.CLOSED,
                startTime: 0,
                endTime: 0
            }),
            projectToken: IERC20Upgradeable(address(0)),
            paymentToken: _paymentToken,
            totalInvestedPaymentToken: 0,
            totalAllocatedPaymentToken: _totalAllocatedPaymentToken,
            totalTokensClaimed: 0,
            totalTokensAllocated: 0
        });
        emit InvestmentAdded(latestInvestmentId);
    }

    function setInvestmentContributionPhase(uint _investmentId, Phase _investmentPhase) external onlyRole(MANAGER_ROLE) {
        investments[_investmentId].contributionPhase.phase = _investmentPhase;
        emit InvestmentPhaseSet(_investmentId, _investmentPhase);
    }

    function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) public onlyRole(MANAGER_ROLE) {
        investments[_investmentId].projectToken = IERC20Upgradeable(projectTokenAddress);
        emit InvestmentProjectTokenAddressSet(_investmentId, projectTokenAddress);
    }

    function setInvestmentProjectTokenAllocation(uint _investmentId, uint totalTokensAllocated) public onlyRole(MANAGER_ROLE) {
        investments[_investmentId].totalTokensAllocated = totalTokensAllocated;
        emit InvestmentProjectTokenAllocationSet(_investmentId, totalTokensAllocated);
    }

    /**
     * @dev this function will be used to manually add contributions to an investment, assuming paymentTokens were provided outside of the contract
     * @param _kycAddress address of user to add contribution to
     * @param _investmentId id of investment to add contribution to
     * @param _paymentTokenAmount amount of payment tokens to add to user's contribution
     */
    function manualAddContribution(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public onlyRole(MANAGER_ROLE) {
        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;
        investments[_investmentId].totalInvestedPaymentToken += _paymentTokenAmount;
        emit UserContributionToInvestment(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }


    /**
     * @dev manually refunds user
     * @param _kycAddress address of user to refund
     * @param _investmentId id of investment to refund from
     * @param _paymentTokenAmount amount of payment tokens to refund
     */
    function refundUser(address _kycAddress, uint _investmentId, uint _paymentTokenAmount) public onlyRole(MANAGER_ROLE) {
        if(userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken < _paymentTokenAmount){
            revert RefundAmountExceedsUserBalance();
        }        
        userInvestments[_kycAddress][_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;
        investments[_investmentId].totalInvestedPaymentToken -= _paymentTokenAmount;
        investments[_investmentId].paymentToken.safeTransfer(_kycAddress, _paymentTokenAmount);
        emit UserRefunded(msg.sender, _kycAddress, _investmentId, _paymentTokenAmount);
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // TESTING - TO BE DELETED LATER?
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    function checkSignature(address signer, address _user, uint256 _maxInvestableAmount, Phase _userPhase, bytes memory signature) public view returns (bool) {
        return(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(_user, _maxInvestableAmount, _userPhase))),
                signature
            )
        );
    }

}