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

    VVV_FUND_ERC721 public fundNft;

    address[] public users = new address[](333);

    uint256 public deployerKey = 1234;
    uint256 public defaultAdminControllerKey = 12345; //will likely be multisig
    uint256 public custodianKey = 123456;
    uint256 public signerKey = 123456789;
    uint256 public whitelistMintDeadline;

    address deployer = vm.addr(deployerKey);
    address defaultAdminController = vm.addr(defaultAdminControllerKey);
    address custodian = vm.addr(custodianKey);
    address signer = vm.addr(signerKey);

    address sampleUser;
    address sampleKycAddress;

    bool logging = false;

    uint256 blockNumber;
    uint256 blockTimestamp;

    // setup =============================================================================

    function setUp() public {
        vm.startPrank(deployer, deployer);

        s1nft = new MyToken();


        fundNft = new VVV_FUND_ERC721(
            address(s1nft),
            signer,
            "VVV Fund",
            "VVVF",
            "https://vvv.fund/api/token/"
        );
        fundNft.unpause(); 
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

    function getSignature(
        address _minter,
        uint256 _maxQuantity,
        uint256 _deadline
    ) public returns (bytes memory) {
        // EIP-712 domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VVV_FUND_ERC721")),
                keccak256(bytes("1")),
                block.chainid,
                address(fundNft)
            )
        );

        // EIP-712 encoded data
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256("WhitelistMint(address minter,uint256 maxQuantity,uint256 deadline)"),
                        _minter,
                        _maxQuantity,
                        _deadline
                    )
                )
            )
        );

        // Get the signature components
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        bytes memory signature = toBytesConcat(r, s, v);

        if (logging) {
            emit log_named_bytes32("digest", digest);
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
    function testDeployment() public {
        assertTrue(address(fundNft) != address(0));
    }

    function testMintViaSignature() public {
        whitelistMintDeadline = blockTimestamp + 1;
        bytes memory signature = getSignature(sampleUser, 1, whitelistMintDeadline);
        vm.startPrank(sampleUser, sampleUser);
        fundNft.mintBySignature{value: fundNft.whitelistMintPrice()}(sampleUser, 1, 1, whitelistMintDeadline, signature);
        vm.stopPrank();
        uint256 idOffset = fundNft.currentNonReservedId();
        assertTrue(fundNft.ownerOf(idOffset) == sampleUser);
    }

    function testPublicMint() public {
        vm.startPrank(sampleUser, sampleUser);
        fundNft.publicMint{value: 0.05 ether}(sampleUser, 1);
        vm.stopPrank();

        uint256 idOffset = fundNft.currentNonReservedId();
        assertTrue(fundNft.ownerOf(idOffset) == sampleUser);
    }

    function testPublicMintMax() public {
        vm.startPrank(sampleUser, sampleUser);
        fundNft.publicMint{value: 0.25 ether}(sampleUser, 5);
        vm.stopPrank();
        uint256 idOffset = fundNft.currentNonReservedId();
        assertTrue(fundNft.ownerOf(idOffset - 4)== sampleUser);
        assertTrue(fundNft.ownerOf(idOffset - 3) == sampleUser);
        assertTrue(fundNft.ownerOf(idOffset - 2) == sampleUser);
        assertTrue(fundNft.ownerOf(idOffset - 1) == sampleUser);
        assertTrue(fundNft.ownerOf(idOffset) == sampleUser);
    }

    function testPublicMintMaxExceeded() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxPublicMintsWouldBeExceeded.selector);
        fundNft.publicMint{value: 0.30 ether}(sampleUser, 6);
        vm.stopPrank();
    }

    function testPublicMintSetMax() public {
        vm.startPrank(deployer, deployer);
        fundNft.setMaxPublicMintsPerAddress(1);
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxPublicMintsWouldBeExceeded.selector);
        fundNft.publicMint{value: 0.05 ether}(sampleUser, 2);
        vm.stopPrank();
    }

    function testPublicMintMaxSupplyExceded() public {
        vm.startPrank(deployer, deployer);
        for (uint256 i = 0; i < 9999; i++) {
            fundNft.adminMint(deployer, 1);
        }
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxSupplyWouldBeExceeded.selector);
        fundNft.publicMint{value: 0.05 ether}(sampleUser, 1);
        vm.stopPrank();
    }

    function testPublicMintInsuffecientFunds() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.InsufficientFunds.selector);
        fundNft.publicMint{value: 0.01 ether}(sampleUser, 1);
        vm.stopPrank();
    }

    function testMintMaxSupplyExceeded() public {
        whitelistMintDeadline = blockTimestamp + 1;
        bytes memory signature = getSignature(sampleUser, 1, whitelistMintDeadline);
        vm.startPrank(deployer, deployer);
        // loop so that we mint 9999 nfts
        for (uint256 i = 0; i < 9999; i++) {
            fundNft.adminMint(deployer, 1);
        }
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVV_FUND_ERC721.MaxSupplyWouldBeExceeded.selector);
        fundNft.mintBySignature{value: 0.05 ether}(sampleUser, 1, 1, whitelistMintDeadline, signature);
        vm.stopPrank();
    }

    function testSetPublicMintStartTime() public {
        vm.startPrank(deployer, deployer);
        uint256 newStartTime = blockTimestamp + 1000;
        fundNft.setPublicMintStartTime(newStartTime);
        vm.stopPrank();
        assertTrue(fundNft.publicMintStartTime() == newStartTime);
    }

    function testMintViaTradeIn() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundNft), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        fundNft.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft.ownerOf(1) == sampleUser);
    }

    function testMigrateFifteenNfts() public {
        vm.startPrank(sampleUser, sampleUser);
            s1nft.setApprovalForAll(address(fundNft), true);

            uint256[] memory ids = new uint256[](15);
            for(uint256 i=0; i<ids.length; i++){
                ids[i] = i+1;
            }

            fundNft.mintByTradeIn(sampleUser, ids); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundNft.ownerOf(1) == sampleUser);        
    }

    function testAdminMint() public{
        vm.startPrank(deployer, deployer);
        fundNft.adminMint(deployer, 1);
        vm.stopPrank();
        uint256 idOffset = fundNft.currentNonReservedId();
        assertTrue(fundNft.ownerOf(idOffset) == deployer);
    }

    function testPause() public {
        vm.startPrank(deployer, deployer);
        fundNft.pause();
        vm.stopPrank();
        assertTrue(fundNft.paused());
    }

    function testUnPause() public {
        vm.startPrank(deployer, deployer);
        fundNft.pause();
        assertTrue(fundNft.paused());
        fundNft.unpause();
        vm.stopPrank();
        assertTrue(!fundNft.paused());
    }

    function testPublicMintWhenPaused() public {
        vm.startPrank(deployer, deployer);
        fundNft.pause();
        vm.expectRevert();
        fundNft.publicMint{value: 0.05 ether}(sampleUser, 1);
        vm.stopPrank();
    }

    function testSignatureMintWhenPaused() public {
        whitelistMintDeadline = blockTimestamp + 1;
        bytes memory signature = getSignature(sampleUser, 1, whitelistMintDeadline);
        vm.startPrank(deployer, deployer);
        fundNft.pause();
        vm.stopPrank();
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        fundNft.mintBySignature{value: 0.05 ether}(sampleUser, 1, 1, whitelistMintDeadline, signature);
        vm.stopPrank();
    }

    function testSignatureMintWithExpiredSignature() public {
        whitelistMintDeadline = blockTimestamp + 1;
        bytes memory signature = getSignature(sampleUser, 1, whitelistMintDeadline);
        advanceBlockNumberAndTimestamp(1); //advance one block to make signature invalid
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert();
        fundNft.mintBySignature{value: 0.05 ether}(sampleUser, 1, 1, whitelistMintDeadline, signature);
        vm.stopPrank();  
    }

    function testWithdraw() public {
        uint256 balance = address(deployer).balance;
        vm.startPrank(sampleUser, sampleUser);
        fundNft.publicMint{value: 0.25 ether}(sampleUser, 5);
        vm.stopPrank();
        vm.startPrank(deployer, deployer);
        fundNft.withdraw();
        vm.stopPrank();
        uint newBalance = address(deployer).balance;
        assertTrue(newBalance == balance + 0.25 ether);
    }

    function testTokenURI() public {
        vm.startPrank(deployer, deployer);
        fundNft.adminMint(deployer, 1);
        vm.stopPrank();

        string memory tokenURI = fundNft.tokenURI(3501);
        assertTrue(keccak256(abi.encodePacked(tokenURI)) == keccak256(abi.encodePacked("https://vvv.fund/api/token/3501.json")));
    }

    function testSetBaseExtension() public {
        vm.startPrank(deployer, deployer);
        fundNft.setBaseExtension(".html");
        fundNft.adminMint(deployer, 1);
        vm.stopPrank();

        string memory tokenURI = fundNft.tokenURI(3501);
        assertTrue(keccak256(abi.encodePacked(tokenURI)) == keccak256(abi.encodePacked("https://vvv.fund/api/token/3501.html")));

    }
}
