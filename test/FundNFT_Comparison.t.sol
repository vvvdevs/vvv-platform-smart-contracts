//SPDX-License-Identifier: MIT

/**
 * @dev VVV_FUND NFT tests
 */

pragma solidity ^0.8.15;

import "lib/forge-std/src/Test.sol"; //for stateless tests

import { VVV_FUND_ERC721A } from "contracts/FundNFT_ERC721A.sol";
import { VVV_FUND_ERC721 } from "contracts/FundNFT_ERC721.sol";
import { VVV_FUND_ERC1155 } from "contracts/FundNFT_ERC1155.sol";
import { VVV_FUND_ERC1155D } from "contracts/FundNFT_ERC1155D.sol";

import { MyToken } from "contracts/mock/MockERC721.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";


contract InvestmentHandlerTestSetup is Test {

    MyToken public s1nft;

    VVV_FUND_ERC721A public fundNft_ERC721A;
    VVV_FUND_ERC721 public fundNft_ERC721;
    VVV_FUND_ERC1155 public fundNft_ERC1155;
    VVV_FUND_ERC1155D public fundNft_ERC1155D;

    address[] public users = new address[](333);

    uint256 public deployerKey = 1234;
    uint256 public defaultAdminControllerKey = 12345; //will likely be multisig
    uint256 public custodianKey = 123456;
    uint256 public signerKey = 123456789;

    address deployer = vm.addr(deployerKey);
    address defaultAdminController = vm.addr(defaultAdminControllerKey);
    address custodian = vm.addr(custodianKey);
    address signer = vm.addr(signerKey);

    address sampleUser;
    address sampleKycAddress;

    bool logging = false;

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 chainid;

    // setup =============================================================================

    function setUp() public {
        vm.startPrank(deployer, deployer);

        s1nft = new MyToken();

        fundNft_ERC721A = new VVV_FUND_ERC721A(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/"
        );

        fundNft_ERC721 = new VVV_FUND_ERC721(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/"
        );

        fundNft_ERC1155 = new VVV_FUND_ERC1155(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/{id}.json"
        );

        fundNft_ERC1155D = new VVV_FUND_ERC1155D(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/{id}.json"
        );

        vm.stopPrank();

        generateUserAddressListAndDealEther();

    }

    // Helpers-----------------------------------------------------------------------------

    // generate list of random addresses
    function generateUserAddressListAndDealEther() public {


        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
        }
        vm.deal(defaultAdminController, 1 ether); // and YOU get an ETH
        sampleKycAddress = users[0];
        sampleUser = users[1];
        s1nft.safeMint(sampleUser);
        s1nft.safeMint(sampleUser); //will def have ID 1

        for (uint256 i = 0; i < users.length; i++) {
            s1nft.safeMint(users[i]);
        }
    }

    // create concat'd 65 byte signature that ethers would generate instead of r,s,v
    function toBytesConcat(bytes32 r, bytes32 s, uint8 v) public pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        for (uint256 i = 0; i < 32; i++) {
            signature[i] = r[i];
            signature[i + 32] = s[i];
        }
        signature[64] = bytes1(v);
        return signature;
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function getSignature(
        address _minter,
        uint256 _maxQuantity
    ) public returns (bytes memory) {
        chainid = block.chainid;
        bytes32 messageHash = keccak256(abi.encodePacked(_minter, _maxQuantity, chainid));
        bytes32 prefixedHash = prefixed(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, prefixedHash);
        bytes memory signature = toBytesConcat(r, s, v);

        if (logging) {
            emit log_named_bytes32("hash", messageHash);
            emit log_named_bytes("signature", signature);
        }

        return signature;
    }

    function advanceBlockNumberAndTimestamp(uint256 blocks) public {
        for (uint256 i = 0; i < blocks; i++) {
            blockNumber += 1;
            blockTimestamp += 12; //seconds per block
        }
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }

    //==================================================================================================
    // ERC721A VERSION
    //==================================================================================================

    function testDeployment_ERC721A() public {
        assertTrue(address(fundNft_ERC721A) != address(0));
    }

    function testMintViaSignature_ERC721A() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721A.mintBySignature{value: fundNft_ERC721A.whitelistMintPrice()}(sampleUser, 1, 1, signature);
        vm.stopPrank();
        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);
    }

    function testMintViaTradeIn_ERC721A() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft_ERC721A), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        fundNft_ERC721A.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);
    }

    function testMintPublic_ERC721A() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721A.setPublicMintIsOpen(true);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721A.publicMint{value: fundNft_ERC721A.publicMintPrice()}(sampleUser, 1);
        vm.stopPrank();

        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);
    }

    function testFailMintViaSignature_ERC721A() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721A.mintBySignature{value: fundNft_ERC721A.whitelistMintPrice()-1}(sampleUser, 1, 1, signature);
        vm.stopPrank();
        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);
    }

    function testFailMintViaTradeIn_ERC721A() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft_ERC721A), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 11;
        fundNft_ERC721A.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);        
    }

    function testFailMintPublic_ERC721A() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721A.setPublicMintIsOpen(true);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721A.publicMint{value: fundNft_ERC721A.publicMintPrice()-1}(sampleUser, 1);
        vm.stopPrank();

        assertTrue(fundNft_ERC721A.ownerOf(1) == sampleUser);
    }

    //==================================================================================================
    // ERC721 VERSION
    //==================================================================================================
    function testDeployment_ERC721() public {
        assertTrue(address(fundNft_ERC721) != address(0));
    }

    function testMintViaSignature_ERC721() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721.mintBySignature{value: fundNft_ERC721.whitelistMintPrice()}(sampleUser, 1, 1, signature);
        vm.stopPrank();
        uint256 idOffset = fundNft_ERC721.currentNonReservedId();
        assertTrue(fundNft_ERC721.ownerOf(idOffset) == sampleUser);
    }

    function testMintViaTradeIn_ERC721() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft_ERC721), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        fundNft_ERC721.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC721.ownerOf(1) == sampleUser);
    }

    function testMintPublic_ERC721() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.setPublicMintIsOpen(true);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721.publicMint{value: fundNft_ERC721.publicMintPrice()}(sampleUser, 1);
        vm.stopPrank();
        
        uint256 idOffset = fundNft_ERC721.currentNonReservedId();
        assertTrue(fundNft_ERC721.ownerOf(idOffset) == sampleUser);
    }
    //==================================================================================================
    // ERC1155 VERSION
    //==================================================================================================

    function testDeployment_ERC1155() public {
        assertTrue(address(fundNft_ERC1155) != address(0));
    }

    function testMintViaSignature_ERC1155() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC1155.mintBySignature{value: fundNft_ERC1155.whitelistMintPrice()}(sampleUser, 1, 1, signature);
        vm.stopPrank();
        uint256 idOffset = fundNft_ERC1155.currentNonReservedId();
        assertTrue(fundNft_ERC1155.ownerOf(idOffset) == sampleUser);
    }

    function testMintViaTradeIn_ERC1155() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft_ERC1155), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        fundNft_ERC1155.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC1155.ownerOf(1) == sampleUser);
    }

    function testMintPublic_ERC1155() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC1155.setPublicMintIsOpen(true);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC1155.publicMint{value: fundNft_ERC1155.publicMintPrice()}(sampleUser, 1);
        vm.stopPrank();

        uint256 idOffset = fundNft_ERC1155.currentNonReservedId();
        assertTrue(fundNft_ERC1155.ownerOf(idOffset) == sampleUser);
    }

    //==================================================================================================
    // ERC1155D VERSION
    //==================================================================================================

    function testDeployment_ERC1155D() public {
        assertTrue(address(fundNft_ERC1155D) != address(0));
    }

    function testMintViaSignature_ERC1155D() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC1155D.mintBySignature{value: fundNft_ERC1155D.whitelistMintPrice()}(sampleUser, 1, 1, signature);
        vm.stopPrank();
        uint256 idOffset = fundNft_ERC1155D.currentNonReservedId();
        assertTrue(fundNft_ERC1155D.ownerOfERC721Like(idOffset) == sampleUser);
    }

    function testMintViaTradeIn_ERC1155D() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft_ERC1155D), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        fundNft_ERC1155D.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC1155D.ownerOfERC721Like(1) == sampleUser);
    }

    function testMintPublic_ERC1155D() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC1155D.setPublicMintIsOpen(true);
        vm.stopPrank();

        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC1155D.publicMint{value: fundNft_ERC1155D.publicMintPrice()}(sampleUser, 1);
        vm.stopPrank();

        uint256 idOffset = fundNft_ERC1155D.currentNonReservedId();
        assertTrue(fundNft_ERC1155D.ownerOfERC721Like(idOffset) == sampleUser);
    }
}
