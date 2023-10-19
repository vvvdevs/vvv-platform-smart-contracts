//SPDX-License-Identifier: MIT

/**
 * @dev VVV_FUND NFT tests
 */

pragma solidity ^0.8.15;

import "lib/forge-std/src/Test.sol"; //for stateless tests

import { VVV_FUND_ERC721 } from "contracts/FundNFT_ERC721.sol";

import { MyToken } from "contracts/mock/MockERC721.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";


contract InvestmentHandlerTestSetup is Test {

    MyToken public s1nft;

    VVV_FUND_ERC721 public fundNft_ERC721;

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


        fundNft_ERC721 = new VVV_FUND_ERC721(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/"
        );
        fundNft_ERC721.unpause(); 
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
        for (uint256 i=0; i < 20; i++){
            s1nft.safeMint(sampleUser);
        }

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
    // ERC721 VERSION TESTS
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

    function testPublicMint() public {
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721.publicMint{value: 0.05 ether}(1);
        vm.stopPrank();

        uint256 idOffset = fundNft_ERC721.currentNonReservedId();
        assertTrue(fundNft_ERC721.ownerOf(idOffset) == sampleUser);
    }

    function testPublicMintMax() public {
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721.publicMint{value: 0.25 ether}(5);
        vm.stopPrank();
        uint256 idOffset = fundNft_ERC721.currentNonReservedId();
        assertTrue(fundNft_ERC721.ownerOf(idOffset - 4)== sampleUser);
        assertTrue(fundNft_ERC721.ownerOf(idOffset - 3) == sampleUser);
        assertTrue(fundNft_ERC721.ownerOf(idOffset - 2) == sampleUser);
        assertTrue(fundNft_ERC721.ownerOf(idOffset - 1) == sampleUser);
        assertTrue(fundNft_ERC721.ownerOf(idOffset) == sampleUser);
    }

    function testPublicMintMaxExceeded() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxPublicMintsWouldBeExceeded.selector);
        fundNft_ERC721.publicMint{value: 0.30 ether}(6);
        vm.stopPrank();
    }

    function testPublicMintMaxSupplyExceded() public {
        vm.startPrank(deployer, deployer);
        for (uint256 i = 0; i < 9999; i++) {
            fundNft_ERC721.adminMint(deployer, 1);
        }
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxSupplyWouldBeExceeded.selector);
        fundNft_ERC721.publicMint{value: 0.05 ether}(1);
        vm.stopPrank();
    }

    function testPublicMintInsuffecientFunds() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.InsufficientFunds.selector);
        fundNft_ERC721.publicMint{value: 0.01 ether}(1);
        vm.stopPrank();
    }

    function testMintMaxSupplyExceeded() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(deployer, deployer);
        // loop so that we mint 9999 nfts
        for (uint256 i = 0; i < 9999; i++) {
            fundNft_ERC721.adminMint(deployer, 1);
        }
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxSupplyWouldBeExceeded.selector);
        fundNft_ERC721.mintBySignature{value: 0.05 ether}(sampleUser, 1, 1, signature);
        vm.stopPrank();
    }

    function testSetPublicMintStartTime() public {
        vm.startPrank(deployer, deployer);
        uint256 newStartTime = blockTimestamp + 1000;
        fundNft_ERC721.setPublicMintStartTime(newStartTime);
        vm.stopPrank();
        assertTrue(fundNft_ERC721.publicMintStartTime() == newStartTime);
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

    function testMigrateFifteenNfts() public {
        vm.startPrank(sampleUser, sampleUser);
            s1nft.setApprovalForAll(address(fundNft_ERC721), true);

            uint256[] memory ids = new uint256[](15);
            for(uint256 i=0; i<ids.length; i++){
                ids[i] = i+1;
            }

            fundNft_ERC721.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft_ERC721.ownerOf(1) == sampleUser);        
    }

    function testAdminMint() public{
        vm.startPrank(deployer, deployer);
            fundNft_ERC721.adminMint(deployer, 1);
        vm.stopPrank();
        uint256 idOffset = fundNft_ERC721.currentNonReservedId();
        assertTrue(fundNft_ERC721.ownerOf(idOffset) == deployer);
    }

    function testPause() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.pause();
        vm.stopPrank();
        assertTrue(fundNft_ERC721.paused());
    }

    function testUnPause() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.pause();
        assertTrue(fundNft_ERC721.paused());
        fundNft_ERC721.unpause();
        vm.stopPrank();
        assertTrue(!fundNft_ERC721.paused());
    }

    function testPublicMintWhenPaused() public {
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.pause();
        vm.expectRevert();
        fundNft_ERC721.publicMint{value: 0.05 ether}(1);
        vm.stopPrank();
    }

    function testSignatureMintWhenPaused() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.pause();
        vm.expectRevert();
        fundNft_ERC721.mintBySignature{value: 0.05 ether}(sampleUser, 1, 1, signature);
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 balance = address(deployer).balance;
        vm.startPrank(sampleUser, sampleUser);
        fundNft_ERC721.publicMint{value: 0.25 ether}(5);
        vm.stopPrank();
        vm.startPrank(deployer, deployer);
        fundNft_ERC721.withdraw();
        vm.stopPrank();
        uint newBalance = address(deployer).balance;
        assertTrue(newBalance == balance + 0.25 ether);
    }
}
