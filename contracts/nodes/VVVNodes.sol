//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

contract VVVNodes is ERC721, VVVAuthorizationRegistryChecker {
    using SafeERC20 for IERC20;

    ///@notice Additional data for each token
    struct TokenData {
        uint256 unvestedAmount; //Remaining tokens to be vested, starts at 60% of $VVV initially locked in each node
        uint256 vestingSince; //timestamp of most recent token activation or claim
        uint256 claimableAmount; //claimable $VVV across vesting, transaction, and launchpad yield sources
        uint256 amountToVestPerSecond; //amount of $VVV to vest per second
        uint256 stakedAmount; //total staked $VVV for the node
    }

    ///@notice The address of the authorization registry
    address public authorizationRegistry;

    ///@notice Flag for whether nodes are soulbound
    bool public soulbound = true;

    ///@notice The baseURI for the token metadata
    string public baseURI;

    ///@notice The total number of nodes that can be minted
    uint256 public constant TOTAL_SUPPLY = 5000;

    ///@notice Node activation threshold in staked $VVV
    uint256 public activationThreshold;

    ///@notice The maximum staked $VVV which can be considered for launchpad yield points
    uint256 public maxLaunchpadStakeAmount;

    ///@notice The current tokenId
    uint256 public tokenId;

    ///@notice Transaction processing reward
    uint256 public transactionProcessingReward;

    ///@notice Maps a TokenData struct to each tokenId
    mapping(uint256 => TokenData) public tokenData;

    ///@notice Thrown when the caller is not the owner of the token
    error CallerIsNotTokenOwner();

    ///@notice Thrown when a mint is attempted past the total supply
    error MaxSupplyReached();

    ///@notice Thrown when there are no claimable tokens for a node
    error NoClaimableTokens();

    ///@notice Thrown when a node transfer is attempted while nodes are soulbound
    error NodesAreSoulbound();

    ///@notice Thrown when a native transfer fails
    error TransferFailed();

    ///@notice Thrown when an attempt is made to stake/unstake 0 $VVV
    error ZeroTokenTransfer();

    constructor(
        address _authorizationRegistry,
        string memory _newBaseURI,
        uint256 _activationThreshold
    ) ERC721("Multi-token Nodes", "NODES") VVVAuthorizationRegistryChecker(_authorizationRegistry) {
        activationThreshold = _activationThreshold;
        authorizationRegistry = _authorizationRegistry;
        baseURI = _newBaseURI;
    }

    ///@notice Mints a node to the recipient (placeholder)
    function mint(address _recipient) external {
        ++tokenId;
        if (tokenId > TOTAL_SUPPLY) revert MaxSupplyReached();

        //placeholder logic to set TokenData
        tokenData[tokenId] = TokenData({
            unvestedAmount: 63_113_904 * 1e18, //seconds in 2 years * 1e18 for easy math with amount to vest per second
            vestingSince: block.timestamp,
            claimableAmount: 0,
            amountToVestPerSecond: 1e18,
            stakedAmount: 0
        });

        _mint(_recipient, tokenId);
    }

    ///@notice Stakes $VVV, handles activation if amount added causes total staked to surpass activation threshold
    function stake(uint256 _tokenId) external payable {
        if (msg.value == 0) revert ZeroTokenTransfer();
        if (msg.sender != ownerOf(_tokenId)) revert CallerIsNotTokenOwner();
        TokenData storage token = tokenData[_tokenId];

        //if node is inactive and this stake activates it, set vestingSince to the current timestamp
        if (
            !_isNodeActive(token.stakedAmount, activationThreshold) &&
            _isNodeActive(msg.value + token.stakedAmount, activationThreshold)
        ) {
            token.vestingSince = block.timestamp;
        }

        token.stakedAmount += msg.value;
    }

    ///@notice Unstakes $VVV, handles deactivation if amount removed causes total staked to fall below activation threshold
    function unstake(uint256 _tokenId, uint256 _amount) external {
        if (_amount == 0) revert ZeroTokenTransfer();
        if (msg.sender != ownerOf(_tokenId)) revert CallerIsNotTokenOwner();
        TokenData storage token = tokenData[_tokenId];

        if (
            _isNodeActive(token.stakedAmount, activationThreshold) &&
            !_isNodeActive(token.stakedAmount - _amount, activationThreshold)
        ) {
            _updateClaimableFromVesting(token);
        }

        token.stakedAmount -= _amount;

        (bool success, ) = msg.sender.call{ value: _amount }("");
        if (!success) revert TransferFailed();
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

        (bool success, ) = msg.sender.call{ value: amountToClaim }("");
        if (!success) revert TransferFailed();
    }

    ///@notice Claims for all input tokenIds
    function batchClaim(uint256[] calldata _tokenIds) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            claim(_tokenIds[i]);
        }
    }

    ///@notice Sets the node activation threshold in staked $VVV
    function setActivationThreshold(uint256 _activationThreshold) external onlyAuthorized {
        if (_activationThreshold > activationThreshold) {
            //update claimable balances of nodes which will become inactive as a result of the threshold increase
            for (uint256 i = 1; i <= tokenId; i++) {
                TokenData storage token = tokenData[i];
                if (
                    _isNodeActive(token.stakedAmount, activationThreshold) &&
                    !_isNodeActive(token.stakedAmount, _activationThreshold)
                ) {
                    _updateClaimableFromVesting(token);
                }
            }
        } else if (_activationThreshold < activationThreshold) {
            //set vestingSince for nodes which will become active as a result of the threshold decrease
            for (uint256 i = 1; i <= tokenId; i++) {
                TokenData storage token = tokenData[i];
                if (
                    _isNodeActive(token.stakedAmount, _activationThreshold) &&
                    !_isNodeActive(token.stakedAmount, activationThreshold)
                ) {
                    token.vestingSince = block.timestamp;
                }
            }
        }

        activationThreshold = _activationThreshold;
    }

    ///@notice Sets the maximum staked $VVV which can be considered for launchpad yield points
    function setMaxLaunchpadStakeAmount(uint256 _maxLaunchpadStakeAmount) external onlyAuthorized {
        maxLaunchpadStakeAmount = _maxLaunchpadStakeAmount;
    }

    ///@notice Sets whether nodes are soulbound
    function setSoulbound(bool _soulbound) external onlyAuthorized {
        soulbound = _soulbound;
    }

    ///@notice Sets token URI for token of tokenId (placeholder)
    function setBaseURI(string calldata _newBaseURI) external onlyAuthorized {
        baseURI = _newBaseURI;
    }

    ///@notice Sets the transaction processing reward
    function setTransactionProcessingReward(uint256 _transactionProcessingReward) external onlyAuthorized {
        transactionProcessingReward = _transactionProcessingReward;
    }

    ///@notice Withdraws $VVV from the contract
    function withdraw(uint256 _amount) external onlyAuthorized {
        (bool success, ) = msg.sender.call{ value: _amount }("");
        if (!success) revert TransferFailed();
    }

    ///@notice returns whether a node of input tokenId is active
    function isNodeActive(uint256 _tokenId) external view returns (bool) {
        return _isNodeActive(tokenData[_tokenId].stakedAmount, activationThreshold);
    }

    ///@notice override for ERC721:_baseURI to set baseURI
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    ///@notice Override of ERC721:_update to enforce soulbound restrictions when tokens are not being minted
    function _update(
        address _to,
        uint256 _tokenId,
        address _auth
    ) internal virtual override returns (address) {
        if (soulbound && _auth != address(0)) revert NodesAreSoulbound();
        return super._update(_to, _tokenId, _auth);
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
        if (!_isNodeActive(_tokenData.stakedAmount, activationThreshold)) return 0;

        uint256 totalUnvestedAmount = _tokenData.unvestedAmount;
        uint256 amountToVestPerSecond = _tokenData.amountToVestPerSecond;

        //inclusive of timestamp which set vestingSince
        uint256 timeBasedVestingAmount = (block.timestamp - vestingSince + 1) * amountToVestPerSecond;
        uint256 currentVestedAmount = totalUnvestedAmount > timeBasedVestingAmount
            ? timeBasedVestingAmount
            : totalUnvestedAmount;

        return currentVestedAmount;
    }

    ///@notice Returns whether node is active based on whether it's staked $VVV is above the activation threshold.
    function _isNodeActive(
        uint256 _stakedVVVAmount,
        uint256 _activationThreshold
    ) private pure returns (bool) {
        return _stakedVVVAmount >= _activationThreshold;
    }
}
