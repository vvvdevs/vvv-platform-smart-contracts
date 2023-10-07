//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// Using Mock for now until branches merge and this contract can access the token and its interface
// import { IVVVToken } from "../interfaces/IVVVToken.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract LinearVestingWithLinearPenalty is Ownable {
    MockERC20 public token;

    address public immutable signer;

    uint256 public startTimestamp;
    uint256 public endTimestamp;
    uint256 public totalClaimed;
    uint256 public totalVestingTime;

    mapping(address => uint256) public claimedNominalTokens;
    mapping(address => uint256) public claimedActualTokens;
    mapping(address => uint256) public claimPenalty;

    error AmountIsGreaterThanClaimable();
    error InvalidConstructorArguments();
    error InvalidSignature();

    constructor(
        address _token,
        address _signer,
        uint256 _startTimestamp,
        uint256 _endTimestamp
    ) {
        if (
            _signer == address(0) ||
            _signer == address(this) ||
            _token == address(0) ||
            _startTimestamp > _endTimestamp
        ) {
            revert InvalidConstructorArguments();
        }

        signer = _signer;

        token = MockERC20(_token);
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        totalVestingTime = _endTimestamp - _startTimestamp;
    }

    /**
        @dev ex. If a user is awarded 100 nominal tokens and claims 25 actual tokens at t=0.5, at which time the nominal amount is 50. This leaves 50 nominal tokens to be claimed later. At t=1, these 50 nominal tokens will be equivalent to 50 actual tokens. So the user will have claimed a total of 75 actual tokens.
     */
    function claim(
        address _to,
        uint256 _claimAmount,
        uint256 _nominalTotalClaimable,
        bytes calldata _signature
    ) external {
        address sender = msg.sender;

        if (!_signatureCheck(sender, _nominalTotalClaimable, _signature)) {
            revert InvalidSignature();
        }

        if(_claimAmount > claimableNow(_nominalTotalClaimable, sender)) {
            revert AmountIsGreaterThanClaimable();
        }

        // register actual and equivalent nominal amount, i.e. if _claimAmount is 20 at t=0.5, then nominal amount is 40
        claimedActualTokens[sender] += _claimAmount;
        claimedNominalTokens[sender] += actualToNominal(_claimAmount);

        // mint tokens to _to
        token.mint(_to, _claimAmount);
    }

    function claimableNow(uint256 _nominalAmount, address _user) public view returns (uint256) {
        //equivalent to actual total available now - scaled total claimed (nominal claimed * vesting fraction)
        return nominalToActual(_nominalAmount - claimedNominalTokens[_user]);
    }

    function nominalToActual(uint256 _amount) public view returns (uint256) {
        return (_amount * elapsedVestingTime()) / totalVestingTime;
    }

    function actualToNominal(uint256 _amount) public view returns (uint256) {
        return (_amount * totalVestingTime) / elapsedVestingTime();
    }

    function elapsedVestingTime() public view returns (uint256) {
        return block.timestamp - startTimestamp;
    }

    /// @dev ensures signature is valid for input combo of account and total claimable
    function _signatureCheck(
        address _account,
        uint256 _nominalTotalClaimable,
        bytes calldata _signature
    ) private view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                signer,
                ECDSA.toEthSignedMessageHash(
                    keccak256(abi.encodePacked(_account, _nominalTotalClaimable, block.chainid))
                ),
                _signature
            );
    }
}
