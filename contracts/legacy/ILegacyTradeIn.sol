// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILegacyTradeIn {
    event TradeInCompleted(uint256 tokenId, bytes userId);

    function tradeIn(uint256 _tokenId, bytes memory _userId) external;
    function setTradeInPhase(uint256 _start_time, uint256 _end_time) external;
    function setPaused(bool _paused) external;
}
