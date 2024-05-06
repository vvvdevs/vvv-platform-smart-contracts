//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVVVVCReadOnlyInvestmentLedger {
    function kycAddressInvestedRoots(uint256 _roundId) external view returns (bytes32);
    function totalInvestedPerRound(uint256 _roundId) external view returns (uint256);
    function getInvestmentRoots(uint256[] calldata _roundIds) external view returns (bytes32[] memory);
}
