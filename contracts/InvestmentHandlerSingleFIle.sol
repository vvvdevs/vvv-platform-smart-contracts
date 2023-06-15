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
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
// import {IAccessManager} from "./interfaces/IAccessManager.sol";
// import {ISAFTWalletFactory} from "./interfaces/ISAFTWalletFactory.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract InvestmentHandlerSingleFile is 
    Initializable, 
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using StringsUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ECDSAUpgradeable for bytes32;

    //Storage
    IAccessManager public accessManager;
    ISAFTWalletFactory public saftWalletFactory;
    IERC20 USDC;
    IERC20 USDT;

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
        AllocationPhase allocationPhase;
        bytes32 root; //or bytes32 signature if using ECDSA signatures
        string name;
        uint totalInvestedUsd;
        uint totalAllocatedUsd;
        uint totalTokensClaimed;
        uint totalTokensAllocated;
    }

    struct AllocationPhase {
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
    error InvestmentIsNotOpen();
    error InvalidSignature();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialization + Modifiers
    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
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
     */
    modifier investChecks(uint investmentId, uint maxInvestableAmount, uint thisInvestmentAmount, bytes memory sig) {
        if(investmentIsOpen(investmentId, phase)) {
            _;
        } else {
            revert InvestmentIsNotOpen();
        }        
        
        if(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                project.signer,
                keccak256(abi.encodePacked(msg.sender, maxInvestableAmount))
                    .toEthSignedMessageHash(),
                sig
            )
        ) {
            _;
        } else {
            revert InvalidSignature();
        }

        if(thisInvestmentAmount + userInvestments[msg.sender][investmentId] <= maxInvestableAmount) {
            _;
        } else {
            revert InvestmentAmountExceedsMax();
        }
    }

    // User Write Functions
    function claimAllocation() public claimChecks() {
        //must add to total tokens claimed for investment
        //must add to user's total tokens claimed for investment
    }
    function invest() public investChecks() {}

    // User Read Functions
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
        uint totalInvestedUsdc = investments[investmentId].totalInvestedUsdc;
        uint totalTokensAllocated = investments[investmentId].totalTokensAllocated;
        uint userTotalInvestedUsdc = userInvestments[sender][investmentId].totalInvestedUsdc;
        uint userTokensClaimed = userInvestments[sender][investmentId].totalTokensClaimed;

        /**
            totalInvestedUsdc/userInvestedUsdc = totalTokensAllocated/userTotalClaimableTokens
            below solves for this

            may not be neccessary, can be used to make sure user has not exceeded their total claimable amount
         */
        uint userTotalClaimableTokens = Math.mulDiv(totalTokensAllocated, userTotalInvestedUsdc, totalInvestedUsdc);
        if(claimAmount + userTokensClaimed >= userTotalClaimableTokens) {
            revert ClaimAmountExceedsTotalClaimable();
        }
        /**
            user claimable tokens for current total deposited
         */
        uint contractTokenBalance = IERC20(investments[investmentId].projectToken).balanceOf(address(this));
        uint userContractBalanceClaimableTokens = Math.mulDiv(contractTokenBalance, userTotalInvestedUsdc, totalInvestedUsdc);

        /**
            user claimable tokens for current total deposited + claim amount
         */
        uint userClaimableTokens = userContractbalanceClaimableTokens - userTokensClaimed;
        
        return userClaimableTokens;
    }

    // Admin Write Functions
    function addInvestment() public {}
    function removeInvestment() public {} // @curi0n-s should this be here?
    function modifyInvestment() public {}
    function setInvestmentPhase() public {}

    function setRefundsAreOpen() public {}

    /**
        @dev this function will be used to manually add contributions to an investment
     */
    function manualAddContribution() public {}

    function setAccessManager() public {}
    function setSAFTWalletFactory() public {}
     
}