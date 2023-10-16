//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC721A } from "erc721a/contracts/ERC721A.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VVV_FUND is ERC721A, AccessControl, ReentrancyGuard {

    IERC721 public immutable S1NFT;
    address public signer;
    string public baseURI;
    uint256 public constant MAX_SUPPLY = 10_000;
    mapping(address => uint256) public mintedBySignature;

    error ArrayLengthMismatch();
    error InvalidSignature();
    error MaxAllocationWouldBeExceeded();
    error MaxSupplyWouldBeExceeded();
    error NotTokenOwner();

    constructor(
        address _s1nft,
        address _signer,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC721A(_name, _symbol) {
        S1NFT = IERC721(_s1nft);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        uint256[] memory _ids,
        uint256 _quantity
    ) public nonReentrant {
        if(_ids.length != _quantity){
            revert ArrayLengthMismatch();
        }

        for(uint256 i = 0; i < _ids.length; ++i) {
            if(S1NFT.ownerOf(_ids[i]) != msg.sender) {
                revert NotTokenOwner();
            }
            S1NFT.transferFrom(msg.sender, address(this), _ids[i]);
        }

        _safeMint(_to, _quantity);
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

        if(mintedBySignature[msg.sender] + _quantity > _maxQuantity) {
            revert MaxAllocationWouldBeExceeded();
        }

        mintedBySignature[msg.sender] += _quantity;

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

    //==================================================================================================
    // INTERNAL FUNCTIONS
    //==================================================================================================
    function _isSignatureValid(
        address _minter,
        uint256 _maxQuantity,
        bytes memory _signature
    ) private view returns (bool) {
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

