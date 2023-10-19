//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title VVV_FUND_ERC1155
/// @notice relative to ERC721A version, includes reserved IDs for non-S1 collection IDs (example, assuming above 3500, would need to know this number ahead of deployment)
/// @notice relative to both ERC721A and ERC721 versions, includes an 'ownerOf' mapping to track the owner of each token ID

contract VVV_FUND_ERC1155 is ERC1155, AccessControl, ReentrancyGuard {

    IERC721 public immutable S1NFT;
    
    uint256 public constant MAX_SUPPLY = 10_000;
    
    address public signer;
    bool public publicMintIsOpen;
    string public name;
    string public symbol;

    // note: 1-3500 reserved, 3501 - 10,000 non-reserved (currentNonReservedId incremented before each mint)
    uint256 public currentNonReservedId = 3500;
    
    uint256 public mintableInPublicPerAddress = 2;
    uint256 public publicMintPrice = 0.06 ether;
    uint256 public totalSupply;
    uint256 public whitelistMintPrice = 0.05 ether;    

    mapping(address => uint256) public mintedBySignature;
    mapping(address => uint256) public mintedPublic;
    mapping(uint256 => address) private _owners;

    error ArrayLengthMismatch();
    error InsufficientFunds();
    error InvalidSignature();
    error MaxAllocationWouldBeExceeded();
    error MaxSupplyWouldBeExceeded();
    error NotTokenOwner();
    error PublicMintIsNotOpen();

    constructor(
        address _s1nft,
        address _signer,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC1155(_baseUri) {
        S1NFT = IERC721(_s1nft);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    //==================================================================================================
    // MINTING BY TRADING IN PREVIOUS NFT COLLECTION (MIGRATION)
    //==================================================================================================
    /**
        @notice inbuilt checks confirm that the S1NFT is owned by the msg.sender and that this contract has permission to transfer it on behalf of the user    
        @notice this function is only callable by the owner of the S1NFT
        @notice S1NFT are sent to this contract- could also be 0xdead if desired - original contract does not include burn function
        @notice requires this contract to be approved to transfer S1NFT on behalf of the user
     */ 
    function mintByTradeIn(
        address _to,
        uint256[] memory _ids
    ) public nonReentrant {
        uint256 quantity = _ids.length;
        totalSupply += quantity;
        for(uint256 i = 0; i < quantity; ++i) {
            if(S1NFT.ownerOf(_ids[i]) != msg.sender) {
                revert NotTokenOwner();
            }
            S1NFT.transferFrom(msg.sender, address(this), _ids[i]);
            _mint(_to, _ids[i], 1, "");
        }
    }

    //==================================================================================================
    // MINTING BY SIGNATURE (WHITELIST)
    //==================================================================================================
    
    /**
     * @notice mints via signature while ensuring the max mintable amount specified in the signature is not exceeded
     */
    function mintBySignature(
        address _to,
        uint256 _quantity,
        uint256 _maxQuantity,
        bytes memory _signature
    ) external payable nonReentrant {

        if(!_isSignatureValid(msg.sender, _maxQuantity, _signature)) {
            revert InvalidSignature();
        }

        if(_quantity + totalSupply > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }

        if(msg.value < whitelistMintPrice * _quantity) {
            revert InsufficientFunds();
        }

        mintedBySignature[msg.sender] += _quantity;
        if(mintedBySignature[msg.sender] > _maxQuantity) {
            revert MaxAllocationWouldBeExceeded();
        }
        
        totalSupply += _quantity;
        for(uint256 i = 0; i < _quantity; ++i) {
            ++currentNonReservedId;
            _mint(_to, currentNonReservedId, 1, "");
        }
    }

    //==================================================================================================
    // PUBLIC MINTING
    //==================================================================================================
    function publicMint(address _to, uint256 _quantity) external payable nonReentrant {
        if(!publicMintIsOpen) {
            revert PublicMintIsNotOpen();
        }
        
        if(_quantity + totalSupply > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }

        if(msg.value < publicMintPrice * _quantity) {
            revert InsufficientFunds();
        }

        if(mintedPublic[msg.sender] + _quantity > mintableInPublicPerAddress) {
            revert MaxAllocationWouldBeExceeded();
        }

        totalSupply += _quantity;
        for(uint256 i = 0; i < _quantity; ++i) {
            ++currentNonReservedId;
            _mint(_to, currentNonReservedId, 1, "");
        }
    }

    //==================================================================================================
    // VIEW FUNCTIONS
    //==================================================================================================
    function ownerOf(uint256 _tokenId) external view returns (address) {
        return _owners[_tokenId];
    }

    //==================================================================================================
    // ADMIN FUNCTIONS
    //==================================================================================================
    function adminMint(
        address _to,
        uint256 _quantity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_quantity + totalSupply > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }
        
        totalSupply += _quantity;
        for(uint256 i = 0; i < _quantity; ++i) {
            ++currentNonReservedId;
            _mint(_to, currentNonReservedId, 1, "");
        }
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(_uri);
    }

    function setSigner(address _signer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function setPublicMintIsOpen(bool _publicMintIsOpen) public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicMintIsOpen = _publicMintIsOpen;
    }

    function setMintPrices(uint256 _publicMintPrice, uint256 _whitelistMintPrice) public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicMintPrice = _publicMintPrice;
        whitelistMintPrice = _whitelistMintPrice;
    }

    //==================================================================================================
    // INTERNAL FUNCTIONS
    //==================================================================================================
    function _isSignatureValid(
        address _minter,
        uint256 _maxQuantity,
        bytes memory _signature
    ) internal view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                signer,
                ECDSA.toEthSignedMessageHash(
                    keccak256(
                        abi.encodePacked(
                            _minter,
                            _maxQuantity,
                            block.chainid
                        )
                    )
                ),
                _signature
            );
    }

    //==================================================================================================
    // OVERRIDES
    //==================================================================================================
    function _beforeTokenTransfer(
        address operator, 
        address from,
        address to, 
        uint256[] memory ids, 
        uint256[] memory amounts, 
        bytes memory data
    ) internal override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        for(uint256 i = 0; i < ids.length; ++i) {
                _owners[ids[i]] = to;
        }
    }

}

