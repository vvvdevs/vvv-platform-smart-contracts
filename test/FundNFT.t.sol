//SPDX-License-Identifier: MIT

/**
 * @dev VVV_FUND NFT tests
 */

pragma solidity ^0.8.15;

import "lib/forge-std/src/Test.sol"; //for stateless tests

import { VVV_FUND } from "contracts/FundNFT.sol";
import { MyToken } from "contracts/mock/MockERC721.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";


contract InvestmentHandlerTestSetup is Test {

    MyToken public s1nft;

    VVV_FUND public fundnft;

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

        fundnft = new VVV_FUND(
            address(s1nft),
            signer,
            custodian,
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
        uint256 _id
    ) public returns (bytes memory) {
        chainid = block.chainid;
        bytes32 messageHash = keccak256(abi.encodePacked(_minter, _id, chainid));
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

    // Tests =============================================================================

    function testDeployment() public {
        assertTrue(address(fundnft) != address(0));
    }

    function testMintViaSignature() public {
        bytes memory signature = getSignature(sampleUser, 1);
        vm.startPrank(sampleUser, sampleUser);
        fundnft.mintBySignature(1, signature);
        vm.stopPrank();
        assertTrue(fundnft.balanceOf(custodian, 1) == 1);
    }

    function testMintViaTradeIn() public {
        vm.startPrank(sampleUser, sampleUser);
        s1nft.setApprovalForAll(address(fundnft), true);
        fundnft.mintByTradeIn(1); //sampleUser is minted ID 1
        vm.stopPrank();
        assertTrue(fundnft.balanceOf(custodian, 1) == 1);
    }

}
