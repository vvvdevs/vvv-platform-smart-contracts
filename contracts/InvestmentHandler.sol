//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
@title InvestmentHandler
@author @vvvfund (@c0dejax, @kcper, @curi0n-s)

@notice InvestmentHandler is a contract that handles the investment process for a given project. It is responsible for:
    1. Allowing users to invest in a project
    2. Allowing users to claim their allocation
    3. Allowing admins to add/remove/modify investments
    4. Allowing admins to set the investment phase

    ???
    1. is IERC20Upgradeable the interface we should use for all IERC20 interfacing,
        because it's done in an upgradeable contract, or is it an interface to 
        upgradeable ERC20 tokens?
 */

/**
 * @title InvestmentHandler
 * @author @vvvfund (@curi0n-s, @kcper, @c0dejax)
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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 

// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
// import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

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

    address public deployer;
    
    /// @dev role for adding and modifying investments
    bytes32 public MANAGER_ROLE;
    
    /// @dev global tracker for latest investment id
    uint public investmentId; 
    
    /// @dev global tracker for total invested in contract (TESTING!)
    uint public contractTotalInvestedPaymentToken; 

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
        IERC20 projectToken;
        IERC20 paymentToken;
        uint totalInvestedPaymentToken;
        uint totalAllocatedPaymentToken;
        uint totalTokensClaimed;
        uint totalTokensAllocated;
    }

    struct ContributionPhase {
        Phase phase;
        uint startTime;
        uint endTime;
    }

    struct UserInvestment {
        uint totalInvestedPaymentToken;
        uint pledgeDebt;
        uint totalTokensClaimed;
        uint[] tokenWithdrawalAmounts; //@curi0n-s are arrays the move for recording withdrawal amounts and timestamps here?
        uint[] tokenWithdrawalTimestamps;
    }

    struct InvestParams {
        uint investmentId;
        uint maxInvestableAmount;
        uint thisInvestmentAmount;
        Phase userPhase;
        address user;
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
    
    // @curi0n-s reserve space for upgrade if needed?
    uint[48] __gap; 

    // Events
    event InvestmentAdded(uint indexed investmentId);
    event InvestmentRemoved();
    event InvestmentModified();
    event InvestmentPhaseSet();
    event UserContributionToInvestment(address indexed sender, address indexed kycWallet, uint indexed investmentId, uint amount);
    event UserTokenClaim(address indexed sender, address tokenRecipient, address indexed kycWallet, uint indexed investmentId, uint amount);
    event WalletAddedToKycNetwork(address indexed kycWallet, address indexed wallet);

    error ClaimAmountExceedsTotalClaimable();
    error InsufficientAllowance();
    error InvestmentAmountExceedsMax();
    error InvestmentIsNotOpen();
    error InvalidSignature();
    error NotInKycWalletNetwork();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INITIALIZATION & MODIFIERS
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        deployer = msg.sender;
        MANAGER_ROLE = keccak256("MANAGER_ROLE");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
        
    }
    
    modifier claimChecks(uint _investmentId, uint _thisClaimAmount, address _tokenRecipient, address _kycAddress) {        
        uint claimableTokens = _computeUserClaimableAllocationForInvestment(_tokenRecipient, _investmentId);
        
        if(_thisClaimAmount > claimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        if(!isInKycWalletNetwork[_kycAddress][msg.sender]){
            revert NotInKycWalletNetwork();
        }

        _;
    }

    /**
        @dev checks to make sure user is able to investment the amount, at this time
            1. investment phase is open
            2. signature validates user max investable amount and address
            3. user has approved spending of the investment amount in the desired paymentToken
            3. user investment amount + current proposed investment amount is less than max investable amount
        
            1. will users have to supply pledged amount in one txn? or can they contribute multiple times?
            2. consider the case where user contributes initial allocation, then allocation is increased
            3. could track "pledge debt" as a metric of whether the user follows thru on pledges of X amount
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

        investment.projectToken.transfer(_tokenRecipient, _claimAmount);

        emit UserTokenClaim(msg.sender, _tokenRecipient, _kycAddress, _investmentId, _claimAmount);
    }

    /**
        @dev this function will be called by the user to invest in the project
        @param _params the parameters for the investment as specified in InvestParams
        @notice adds to users total usd invested for investment + total usd in investment overall
        @notice adjusts user's pledge debt (pledged - contributed

     */

    function invest(
        InvestParams memory _params
    ) public nonReentrant whenNotPaused() investChecks(_params) {

        UserInvestment storage userInvestment = userInvestments[_params.user][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];
        userInvestment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        
        // [!] What to do here? in the case that _maxInvestableAmount changes, and user has already contributed
        // maybe will need helper function, etc
        // note that userInvestment.totalInvestedPaymentToken is incremented above so the below includes
        // both the previously invested amount as well as the current proposed investment amount
        userInvestment.pledgeDebt = _params.maxInvestableAmount - userInvestment.totalInvestedPaymentToken;
        
        investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        contractTotalInvestedPaymentToken += _params.thisInvestmentAmount;

        investment.paymentToken.transferFrom(msg.sender, address(this), _params.thisInvestmentAmount);

        emit UserContributionToInvestment(msg.sender, _params.user, _params.investmentId, _params.thisInvestmentAmount);

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
    
    function getUserInvestmentIds() public view returns (uint[] memory) {}
    function getTotalClaimedForInvestment() public view returns (uint) {}
    function computeUserTotalAllocationForInvesment() public view returns (uint) {}
    
    /**
        this will be a bit spicy - this will calculate claimable tokens, 
        based on users % share of allocation

        assumes that since they could invest, no further signature validation of the pledge amount is needed

        no checks for math yet, but this assumes that (totalTokensAllocated*userTotalInvestedPaymentToken)/totalInvestedPaymentToken
        will work, i.e. num >> denom, when assigning to userTotalClaimableTokens. if not, maybe will need to add 
        the case for num < denom. same thing for userContractBalanceClaimableTokens
     */

    function computeUserClaimableAllocationForInvestment(address sender, uint _investmentId) external view returns (uint) {
        return _computeUserClaimableAllocationForInvestment(sender, _investmentId);
    }

    /**
     * @dev private function to compute current amount claimable by user for an investment
     * @param _sender the address of the user claiming
     * @param _investmentId the id of the investment the user is claiming from
     * @notice contractTokenBalnce + totalTokensClaimed is used to preserve user's claimable balance regardless of order
     */

    function _computeUserClaimableAllocationForInvestment(address _sender, uint _investmentId) private view returns (uint) {
        
        uint totalInvestedPaymentToken = investments[_investmentId].totalInvestedPaymentToken;
        uint totalTokensClaimed = investments[_investmentId].totalTokensClaimed;
        uint userTotalInvestedPaymentToken = userInvestments[_sender][_investmentId].totalInvestedPaymentToken;
        uint userTokensClaimed = userInvestments[_sender][_investmentId].totalTokensClaimed;

        uint contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));
        uint userContractBalanceClaimableTokens = MathUpgradeable.mulDiv(contractTokenBalance+totalTokensClaimed, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
        uint userClaimableTokens = userContractBalanceClaimableTokens - userTokensClaimed;
        
        return userClaimableTokens;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    function investmentIsOpen(uint _investmentId, Phase _userPhase) external view returns (bool) {
        return _investmentIsOpen(_investmentId, _userPhase);
    }
    
    function _investmentIsOpen(uint _investmentId, Phase _userPhase) private view returns (bool) {
        return investments[_investmentId].contributionPhase.phase == _userPhase;
    }

    /// @dev private helpers for investChecks to avoid stack-too-deep errors...
    function _signatureCheck(InvestParams memory _params) private view returns (bool) {
        return SignatureCheckerUpgradeable.isValidSignatureNow(
                _params.signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(_params.user, _params.maxInvestableAmount, _params.userPhase))),
                _params.signature
        );
    }

    function _phaseCheck(InvestParams memory _params) private view returns (bool) {
        return _investmentIsOpen(_params.investmentId, _params.userPhase);
    }

    function _paymentTokenAllowanceCheck(InvestParams memory _params) private view returns (bool) {
        return investments[_params.investmentId].paymentToken.allowance(_params.user, address(this)) >= _params.thisInvestmentAmount;
    }
    
    function _contributionLimitCheck(InvestParams memory _params) private view returns (bool) {
        return _params.thisInvestmentAmount + userInvestments[_params.user][_params.investmentId].totalInvestedPaymentToken <= _params.maxInvestableAmount;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // ADMIN WRITE FUNCTIONS (ADD INVESTMENT, REMOVE INVESTMENT, MODIFY INVESTMENT, SET INVESTMENT PHASE 
    // ADD CONTRIBUTION MANUALLY, REFUND USER)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    /**
        For now, assuming MANAGER_ROLE will handle this all, and can be given to multiple addresses/roles
        @dev this function will be used to add a new investment to the contract
     */

    function addInvestment(
        address _signer,
        IERC20 _projectToken,
        uint _totalAllocatedPaymentToken
        // uint totalTokensAllocated
    ) public onlyRole(MANAGER_ROLE) {
        investments[++investmentId] = Investment({
            signer: _signer,
            contributionPhase: ContributionPhase({
                phase: Phase.CLOSED,
                startTime: 0,
                endTime: 0
            }),
            projectToken: IERC20(address(0)),
            paymentToken: _projectToken,
            totalInvestedPaymentToken: 0,
            totalAllocatedPaymentToken: _totalAllocatedPaymentToken,
            totalTokensClaimed: 0,
            totalTokensAllocated: 0
        });
        emit InvestmentAdded(investmentId);
    }

    function setInvestmentContributionPhase(uint _investmentId, Phase _investmentPhase) external onlyRole(MANAGER_ROLE) {
        investments[_investmentId].contributionPhase.phase = _investmentPhase;
    }

    function setInvestmentProjectTokenAddress(uint _investmentId, address projectTokenAddress) public onlyRole(MANAGER_ROLE) {
        investments[_investmentId].projectToken = IERC20(projectTokenAddress);
    }

    function setInvestmentProjectTokenAllocation(uint _investmentId, uint totalTokensAllocated) public onlyRole(MANAGER_ROLE) {
        investments[_investmentId].totalTokensAllocated = totalTokensAllocated;
    }

    function modifyInvestment() public onlyRole(MANAGER_ROLE) {}
    
    function setInvestmentPhase() public onlyRole(MANAGER_ROLE) {}

    /**
        @dev this function will be used to manually add contributions to an investment
     */
    function manualAddContribution() public onlyRole(MANAGER_ROLE) {}

    function refundUser() public onlyRole(MANAGER_ROLE) {}

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // TESTING - TO BE DELETED LATER
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