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

    IERC20 USDC;
    IERC20 USDT;

    address public deployer;
    bytes32 public MANAGER_ROLE;
    
    /// @dev global tracker for latest investment id
    uint public investmentId; 
    
    /// @dev global tracker for total invested in contract (TESTING!)
    uint public contractTotalInvestedPaymentToken; 

    /// @curi0n-s are enums extensible?
    enum Phase {
        CLOSED,
        WHALE,
        SHARK,
        FCFS
    } 

    /**
        @curi0n-s adding everything discussed so far here,
        likely we can remove what isn't needed later, 
        so adding all options I can think of for now

        investment IDs may not be necessary in the struct,
        since this will be the index used to get the struct
        in the first place

        def open to new approaches on how to best structure this,
        for example will we ID investments by uint, project token address, or other?

     */

    struct Investment {
        // uint id;
        address signer; //or bytes32 root if using merkle tree
        ContributionPhase contributionPhase;
        IERC20 projectToken;
        IERC20 paymentToken;
        // string name;
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
    
    // @curi0n-s reserve space for upgrade if needed?
    uint[48] __gap; 

    // Events
    event InvestmentAdded(uint indexed _investmentId);
    event InvestmentRemoved();
    event InvestmentModified();
    event InvestmentPhaseSet();
    event UserContributionToInvestment(address indexed user, uint indexed _investmentId, uint amount);
    event UserTokenClaim(address indexed user, uint indexed _investmentId, uint amount);

    error ClaimAmountExceedsTotalClaimable();
    error InsufficientAllowance();
    error InvestmentAmountExceedsMax();
    error InvestmentIsNotOpen();
    error InvalidSignature();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INITIALIZATION & MODIFIERS
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    
    function initialize(address _usdc, address _usdt) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        deployer = msg.sender;
        MANAGER_ROLE = keccak256("MANAGER_ROLE");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
        
        USDC = IERC20(_usdc);//IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        USDT = IERC20(_usdt);//IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    }
    
    modifier claimChecks(uint _investmentId, uint thisClaimAmount) {
        _computeUserClaimableAllocationForInvestment(msg.sender, _investmentId, thisClaimAmount);
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
        @dev this function will be called by the user to claim their tokens
        @param _investmentId the id of the investment the user is claiming from
        @param claimAmount the amount the user is claiming from the investment
        @notice adds to users total tokens claimed for investment
        @notice adds to total tokens claimed for investment
     */
    
    function claim(uint _investmentId, uint claimAmount) public claimChecks(_investmentId, claimAmount) {
        UserInvestment storage userInvestment = userInvestments[msg.sender][_investmentId];
        Investment storage investment = investments[_investmentId];

        userInvestment.totalTokensClaimed += claimAmount;
        investment.totalTokensClaimed += claimAmount;

        investment.projectToken.transfer(msg.sender, claimAmount);

        emit UserTokenClaim(msg.sender, _investmentId, claimAmount);
    }

    /**
        @dev this function will be called by the user to invest in the project
        @param _params the parameters for the investment as specified in InvestParams
        @notice adds to users total usd invested for investment + total usd in investment overall
        @notice adjusts user's pledge debt (pledged - contributed

     */

    function invest(
        InvestParams memory _params
    ) public nonReentrant investChecks(_params) {

        UserInvestment storage userInvestment = userInvestments[_params.user][_params.investmentId];
        Investment storage investment = investments[_params.investmentId];
        userInvestment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        // What to do here? in the case that _maxInvestableAmount changes, and user has already contributed
        // likely will need different approach or helper function or something
        userInvestment.pledgeDebt = _params.maxInvestableAmount - _params.thisInvestmentAmount;
        investment.totalInvestedPaymentToken += _params.thisInvestmentAmount;
        contractTotalInvestedPaymentToken += _params.thisInvestmentAmount;

        investment.paymentToken.transferFrom(msg.sender, address(this), _params.thisInvestmentAmount);

        emit UserContributionToInvestment(_params.user, _params.investmentId, _params.thisInvestmentAmount);

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

    function computeUserClaimableAllocationForInvestment(address sender, uint _investmentId, uint claimAmount) external view returns (uint) {
        return _computeUserClaimableAllocationForInvestment(sender, _investmentId, claimAmount);
    }

    function _computeUserClaimableAllocationForInvestment(address sender, uint _investmentId, uint claimAmount) private view returns (uint) {
        
        /**
            project totals for invested usdc, total tokens allocated, user total invested usdc
         */
        uint totalInvestedPaymentToken = investments[_investmentId].totalInvestedPaymentToken;
        uint totalTokensAllocated = investments[_investmentId].totalTokensAllocated;
        uint userTotalInvestedPaymentToken = userInvestments[sender][_investmentId].totalInvestedPaymentToken;
        uint userTokensClaimed = userInvestments[sender][_investmentId].totalTokensClaimed;

        /**
            TotalInvestedPaymentTokenc/userInvestedUsdc = totalTokensAllocated/userTotalClaimableTokens
            below solves for this

            may not be neccessary, can be used to make sure user has not exceeded their total claimable amount
         */
        uint userTotalClaimableTokens = MathUpgradeable.mulDiv(totalTokensAllocated, userTotalInvestedPaymentToken, totalInvestedPaymentToken);
        if(claimAmount + userTokensClaimed > userTotalClaimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        /**
            user claimable tokens for current total deposited
         */
        uint contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));
        uint userContractBalanceClaimableTokens = MathUpgradeable.mulDiv(contractTokenBalance, userTotalInvestedPaymentToken, totalInvestedPaymentToken);

        /**
            user claimable tokens for current total deposited + claim amount
         */
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