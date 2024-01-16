// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ILegacyTradeIn } from "./ILegacyTradeIn.sol";

contract LegacyTradeIn is ILegacyTradeIn, Ownable {
    address public burnAddress = address(0xdead);
    uint256 public start_time;
    uint256 public end_time;
    bool public paused = false;

    IERC721 public legacyNFT;

    constructor(address _legacyNFT, uint256 _start_time, uint256 _end_time) Ownable(msg.sender) {
        legacyNFT = IERC721(_legacyNFT);
        start_time = _start_time;
        end_time = _end_time;
    }

    modifier tradeInActive() {
        require(
            block.timestamp >= start_time && block.timestamp < end_time && !paused,
            "Trade-in not active"
        );
        _;
    }

    function tradeIn(uint256 _tokenId, bytes memory _userId) external tradeInActive {
        require(legacyNFT.ownerOf(_tokenId) == msg.sender, "Not the owner");
        legacyNFT.transferFrom(msg.sender, burnAddress, _tokenId);

        emit TradeInCompleted(_tokenId, _userId);
    }

    function setTradeInPhase(uint256 _start_time, uint256 _end_time) external onlyOwner {
        require(_start_time < _end_time, "Start time must be before end time");
        start_time = _start_time;
        end_time = _end_time;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}
