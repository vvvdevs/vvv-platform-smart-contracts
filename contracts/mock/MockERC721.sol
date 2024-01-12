// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MyToken is ERC721 {
    uint256 public tokenId;

    constructor() ERC721("MyToken", "MTK") {}

    function safeMint(address to) public {
        ++tokenId;
        _safeMint(to, tokenId);
    }
}
