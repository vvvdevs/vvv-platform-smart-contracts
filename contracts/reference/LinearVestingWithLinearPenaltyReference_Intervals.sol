//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// Using Mock for now until branches merge and this contract can access the token and its interface
// import { IVVVToken } from "../interfaces/IVVVToken.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract LinearVestingWithLinearPenalty_Intervals is Ownable {
    MockERC20 public token;

    address public immutable signer;

    uint256 public constant DENOMINATOR = 10000;

    /// @dev captures both X% at cliff and linear vesting for the Y% remaining after that
    struct VestingParams {
        uint256 startTimestamp;
        uint256 vestingIntervalDuration;
        uint256 totalVestingIntervals;
        uint256 intervalsBeforeCliff;
    }

    mapping(address => uint256) public claimedNominalTokens;
    mapping(address => uint256) public claimedActualTokens;
    mapping(uint256 => VestingParams) public investmentRoundToVestingParams;

    event Claim(
        address indexed _to,
        uint256 _amount,
        uint256 _nominalTotalClaimable,
        uint256 _investmentRound
    );

    error AmountIsGreaterThanClaimable();
    error InvalidConstructorArguments();
    error InvalidSignature();

    constructor(address _token, address _signer) Ownable(msg.sender) {
        if (_signer == address(0) || _signer == address(this) || _token == address(0)) {
            revert InvalidConstructorArguments();
        }

        signer = _signer;
        token = MockERC20(_token);
    }

    /**
        @dev ex. If a user is awarded 100 nominal tokens and claims 25 actual tokens at t=0.5, at which time the nominal amount is 50. This leaves 50 nominal tokens to be claimed later. At t=1, these 50 nominal tokens will be equivalent to 50 actual tokens. So the user will have claimed a total of 75 actual tokens.

        @param _to address to mint tokens to
        @param _claimAmount amount of tokens to claim (actual terms)
        @param _nominalTotalClaimable total amount of tokens claimable by user (nominal terms)
        @param _investmentRound investment round to use for vesting params
        @param _signature signature of the user's address, total claimable amount, and investment round
     */
    function claim(
        address _to,
        uint256 _claimAmount,
        uint256 _nominalTotalClaimable,
        uint256 _investmentRound,
        bytes calldata _signature
    ) external {
        address sender = msg.sender;

        if (!_signatureCheck(sender, _nominalTotalClaimable, _investmentRound, _signature)) {
            revert InvalidSignature();
        }

        claimedActualTokens[sender] += _claimAmount;
        claimedNominalTokens[sender] += actualToNominal(_claimAmount, _investmentRound);

        // ensure user is not claiming more than they are allowed
        if(claimedNominalTokens[sender] > _nominalTotalClaimable){
            revert AmountIsGreaterThanClaimable();
        }

        //check balance as of this vesting interval
        if(_claimAmount > vestedTokensNow(_investmentRound, _nominalTotalClaimable)){
            revert AmountIsGreaterThanClaimable();
        }

        // mint tokens to _to
        // or transfer contract token balance and burn the penalty amount
        // could instead burn all at the end
        token.mint(_to, _claimAmount);

        emit Claim(_to, _claimAmount, _nominalTotalClaimable, _investmentRound);
    }

    function nominalToActual(uint256 _amount, uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        return (_amount * currentVestingInterval(_investmentRound)) / thisVestingParams.totalVestingIntervals;
    }

    function actualToNominal(uint256 _amount, uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        return (_amount * thisVestingParams.totalVestingIntervals) / currentVestingInterval(_investmentRound);
    }

    ///@dev returns either the total vesting time or the time elapsed since vesting began if less than totalVestingTime
    function currentVestingInterval(uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];

        uint256 currentInterval = (block.timestamp - thisVestingParams.startTimestamp) / thisVestingParams.vestingIntervalDuration;

        if (currentInterval >= thisVestingParams.totalVestingIntervals) {
            return thisVestingParams.totalVestingIntervals;
        } else {
            return currentInterval + 1;
        }
        
    }

    /// @dev incorporates the vesting interval to calculate the amount of tokens vested at the current time (interval), also accounting for cliff
    function vestedTokensNow(uint256 _investmentRound, uint256 _nominalTotalClaimable) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];

        //should this be +1? distinguish elapsed intervals from current
        //consider during first interval, elapsed = 0, current = 1
        uint256 thisInterval = currentVestingInterval(_investmentRound);

        //still < cliff
        if (thisInterval < thisVestingParams.intervalsBeforeCliff) {
            return 0;

        //after cliff, split (total - cliff) amount into remaining intervals, then multiply by elapsed post-cliff intervals    
        } else {
            uint256 cliffAmount = (_nominalTotalClaimable * thisVestingParams.intervalsBeforeCliff) / thisVestingParams.totalVestingIntervals;
            uint256 remainingAmount = _nominalTotalClaimable - cliffAmount;
            uint256 vestedAmount = (remainingAmount * (thisInterval - thisVestingParams.intervalsBeforeCliff)) /
                (thisVestingParams.totalVestingIntervals - thisVestingParams.intervalsBeforeCliff);

            return cliffAmount + vestedAmount;
        }

    }
    

    /// @dev sets the vesting schedule for the round
    function setVestingParams(
        uint256 _investmentRound,
        uint256 _startTimestamp,
        uint256 _vestingIntervalDuration,
        uint256 _totalVestingIntervals,
        uint256 _intervalsBeforeCliff
    ) external onlyOwner {
        investmentRoundToVestingParams[_investmentRound] = VestingParams(
            _startTimestamp,
            _vestingIntervalDuration,
            _totalVestingIntervals,
            _intervalsBeforeCliff
        );
    }

    /// @dev ensures signature is valid for input combo of account and total claimable
    function _signatureCheck(
        address _account,
        uint256 _nominalTotalClaimable,
        uint256 _investmentRound,
        bytes calldata _signature
    ) private view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                signer,
                MessageHashUtils.toEthSignedMessageHash(
                    keccak256(
                        abi.encodePacked(_account, _nominalTotalClaimable, _investmentRound, block.chainid)
                    )
                ),
                _signature
            );
    }
}