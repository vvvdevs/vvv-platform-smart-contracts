//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VVVNodes is ERC721, ERC721URIStorage {
    using SafeERC20 for IERC20;

    ///@notice Additional data for each token
    struct TokenData {
        //Remaining tokens to be vested, starts at 60% of $VVV initially locked in each node
        uint256 unvestedAmount;
        //timestamp of most recent token activation
        uint256 vestingSince;
        //claimable $VVV across vesting, transaction, and launchpad yield sources
        uint256 claimableAmount;
        //amount of $VVV to vest per second
        uint256 amountToVestPerSecond;
    }

    ///@notice The $VVV token used in node activation and yield accrual
    IERC20 public vvvToken;

    ///@notice The total number of nodes that can be minted
    uint256 public constant TOTAL_SUPPLY = 5000;

    ///@notice The current tokenId
    uint256 public tokenId;

    ///@notice Maps a TokenData struct to each tokenId
    mapping(uint256 => TokenData) public tokenData;

    ///@notice Thrown when the caller is not the owner of the token
    error CallerIsNotTokenOwner();

    ///@notice Thrown when a mint is attempted past the total supply
    error MaxSupplyReached();

    ///@notice Thrown when there are no claimable tokens for a node
    error NoClaimableTokens();

    constructor(address _vvvToken) ERC721("Multi-token Nodes", "NODES") {
        vvvToken = IERC20(_vvvToken);
    }

    ///@notice Mints a node to the recipient (placeholder)
    function mint(address _recipient) public {
        ++tokenId;
        if (tokenId > TOTAL_SUPPLY) revert MaxSupplyReached();

        //set user token data (testing!)
        TokenData storage token = tokenData[tokenId];
        token.unvestedAmount = 60_000 * 1e18;
        token.amountToVestPerSecond = 1e18;

        _mint(_recipient, tokenId);
    }

    ///@notice Allows a node owner to claim accrued yield
    function claim(uint256 _tokenId) public {
        if (msg.sender != ownerOf(_tokenId)) revert CallerIsNotTokenOwner();
        TokenData storage token = tokenData[_tokenId];

        _updateClaimableFromVesting(token);
        uint256 amountToClaim = token.claimableAmount;

        if (amountToClaim == 0) revert NoClaimableTokens();
        token.claimableAmount = 0;

        //update vestingSince to the current timestamp to maintain correct vesting calculations
        token.vestingSince = block.timestamp;

        vvvToken.safeTransfer(msg.sender, amountToClaim);
    }

    ///@notice Claims for all input tokenIds
    function batchClaim(uint256[] calldata _tokenIds) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            claim(_tokenIds[i]);
        }
    }

    ///@notice Sets token URI for token of tokenId (placeholder)
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

    ///@notice utilized in claiming and deactivation, updates the claimable tokens accumulated from vesting
    function _updateClaimableFromVesting(TokenData storage _tokenData) private {
        uint256 currentVestedAmount = _calculateVestedTokens(_tokenData);

        _tokenData.unvestedAmount -= currentVestedAmount;
        _tokenData.claimableAmount += currentVestedAmount;
    }

    ///@notice calculates vested tokens for a given tokenId since the last timestamp (vestingSince) update (does not account for claimed)
    function _calculateVestedTokens(TokenData memory _tokenData) private view returns (uint256) {
        uint256 vestingSince = _tokenData.vestingSince;

        //if node is inactive, return 0 (no vesting will occur between time of deactivation and time at which this function is called while the node is still inactive)
        if (!_isNodeActive(_tokenData)) return 0;

        uint256 totalUnvestedAmount = _tokenData.unvestedAmount;
        uint256 amountToVestPerSecond = _tokenData.amountToVestPerSecond;

        uint256 timeBasedVestingAmount = (block.timestamp - vestingSince) * amountToVestPerSecond;
        uint256 currentVestedAmount = totalUnvestedAmount > timeBasedVestingAmount
            ? timeBasedVestingAmount
            : totalUnvestedAmount;

        return currentVestedAmount;
    }

    ///@notice Returns whether node is active based on whether it's staked $VVV is above the activation threshold.
    //(placeholder for now)
    function _isNodeActive(TokenData memory _tokenData) private view returns (bool) {
        return true;
    }
}
