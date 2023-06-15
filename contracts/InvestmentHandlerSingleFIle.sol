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
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
// import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract InvestmentHandlerSingleFile is 
    Initializable, 
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    //==================================================================================================
    // STORAGE & SETUP
    //==================================================================================================
    
    IERC20 USDC;
    IERC20 USDT;

    bytes32 MANAGER_ROLE;

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
        address projectToken;
        ContributionPhase contributionPhase;
        address signer; //or bytes32 root if using merkle tree
        string name;
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
        // uint investmentId;
        uint totalInvestedUsd;
        uint totalAllocatedUsd;
        uint totalTokensClaimed;
        uint totalTokensAllocated;
        uint[] tokenWithdrawalAmounts; //@curi0n-s are arrays the move for recording withdrawal amounts and timestamps here?
        uint[] tokenWithdrawalTimestamps;
    }

    mapping(uint => Investment) public investments;
    mapping(address => mapping(uint => UserInvestment)) public userInvestments;

    uint[48] __gap; // @curi0n-s reserve space for upgrade if needed?

    // Events
    event InvestmentAdded();
    event InvestmentRemoved();
    event InvestmentModified();
    event InvestmentPhaseSet();
    event AccessManagerSet();
    event SAFTWalletFactorySet();

    error ClaimAmountExceedsTotalClaimable();
    error InvestmentAmountExceedsMax();
    error InvestmentIsNotOpen();
    error InvalidSignature();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //==================================================================================================
    // INITIALIZATION & MODIFIERS
    //==================================================================================================
    
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        MANAGER_ROLE = keccak256("MANAGER_ROLE");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
        
        USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    }
    
    modifier claimChecks(uint investmentId, uint thisClaimAmount) {
        _computeUserClaimableAllocationForInvestment(msg.sender, investmentId, thisClaimAmount);
        _;
    }

    /**
        @dev checks to make sure user is able to investment the amount, at this time
            1. investment phase is open
            2. signature validates user max investable amount and address
            3. user investment amount + current proposed investment amount is less than max investable amount
        ???
            1. will users have to supply pledged amount in one txn? or can they contribute multiple times?
            2. consider the case where user contributes initial allocation, then allocation is increased
            3. could track "contribution debt" as a metric of whether the user follows thru on pledges of X amount
     */
    modifier investChecks(uint investmentId, uint maxInvestableAmount, uint thisInvestmentAmount, bytes memory signature) {
        if(_investmentIsOpen(investmentId, investments[investmentId].contributionPhase.phase)) {
            _;
        } else {
            revert InvestmentIsNotOpen();
        }        
        
        if(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                investments[investmentId].signer,
                ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(msg.sender, maxInvestableAmount))),
                signature
            )
        ) {
            _;
        } else {
            revert InvalidSignature();
        }

        if(thisInvestmentAmount + userInvestments[msg.sender][investmentId].totalAllocatedUsd <= maxInvestableAmount) {
            _;
        } else {
            revert InvestmentAmountExceedsMax();
        }
    }

    //==================================================================================================
    // USER WRITE FUNCTIONS (INVEST, CLAIM)
    //==================================================================================================
    
    function claim(uint investmentId, uint claimAmount) public claimChecks(investmentId, claimAmount) {
        //must add to total tokens claimed for investment
        //must add to user's total tokens claimed for investment
    }

    function invest(
        uint investmentId,
        uint maxInvestableAmount,
        uint thisInvestmentAmount,
        bytes calldata signature
    ) public investChecks(
        investmentId, 
        maxInvestableAmount,
        thisInvestmentAmount,
        signature
    ) {
        //must add to total invested usd for investment
        //must add to user's total invested usd for investment
        //adjusts user's contribution debt
    }

    //==================================================================================================
    // USER READ FUNCTIONS (USER INVESTMENTS, USER CLAIMABLE ALLOCATION, USER TOTAL ALLOCATION)
    //==================================================================================================
    
    function getUserInvestmentIds() public view returns (uint[] memory) {}
    function getTotalClaimedForInvestment() public view returns (uint) {}
    function computeUserTotalAllocationForInvesment() public view returns (uint) {}
    
    /**
        this will be a bit spicy - this will calculate claimable tokens, 
        based on users % share of allocation
     */

    function _computeUserClaimableAllocationForInvestment(address sender, uint investmentId, uint claimAmount) private view returns (uint) {
        
        /**
            project totals for invested usdc, total tokens allocated, user total invested usdc
         */
        uint totalInvestedUsd = investments[investmentId].totalInvestedUsd;
        uint totalTokensAllocated = investments[investmentId].totalTokensAllocated;
        uint userTotalInvestedUsd = userInvestments[sender][investmentId].totalInvestedUsd;
        uint userTokensClaimed = userInvestments[sender][investmentId].totalTokensClaimed;

        /**
            totalInvestedUsdc/userInvestedUsdc = totalTokensAllocated/userTotalClaimableTokens
            below solves for this

            may not be neccessary, can be used to make sure user has not exceeded their total claimable amount
         */
        uint userTotalClaimableTokens = MathUpgradeable.mulDiv(totalTokensAllocated, userTotalInvestedUsd, totalInvestedUsd);
        if(claimAmount + userTokensClaimed >= userTotalClaimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }

        /**
            user claimable tokens for current total deposited
         */
        uint contractTokenBalance = IERC20(investments[investmentId].projectToken).balanceOf(address(this));
        uint userContractBalanceClaimableTokens = MathUpgradeable.mulDiv(contractTokenBalance, userTotalInvestedUsd, totalInvestedUsd);

        /**
            user claimable tokens for current total deposited + claim amount
         */
        uint userClaimableTokens = userContractBalanceClaimableTokens - userTokensClaimed;
        
        return userClaimableTokens;
    }

    //==================================================================================================
    // INVESTMENT READ FUNCTIONS (INVESTMENT IS OPEN)
    //==================================================================================================

    function _investmentIsOpen(uint investmentId, Phase phase) private view returns (bool) {
        return investments[investmentId].contributionPhase.phase == phase;
    }

    //==================================================================================================
    // ADMIN WRITE FUNCTIONS (ADD INVESTMENT, REMOVE INVESTMENT, MODIFY INVESTMENT, SET INVESTMENT PHASE 
    // ADD CONTRIBUTION MANUALLY, REFUND USER)
    //==================================================================================================

    /**
        For now, assuming MANAGER_ROLE will handle this all, and can be given to multiple addresses
     */

    function addInvestment() public onlyRole(MANAGER_ROLE) {}
    function removeInvestment() public onlyRole(MANAGER_ROLE) {} // @curi0n-s should this be here?
    function modifyInvestment() public onlyRole(MANAGER_ROLE) {}
    function setInvestmentPhase() public onlyRole(MANAGER_ROLE) {}

    /**
        @dev this function will be used to manually add contributions to an investment
     */
    function manualAddContribution() public onlyRole(MANAGER_ROLE) {}

    function refundUser() public onlyRole(MANAGER_ROLE) {}

     
}