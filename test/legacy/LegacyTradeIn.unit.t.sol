// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { LegacyTradeInBase } from "./LegacyTradeInTestBase.sol";

contract LegacyTradeInUnitTests is LegacyTradeInBase {
    function setUp() public override {
        super.setUp();
    }

    function testTradeInNFTSuccess() public {
        uint256 tokenId = 1;
        vm.startPrank(user1);
        legacyNFTInstance.setApprovalForAll(address(LegacyTradeInInstance), true);
        tradeInAsUser(user1, tokenId);

        assertEq(
            legacyNFTInstance.ownerOf(tokenId),
            burnAddress,
            "NFT should be transferred to burn address"
        );
        vm.stopPrank();
    }

    function testTradeInNFTWhenNotOwner() public {
        uint256 tokenId = 1;
        vm.startPrank(user2);
        vm.expectRevert("Not the owner");
        LegacyTradeInInstance.tradeIn(tokenId, "user-id");
        vm.stopPrank();
    }

    function testTradeInNFTWhenPaused() public {
        setPaused(true);
        uint256 tokenId = 1;
        vm.startPrank(user1);
        vm.expectRevert("Trade-in not active");
        LegacyTradeInInstance.tradeIn(tokenId, "user-id");
        vm.stopPrank();
    }

    function testTradeInNFTOutsideActivePeriod() public {
        uint256 tokenId = 1;
        setTradeInPhase(block.timestamp + 1 days, block.timestamp + 2 days);

        vm.startPrank(user1);
        vm.expectRevert("Trade-in not active");
        LegacyTradeInInstance.tradeIn(tokenId, "user-id");
        vm.stopPrank();
    }

    function testSetTradeInPhase() public {
        uint256 newStartTime = block.timestamp + 1 days;
        uint256 newEndTime = newStartTime + 30 days;

        vm.startPrank(deployer);
        LegacyTradeInInstance.setTradeInPhase(newStartTime, newEndTime);
        vm.stopPrank();

        assertEq(LegacyTradeInInstance.start_time(), newStartTime, "Start time should be updated");
        assertEq(LegacyTradeInInstance.end_time(), newEndTime, "End time should be updated");
    }

    function testSetPaused() public {
        setPaused(true);
        assertTrue(LegacyTradeInInstance.paused(), "Contract should be paused");

        setPaused(false);
        assertFalse(LegacyTradeInInstance.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function testSetPausedNotOwner() public {
        vm.expectRevert();
        LegacyTradeInInstance.setPaused(true);
    }

    function setPaused(bool _paused) internal {
        vm.startPrank(deployer);
        LegacyTradeInInstance.setPaused(_paused);
        vm.stopPrank();
    }

    function setTradeInPhase(uint256 _start_time, uint256 _end_time) internal {
        vm.startPrank(deployer);
        LegacyTradeInInstance.setTradeInPhase(_start_time, _end_time);
        vm.stopPrank();
    }
}
