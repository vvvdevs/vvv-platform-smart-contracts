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
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {ISAFTWalletFactory} from "./interfaces/ISAFTWalletFactory.sol";

contract InvestmentHandler is Initializable, OwnableUpgradeable {

    //Storage
    IAccessManager public accessManager;
    ISAFTWalletFactory public saftWalletFactory;

    enum Phase {
        CLOSED,
        WHALE,
        SHARK,
        FCFS
    } 

    struct Investment {
        uint id;
        string name;
        AllocationPhase allocationPhase;
        bytes32 root;
        uint totalAllocation;
        uint totalAllocationLimit; /// @curi0n-s what does this signify again?
        uint totalClaimed;
    }

    struct AllocationPhase {
        Phase phase;
        uint startTime;
        uint endTime;
    }

    struct ClaimWithdrawal {
        uint investmentId;
        uint amount;
        uint timestamp;
    }

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
    }
    
    modifier claimChecks() {
        // accessManager.checkIfUserCanClaim();
        _;
    }

    modifier investChecks() {
        // accessManager.checkIfUserCanInvest();
        _;
    }

    // User Write Functions
    function claimAllocation() public claimChecks() {}
    function invest() public investChecks() {}

    // User Read Functions
    function getUserInvestmentIds() public view returns (uint[] memory) {}
    function getTotalClaimedForInvestment() public view returns (uint) {}
    function computeUserTotalAllocationForInvesment() public view returns (uint) {}

    // Admin Write Functions
    function addInvestment() public {}
    function removeInvestment() public {} // @curi0n-s should this be here?
    function modifyInvestment() public {}
    function setInvestmentPhase() public {}
    function setAccessManager() public {}
    function setSAFTWalletFactory() public {}
     
}