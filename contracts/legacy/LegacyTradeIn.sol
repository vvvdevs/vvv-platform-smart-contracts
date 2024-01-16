// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LegacyTradeIn is Ownable {
    address public burnAddress = address(0xdead);
    uint256 public start_time;
    uint256 public end_time;
    bool public paused = false;

    IERC721 public legacyNFT;

    event TradeInCompleted(uint256 tokenId, bytes userId);

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

    function tradeIn(uint256 tokenId, bytes memory userId) external tradeInActive {
        require(legacyNFT.ownerOf(tokenId) == msg.sender, "Not the owner");
        legacyNFT.transferFrom(msg.sender, burnAddress, tokenId);

        emit TradeInCompleted(tokenId, userId);
    }

    function setTradeInPhase(uint256 _start_time, uint256 _end_time) external onlyOwner {
        start_time = _start_time;
        end_time = _end_time;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}
