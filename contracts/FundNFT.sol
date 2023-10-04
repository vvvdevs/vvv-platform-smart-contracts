//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VVV_FUND is ERC1155, AccessControl, ReentrancyGuard {

    IERC721 public immutable S1NFT;
    address public signer;
    address public custodian;
    string public name;
    string public symbol;
    mapping(bytes => bool) public signatureHasBeenUsed;

    error InvalidSignature();
    error SignatureHasBeenUsed();
    error ArrayLengthMismatch();

    constructor(
        address _s1nft,
        address _signer,
        address _custodian,
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) ERC1155(_uri) {
        S1NFT = IERC721(_s1nft);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        custodian = _custodian;
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    //==================================================================================================
    // MINTING BY TRADING IN PREVIOUS NFT COLLECTION
    // inbuilt checks confirm that the S1NFT is owned by the msg.sender and that this contract has permission to transfer it on behalf of the user
    // this function is only callable by the owner of the S1NFT
    // S1NFT are sent to this contract- could also be 0xdead if desired - original contract does not include burn function
    function batchMintByTradeIn(
        address _to,
        uint256[] memory _ids
    ) public nonReentrant {
        for(uint256 i = 0; i < _ids.length; i++) {
            mintByTradeIn(_ids[i]);
        }
    }
    
    function mintByTradeIn(
        uint256 _id
    ) public nonReentrant {
        S1NFT.transferFrom(msg.sender, address(this), _id);
        _mint(custodian, _id, 1, "");
    }

    //==================================================================================================
    // MINTING BY SIGNATURE
    function batchMintBySignature(
        address _to,
        uint256[] memory _ids,
        bytes[] memory _signatures
    ) public nonReentrant {
        if(_ids.length != _signatures.length) {
            revert ArrayLengthMismatch();
        }

        for(uint256 i = 0; i < _ids.length; i++) {
            mintBySignature(_ids[i], _signatures[i]);
        }
    }

    function mintBySignature(
        uint256 _id,
        bytes memory _signature
    ) public nonReentrant {

        if(!_signatureCheck(msg.sender, _id, _signature)) {
            revert InvalidSignature();
        }

        if(signatureHasBeenUsed[_signature]) {
            revert SignatureHasBeenUsed();
        }

        signatureHasBeenUsed[_signature] = true;

        _mint(custodian, _id, 1, "");
    }

    function _signatureCheck(
        address _minter,
        uint256 _id,
        bytes memory _signature
    ) private view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                signer,
                ECDSA.toEthSignedMessageHash(
                    keccak256(
                        abi.encodePacked(
                            _minter,
                            _id,
                            block.chainid
                        )
                    )
                ),
                _signature
            );
    }

}

