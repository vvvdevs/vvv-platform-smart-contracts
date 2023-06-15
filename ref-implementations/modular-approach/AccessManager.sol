//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
@title AccessManager
@author @vvvfund (@c0dejax, @kcper, @curi0n-s)
@notice AccessManager is a contract which manages access of users to both the invest and claim functions of InvestmentHandler
 */

/**
@curi0n-s initial notes for AccessManager 
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

import {MerkleProofUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

import {SignatureCheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";


contract AccessManager is Initializable, OwnableUpgradeable {
    using ECDSAUpgradeable for bytes32;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialization
    function initialize() public initializer {
        __Ownable_init();
    }

    // Permission Checks for Users of InvestmentHandler
    function checkIfUserCanClaim() public view returns (bool) {}
    function checkIfUserCanInvest() public view returns (bool) {}

    // If Needed, Permission Checks for Admins of InvestmentHandler

    // Internal or Private Functions for the Above
    function _plsHelpMeLol() private view returns (bool) {}

}