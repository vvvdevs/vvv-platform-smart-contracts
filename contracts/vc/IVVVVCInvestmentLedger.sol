//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVVVVCInvestmentLedger {
    function kycAddressInvestedPerRound(
        address _kycAddress,
        uint256 _roundId
    ) external view returns (uint256);

    function totalInvestedPerRound(uint256 _roundId) external view returns (uint256);
}
