//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

/**
 * @title VVV VC Reward Token
 * @notice This contract represents soulbound ERC-721 tokens for VVV VC investment rewards
 * @dev Tokens are soulbound and cannot be transferred after minting
 */
contract VVVVCRewardToken is ERC721, VVVAuthorizationRegistryChecker {
    using Strings for uint256;

    /// @notice The current token ID counter
    uint256 public currentTokenId;

    /// @notice Mapping from token ID to investment round
    mapping(uint256 => uint256) public tokenIdToInvestmentRound;

    /// @notice The base URI for token metadata
    string public baseTokenURI;

    /// @notice Event emitted when a reward token is minted
    /// @param tokenId The ID of the minted token
    /// @param recipient The address receiving the token
    /// @param investmentRound The investment round associated with the token
    event RewardTokenMinted(
        uint256 indexed tokenId,
        address indexed recipient,
        uint256 indexed investmentRound
    );

    /// @notice Event emitted when the base token URI is changed
    /// @param newBaseTokenURI The new base URI
    event BaseTokenURISet(string newBaseTokenURI);

    /// @notice Error thrown when a transfer is attempted on a soulbound token
    error TokenIsSoulbound();

    /**
     * @notice Constructor for the VVV VC Reward Token
     * @param _authorizationRegistryAddress The address of the authorization registry
     */
    constructor(
        address _authorizationRegistryAddress
    ) ERC721("REWARD", "REWARD") VVVAuthorizationRegistryChecker(_authorizationRegistryAddress) {}

    /**
     * @notice Mints a new reward token to the specified recipient
     * @param _recipient The address to receive the token
     * @param _investmentRound The investment round ID tied to an investment transaction
     * @dev Only authorized addresses can call this function
     */
    function mint(address _recipient, uint256 _investmentRound) external onlyAuthorized {
        ++currentTokenId;
        tokenIdToInvestmentRound[currentTokenId] = _investmentRound;
        _safeMint(_recipient, currentTokenId);
        emit RewardTokenMinted(currentTokenId, _recipient, _investmentRound);
    }

    /**
     * @notice Sets the base URI for all token metadata
     * @param _baseTokenURI The new base URI
     * @dev Only authorized addresses can call this function
     */
    function setBaseTokenURI(string calldata _baseTokenURI) external onlyAuthorized {
        baseTokenURI = _baseTokenURI;
        emit BaseTokenURISet(_baseTokenURI);
    }

    /**
     * @notice Override of _update to prevent transfers (soulbound)
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        // Block transfers (but allow mint)
        if (from != address(0)) {
            revert TokenIsSoulbound();
        }
        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Prevent approvals to block listing on marketplaces
     */
    function setApprovalForAll(address, bool) public pure override {
        revert TokenIsSoulbound();
    }

    function approve(address, uint256) public pure override {
        revert TokenIsSoulbound();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }
}
