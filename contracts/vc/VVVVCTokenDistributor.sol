//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IVVVVCInvestmentLedger.sol";

contract VVVVCTokenDistributor is Ownable {
    IVVVVCInvestmentLedger public ledger;

    /// @notice Mapping of user's KYC address to project token address to investment round id to claimable token amount
    mapping(address => mapping(uint256 => uint256)) public userClaimedTokensForRound;

    /**
        @notice Parameters for claim function
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallets Array of addresses of the wallets from which the project token is to be claimed
        @param investmentRoundIds Array of investment round ids, corresponding to the project token claim from wallets
        @param claimableTokenAmounts Array of claimable token amounts, corresponding to the project token claim from wallets
        @param tokenAmountsToClaim Array of token amounts to be claimed, corresponding to the project token claim from wallets
        @param deadline Deadline for signature validity
        @param signature Signature of the user's KYC wallet address
     */
    struct ClaimParams {
        address userKycAddress;
        address projectTokenAddress;
        address[] projectTokenClaimFromWallets;
        uint256[] investmentRoundIds;
        uint256[] claimableTokenAmounts;
        uint256[] tokenAmountsToClaim;
        uint256 deadline;
        bytes signature;
    }

    /**
        @notice Emitted when a user claims tokens
        @param userKycAddress Address of the user's KYC wallet
        @param projectTokenAddress Address of the project token to be claimed
        @param projectTokenClaimFromWallet Address of the wallet from which the project token is to be claimed
        @param investmentRoundId Id of the investment round for which the claimable token amount is to be calculated
     */
    event VCClaim(
        address indexed userKycAddress,
        address indexed projectTokenAddress,
        address indexed projectTokenClaimFromWallet,
        uint256 investmentRoundId
    );

    /// @notice Emitted when the claim amount exceeds the allocation
    error ClaimExceedsAllocation();

    constructor(address _ledger) Ownable(msg.sender) {
        ledger = IVVVVCInvestmentLedger(_ledger);
    }

    function claim(ClaimParams memory _params) public {
        //check signature is valid (if this is valid, arrays should be same length)

        //PRELIM NOTES:
        //For each project token claim from wallet,
        //-->Calculate claimable amount
        //-->check desired claim amount is less or equal to than claimable amount
        //-->balance of proxy wallet N enough for claimAmount N? if low balance, revert (should happen without any check)
        for (uint256 i = 0; i < _params.projectTokenClaimFromWallets.length; ++i) {
            if (_params.tokenAmountsToClaim[i] > _params.claimableTokenAmounts[i]) {
                revert ClaimExceedsAllocation();
            }

            emit VCClaim(
                _params.userKycAddress,
                _params.projectTokenAddress,
                _params.projectTokenClaimFromWallets[i],
                _params.investmentRoundIds[i]
            );
        }
    }

    /**
        @notice Reads the VVVVCInvestmentLedger contract to calculate the claimable token amount
        @dev uses fraction of invested funds to determine fraction of claimable tokens
        @param _userKycAddress Address of the user's KYC wallet
        @param _projectTokenAddress Address of the project token to be claimed
        @param _investmentRound Id of the investment round for which the claimable token amount is to be calculated
     */
    function _calculateClaimableTokenAmount(
        address _userKycAddress,
        address _projectTokenAddress,
        uint256 _investmentRound
    ) internal view returns (uint256) {}
}
