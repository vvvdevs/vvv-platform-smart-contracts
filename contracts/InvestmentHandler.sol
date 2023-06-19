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
    uint public investmentId; /// @dev global tracker for latest investment id
    uint public contractTotalInvestedUsd; /// @dev global tracker for total invested in contract (TESTING!)

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
        IERC20 stablecoin;
        // string name;
        uint totalInvestedUsd;
        uint totalAllocatedUsd;
        uint totalTokensClaimed;
        uint totalTokensAllocated;
    }

    struct ContributionPhase {
        Phase phase;
        uint startTime;
        uint endTime;
    }

    struct UserInvestment {
        uint totalInvestedUsd;
        uint pledgeDebt;
        uint totalTokensClaimed;
        uint[] tokenWithdrawalAmounts; //@curi0n-s are arrays the move for recording withdrawal amounts and timestamps here?
        uint[] tokenWithdrawalTimestamps;
    }

    /// @notice investmentId => investment
    mapping(uint => Investment) public investments;

    /// @notice user => investmentId => userInvestment
    mapping(address => mapping(uint => UserInvestment)) public userInvestments;

    uint[48] __gap; // @curi0n-s reserve space for upgrade if needed?

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
            3. user has approved spending of the investment amount in the desired stablecoin
            3. user investment amount + current proposed investment amount is less than max investable amount
        
            1. will users have to supply pledged amount in one txn? or can they contribute multiple times?
            2. consider the case where user contributes initial allocation, then allocation is increased
            3. could track "pledge debt" as a metric of whether the user follows thru on pledges of X amount
     */
    modifier investChecks(uint _investmentId, uint _maxInvestableAmount, uint _thisInvestmentAmount, bytes memory signature) {
        if(_investmentIsOpen(_investmentId, investments[_investmentId].contributionPhase.phase)) {
            _;
        } else {
            revert InvestmentIsNotOpen();
        }        
        
        if(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                investments[_investmentId].signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(msg.sender, _maxInvestableAmount))),
                signature
            )
        ) {
            _;
        } else {
            revert InvalidSignature();
        }

        if(
            investments[_investmentId].stablecoin.allowance(msg.sender, address(this)) >= _thisInvestmentAmount
        ) {
            _;
        } else {
            revert InsufficientAllowance();
        }

        if(_thisInvestmentAmount + userInvestments[msg.sender][_investmentId].totalInvestedUsd <= _maxInvestableAmount) {
            _;
        } else {
            revert InvestmentAmountExceedsMax();
        }
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
        @param _investmentId the id of the investment the user is investing in
        @param _maxInvestableAmount the max amount the user is allowed to invest in this investment
        @param _thisInvestmentAmount the amount the user is investing in this investment
        @param signature the signature of the user's address and max investable amount
        @notice adds to users total usd invested for investment + total usd in investment overall
        @notice adjusts user's pledge debt (pledged - contributed)
     */


    function invest(
        uint _investmentId,
        uint _maxInvestableAmount,
        uint _thisInvestmentAmount,
        bytes calldata signature
    ) public nonReentrant investChecks(
        _investmentId, 
        _maxInvestableAmount,
        _thisInvestmentAmount,
        signature
    ) {

        UserInvestment storage userInvestment = userInvestments[msg.sender][_investmentId];
        Investment storage investment = investments[_investmentId];

        userInvestment.totalInvestedUsd += _thisInvestmentAmount;
        userInvestment.pledgeDebt = _maxInvestableAmount - _thisInvestmentAmount;
        investment.totalInvestedUsd += _thisInvestmentAmount;

        contractTotalInvestedUsd += _thisInvestmentAmount;

        investment.stablecoin.transferFrom(msg.sender, address(this), _thisInvestmentAmount);

        emit UserContributionToInvestment(msg.sender, _investmentId, _thisInvestmentAmount);

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

        no checks for math yet, but this assumes that (totalTokensAllocated*userTotalInvestedUsd)/totalInvestedUsd
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
        uint totalInvestedUsd = investments[_investmentId].totalInvestedUsd;
        uint totalTokensAllocated = investments[_investmentId].totalTokensAllocated;
        uint userTotalInvestedUsd = userInvestments[sender][_investmentId].totalInvestedUsd;
        uint userTokensClaimed = userInvestments[sender][_investmentId].totalTokensClaimed;

        /**
            totalInvestedUsdc/userInvestedUsdc = totalTokensAllocated/userTotalClaimableTokens
            below solves for this

            may not be neccessary, can be used to make sure user has not exceeded their total claimable amount
         */
        uint userTotalClaimableTokens = MathUpgradeable.mulDiv(totalTokensAllocated, userTotalInvestedUsd, totalInvestedUsd);
        if(claimAmount + userTokensClaimed > userTotalClaimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        /**
            user claimable tokens for current total deposited
         */
        uint contractTokenBalance = investments[_investmentId].projectToken.balanceOf(address(this));
        uint userContractBalanceClaimableTokens = MathUpgradeable.mulDiv(contractTokenBalance, userTotalInvestedUsd, totalInvestedUsd);

        /**
            user claimable tokens for current total deposited + claim amount
         */
        uint userClaimableTokens = userContractBalanceClaimableTokens - userTokensClaimed;
        
        return userClaimableTokens;
    }

    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //V^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^VvV^

    function investmentIsOpne(uint _investmentId) external view returns (bool) {
        return _investmentIsOpen(_investmentId, investments[_investmentId].contributionPhase.phase);
    }
    
    function _investmentIsOpen(uint _investmentId, Phase phase) private view returns (bool) {
        return investments[_investmentId].contributionPhase.phase == phase;
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
        address signer,
        // IERC20 projectToken,
        bool isUsdc,
        uint totalAllocatedUsd
        // uint totalTokensAllocated
    ) public onlyRole(MANAGER_ROLE) {
        investments[++investmentId] = Investment({
            signer: signer,
            contributionPhase: ContributionPhase({
                phase: Phase.CLOSED,
                startTime: 0,
                endTime: 0
            }),
            projectToken: IERC20(address(0)),
            stablecoin: isUsdc ? USDC : USDT,
            totalInvestedUsd: 0,
            totalAllocatedUsd: totalAllocatedUsd,
            totalTokensClaimed: 0,
            totalTokensAllocated: 0
        });
        emit InvestmentAdded(investmentId);
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
    function checkSignature(address signer, address user, uint256 _maxInvestableAmount, bytes memory signature) public view returns (bool) {
        return(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(user, _maxInvestableAmount))),
                signature
            )
        );
    }

}