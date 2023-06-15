//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
@title SAFTWalletFactory
@notice SAFTWalletFactory is a contract that creates SAFTWallet contracts for a given project. It is responsible for:
    1. Creating SAFTWallet contracts
    2. Setting initial permissions for who can interact with the SAFTWallet for a given investment                              
*/

/**
@curi0n-s initial notes for SAFTWalletFactory 
    1. all functions named
    2. all data structures and types (i.e. int vs bytes) agreed upon, no initial values defined for upgrade compatability (?)
    3. functions working
    4. tests written (unit, fuzzing, etc.)
    5. functions working + gas optimizations (data location, data type/packing, etc.)
    6. adding storage gaps to allocate some room for any potential future variables added in upgrades?
    7. more testing, auditing, more auditing, remediation, etc.
    -----
    8. InvestmentHandler will draw from AccessManager for permission checks, so no need to include AccessManager address in SAFTWallet cloning?
    9. Should this be Ownable? Thought only caller should be InvestmentHandler, but maybe some override needed sometimes?
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {SAFTWallet} from "./SAFTWallet.sol";

contract SAFTWalletFactory is Initializable {

    // Storage
    address walletImplementation;
    address investmentHandler;

    // Events
    event NewSaftWalletCreated(address saftWallet);

    // Errors
    error CallerIsNotInvestmentHandler();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialization + Modifiers
    function initialize() public initializer {
        walletImplementation = address(new SAFTWallet()); // @curi0n-s does this work? perhaps...
    }

    modifier callerIsInvestmentHandler() {
        if(msg.sender != investmentHandler){ revert CallerIsNotInvestmentHandler(); }
        _;
    }

    // Write Functions - Called by InvestmentHandler
    // @notice Deploys an ERC1167 clone of the SAFTWallet contract (which itself is not upgradeable)
    function createNewSaftWallet(
        address _projectToken,
        address _projectTokenDepositor,
        address _investmentHandler
    ) public callerIsInvestmentHandler returns (address) {
        address clone = ClonesUpgradeable.clone(walletImplementation);
        SAFTWallet(clone).initialize(_projectToken, _projectTokenDepositor, _investmentHandler);
        emit NewSaftWalletCreated(clone);
        return clone;
    }

}