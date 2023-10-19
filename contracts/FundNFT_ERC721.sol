//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Pausable } from  "@openzeppelin/contracts/security/Pausable.sol";

/// @title VVV_FUND_ERC721
/// @notice relative to ERC721A version, includes reserved IDs for non-S1 collection IDs (example, assuming above 3500, would need to know this number ahead of deployment)

contract VVV_FUND_ERC721 is ERC721, AccessControl, ReentrancyGuard, Pausable {
    IERC721 public immutable S1NFT;
    
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_MINTABLE_SUPPLY = MAX_SUPPLY - 1;
    uint256 public constant MAX_PUBLIC_MINTS_PER_ADDRESS = 5;
    
    address public signer;
    uint256 public currentNonReservedId = 3500;
    uint256 public totalSupply;
    uint256 public whitelistMintPrice = 0.05 ether;
    uint256 public publicMintPrice = 0.05 ether;
    uint256 public publicMintStartTime;

    mapping(address => uint256) public mintedBySignature;
    mapping(address => uint8) public publicMintsByAddress;

    error ArrayLengthMismatch();
    error InsufficientFunds();
    error InvalidSignature();
    error MaxAllocationWouldBeExceeded();
    error MaxSupplyWouldBeExceeded();
    error NotTokenOwner();
    error MaxPublicMintsWouldBeExceeded();
    error PublicMintNotStarted();
    error PublicMintIsNotOpen();

    constructor(
        address _s1nft,
        address _signer,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC721(_name, _symbol) {
        S1NFT = IERC721(_s1nft);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;

        // should be updated to the actual start time after deployment
        publicMintStartTime = block.timestamp;
        _pause();
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
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
            _mint(_to, _ids[i]);
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
    ) external payable nonReentrant whenNotPaused {
        if(!_isSignatureValid(msg.sender, _maxQuantity, _signature)) {
            revert InvalidSignature();
        }

        if(_quantity + totalSupply > MAX_MINTABLE_SUPPLY) {
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
            _mint(_to, currentNonReservedId);
        }
    }


    /**
     * @notice public mint function that opens after specified date
     * @param _amount amount of tokens to mint
     */
    function publicMint(uint8 _amount) external payable nonReentrant whenNotPaused {
        publicMintsByAddress[msg.sender] += uint8(_amount);
        if(block.timestamp < publicMintStartTime) {
            revert PublicMintNotStarted();
        }

        if(publicMintsByAddress[msg.sender] > MAX_PUBLIC_MINTS_PER_ADDRESS) {
            revert MaxPublicMintsWouldBeExceeded();
        }
        if(_amount + totalSupply > MAX_MINTABLE_SUPPLY) {
            revert MaxSupplyWouldBeExceeded();
        }

        if(msg.value < publicMintPrice * _amount) {
            revert InsufficientFunds();
        }

        totalSupply += _amount;
        for (uint256 i = 0; i < _amount; ++i) {
            ++currentNonReservedId;
            _mint(msg.sender, currentNonReservedId);
        }
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
            _mint(_to, currentNonReservedId);
        }
    }    
    
    function setSigner(address _signer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function setWhitelistMintPrice(uint256 _whitelistMintPrice) public onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistMintPrice = _whitelistMintPrice;
    }

    function setPublicMintPrice(uint256 _publicMintPrice) public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicMintPrice = _publicMintPrice;
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setPublicMintStartTime(uint256 _startTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicMintStartTime = _startTime;
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
}
