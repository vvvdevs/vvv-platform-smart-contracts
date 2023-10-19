//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC721A } from "erc721a/contracts/ERC721A.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VVV_FUND_ERC721A is ERC721A, AccessControl, ReentrancyGuard {

    IERC721 public immutable S1NFT;
    
    uint256 public constant MAX_SUPPLY = 10_000;
    
    address public signer;
    bool public publicMintIsOpen;
    string public baseURI;
    uint256 public mintableInPublicPerAddress = 2;
    uint256 public publicMintPrice = 0.06 ether;
    uint256 public whitelistMintPrice = 0.05 ether;    

    mapping(address => uint256) public mintedBySignature;
    mapping(address => uint256) public mintedPublic;

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
    ) ERC721A(_name, _symbol) {
        S1NFT = IERC721(_s1nft);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        setBaseURI(_baseUri);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721A, AccessControl) returns (bool) {
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
        for(uint256 i = 0; i < quantity; ++i) {
            if(S1NFT.ownerOf(_ids[i]) != msg.sender) {
                revert NotTokenOwner();
            }
            S1NFT.transferFrom(msg.sender, address(this), _ids[i]);
        }

        _mint(_to, quantity);
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

        if(_quantity + totalSupply() > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }

        if(msg.value < whitelistMintPrice * _quantity) {
            revert InsufficientFunds();
        }

        mintedBySignature[msg.sender] += _quantity;
        if(mintedBySignature[msg.sender] > _maxQuantity) {
            revert MaxAllocationWouldBeExceeded();
        }
        
        _mint(_to, _quantity);
    }

    //==================================================================================================
    // PUBLIC MINTING
    //==================================================================================================
    function publicMint(address _to, uint256 _quantity) external payable nonReentrant {
        if(!publicMintIsOpen) {
            revert PublicMintIsNotOpen();
        }
        
        if(_quantity + totalSupply() > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }

        if(msg.value < publicMintPrice * _quantity) {
            revert InsufficientFunds();
        }

        if(mintedPublic[msg.sender] + _quantity > mintableInPublicPerAddress) {
            revert MaxAllocationWouldBeExceeded();
        }

        _mint(_to, _quantity);
    }

    //==================================================================================================
    // ADMIN FUNCTIONS
    //==================================================================================================
    function adminMint(
        address _to,
        uint256 _quantity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_quantity + totalSupply() > MAX_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }
        _mint(_to, _quantity);
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _uri;
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
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

}

