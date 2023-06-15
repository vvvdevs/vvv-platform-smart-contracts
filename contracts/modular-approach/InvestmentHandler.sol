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
    5. Allowing admins to set the access manager
    6. Allowing admins to set the SAFT wallet factory
*/

/**
@curi0n-s initial notes for InvestmentHandler (trying to always put my username before notes so you know who to bother)
    1. all functions named
    2. all data structures and types (i.e. int vs bytes) agreed upon, no initial values defined for upgrade compatability (?)
    3. functions working
    4. tests written (unit, fuzzing, etc.)
    5. functions working + gas optimizations (data location, data type/packing, etc.)
    6. adding storage gaps to allocate some room for any potential future variables added in upgrades?
    7. more testing, auditing, more auditing, remediation, etc.

FEATURES:
1. ECDSA vs Merkle
2. Manual Add of investors in addition to validation stragegy from (1)
3. 1 claim of full % of allocation per vesting period? i.e. if 10%/month vesting,
    user can only claim 10% of their allocation per month. otherwise, can claim later, as they accumulate.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IAccessManager} from "../interfaces/IAccessManager.sol";
import {ISAFTWalletFactory} from "../interfaces/ISAFTWalletFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract InvestmentHandler is 
    Initializable, 
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using StringsUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
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

    uint256[48] __gap; // @curi0n-s reserve space for upgrade if needed?

    // Events
    event InvestmentAdded();
    event InvestmentRemoved();
    event InvestmentModified();
    event InvestmentPhaseSet();
    event AccessManagerSet();
    event SAFTWalletFactorySet();

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
    
    modifier claimChecks() {
        // accessManager.checkIfUserCanClaim();
        _computeUserClaimableAllocationForInvestment();
        _;
    }

    modifier investChecks() {
        // accessManager.checkIfUserCanInvest();
        // @curi0n-s check if amount attempted to invest is <= user limit from merkle tree for this investment
        _;
    }

    // User Write Functions

    function claimAllocation() public claimChecks() {}
    function invest() public investChecks() {}

    // User Read Functions
    function getUserInvestmentIds() public view returns (uint[] memory) {}
    function getTotalClaimedForInvestment() public view returns (uint) {}
    function computeUserTotalAllocationForInvesment() public view returns (uint) {}

    /**
        this will be a bit spicy - this will calculate claimable tokens 
        based on users % share of allocation, as well as
        tokens deposited into project saft wallet during the last vesting period (i.e. a month)
     */

    function _computeUserClaimableAllocationForInvestment() private view returns (uint) {}

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