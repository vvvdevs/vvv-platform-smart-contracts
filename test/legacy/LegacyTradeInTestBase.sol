// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "lib/forge-std/src/Test.sol";
import { LegacyNFTTradeIn } from "contracts/legacy/LegacyTradeIn.sol";
import { MyToken } from "contracts/mock/MockERC721.sol";

contract LegacyTradeInBase is Test {
    MyToken public legacyNFTInstance;
    LegacyNFTTradeIn public legacyNFTTradeInInstance;

    address public deployer = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public burnAddress = address(0xdead);

    uint256 public startTime = block.timestamp;
    uint256 public endTime = block.timestamp + 30 days;

    function setUp() public virtual {
        vm.startPrank(deployer);
        legacyNFTInstance = new MyToken();
        legacyNFTTradeInInstance = new LegacyNFTTradeIn(address(legacyNFTInstance), startTime, endTime);

        legacyNFTInstance.safeMint(user1);
        legacyNFTInstance.safeMint(user2);
        vm.stopPrank();
    }

    function tradeInAsUser(address user, uint256 tokenId) internal {
        vm.startPrank(user);
        legacyNFTTradeInInstance.tradeIn(tokenId, "user-id");
        vm.stopPrank();
    }
}
