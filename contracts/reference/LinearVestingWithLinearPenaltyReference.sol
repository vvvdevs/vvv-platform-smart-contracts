//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// Using Mock for now until branches merge and this contract can access the token and its interface
// import { IVVVToken } from "../interfaces/IVVVToken.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract LinearVestingWithLinearPenalty is Ownable {
    MockERC20 public token;

    address public immutable signer;

    uint256 public constant DENOMINATOR = 10000;

    /// @dev captures both X% at "TGE" and linear vesting for the Y% remaining after that
    struct VestingParams {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 nonPenalizedProportion; //X/10000
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

        @dev user can claim a percentage without this penalty according to their vesting params based on investment round

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

        //handle initial claimable amount calculation
        uint256 userNonPenalizedClaimableTotal = (_nominalTotalClaimable *
            investmentRoundToVestingParams[_investmentRound].nonPenalizedProportion) / DENOMINATOR;

        uint256 unpenalizedClaim;
        uint256 penalizedClaim;

        // handle unpenalized and penalized amounts and update claimed amounts
        unpenalizedClaim = userNonPenalizedClaimableTotal > claimedNominalTokens[sender]
            ? userNonPenalizedClaimableTotal - claimedNominalTokens[sender]
            : 0;
        
        penalizedClaim = _claimAmount > unpenalizedClaim ? _claimAmount - unpenalizedClaim : 0;
        claimedActualTokens[sender] += unpenalizedClaim + penalizedClaim;
        claimedNominalTokens[sender] +=
            unpenalizedClaim +
            actualToNominal(penalizedClaim, _investmentRound);

        // ensure user is not claiming more than they are allowed
        if(claimedNominalTokens[sender] > _nominalTotalClaimable){
            revert AmountIsGreaterThanClaimable();
        }

        // mint tokens to _to
        token.mint(_to, unpenalizedClaim + penalizedClaim);

        emit Claim(_to, _claimAmount, _nominalTotalClaimable, _investmentRound);
    }

    function nominalToActual(uint256 _amount, uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        uint256 totalVestingTime = thisVestingParams.endTimestamp - thisVestingParams.startTimestamp;
        return (_amount * elapsedVestingTime(_investmentRound)) / totalVestingTime;
    }

    function actualToNominal(uint256 _amount, uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        uint256 totalVestingTime = thisVestingParams.endTimestamp - thisVestingParams.startTimestamp;
        return (_amount * totalVestingTime) / elapsedVestingTime(_investmentRound);
    }

    ///@dev returns either the total vesting time or the time elapsed since vesting began if less than totalVestingTime
    function elapsedVestingTime(uint256 _investmentRound) public view returns (uint256) {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        if (block.timestamp >= thisVestingParams.endTimestamp) {
            return thisVestingParams.endTimestamp - thisVestingParams.startTimestamp;
        }
        return block.timestamp - thisVestingParams.startTimestamp;
    }

    function unpenalizedTokensForRound(uint256 _tokenAmount, uint256 _investmentRound)
        public
        view
        returns (uint256)
    {
        VestingParams memory thisVestingParams = investmentRoundToVestingParams[_investmentRound];
        return (_tokenAmount * thisVestingParams.nonPenalizedProportion) / DENOMINATOR;
    }

    /// @dev sets the vesting schedule for the round
    function setVestingParams(
        uint256 _investmentRound,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _nonPenalizedProportion
    ) external onlyOwner {
        investmentRoundToVestingParams[_investmentRound] = VestingParams(
            _startTimestamp,
            _endTimestamp,
            _nonPenalizedProportion
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