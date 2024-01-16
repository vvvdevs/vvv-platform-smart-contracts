// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { LegacyTradeInBase } from "./LegacyTradeInTestBase.sol";

contract LegacyTradeInFuzzTests is LegacyTradeInBase {
    function setUp() public override {
        super.setUp();
        vm.startPrank(user1);
        legacyNFTInstance.setApprovalForAll(address(LegacyTradeInInstance), true);
        vm.stopPrank();
    }

    function testFuzz_TradeInWithVaryingTokenIds(uint256 tokenId) public {
        vm.startPrank(user1);
        tokenId = bound(tokenId, 10, 10000);

        legacyNFTInstance.mint(user1, tokenId);

        tradeInAsUser(user1, tokenId);
        vm.stopPrank();

        assertEq(
            legacyNFTInstance.ownerOf(tokenId),
            burnAddress,
            "NFT should be transferred to burn address"
        );
    }

    function testFuzz_TradeInWithVaryingTimestamps(uint256 timestamp) public {
        timestamp = bound(timestamp, startTime, endTime);

        uint256 tokenId = 10;
        legacyNFTInstance.mint(user1, tokenId);

        vm.warp(timestamp);
        if (timestamp >= startTime && timestamp < endTime && !LegacyTradeInInstance.paused()) {
            tradeInAsUser(user1, tokenId);
            assertEq(
                legacyNFTInstance.ownerOf(tokenId),
                burnAddress,
                "NFT should be transferred to burn address"
            );
        } else {
            vm.startPrank(user1);
            vm.expectRevert("Trade-in not active");
            LegacyTradeInInstance.tradeIn(tokenId, "user-id");
            vm.stopPrank();
        }
    }
}
