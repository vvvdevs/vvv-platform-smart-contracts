//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract VVVNodes is ERC721, ERC721URIStorage {
    ///@notice The total number of nodes that can be minted
    uint256 public constant TOTAL_SUPPLY = 5000;

    ///@notice The current tokenId
    uint256 public tokenId;

    ///@notice Thrown when a mint is attempted past the total supply
    error MaxSupplyReached();

    constructor() ERC721("Multi-token Nodes", "NODES") {}

    ///@notice Mints a node to the recipient
    function mint(address _recipient) public {
        ++tokenId;
        if (tokenId > TOTAL_SUPPLY) revert MaxSupplyReached();

        _mint(_recipient, tokenId);
    }

    ///@notice sets token URI for token of tokenId
    function setTokenURI(uint256 _tokenId, string calldata _tokenURI) public {
        _setTokenURI(_tokenId, _tokenURI);
    }

    ///@notice Returns the tokenURI for the given tokenId, required override
    function tokenURI(
        uint256 _tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(_tokenId);
    }

    ///@notice Returns whether the given interfaceId is supported, required override
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }
}
