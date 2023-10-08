//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**
 * @dev Base for testing LinearVestingWithLinearPenalty.sol
 */


import "lib/forge-std/src/Test.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { LinearVestingWithLinearPenalty } from "contracts/vesting/LinearVestingWithLinearPenalty.sol";

contract LinearVestingWithLinearPenaltyBase is Test {
    MockERC20 public mockToken;
    LinearVestingWithLinearPenalty public vestingContract;
    uint256 blockNumber;
    uint256 blockTimestamp;
    uint256 deployerKey = 1234;
    address deployer = vm.addr(deployerKey);
    uint256 public signerKey = 123456789;
    address signer = vm.addr(signerKey);
    uint256 chainid = 5;

    uint256 VESTING_LENGTH = 100_000;
    uint256[] NON_PENALIZED_PROPORTIONS = [0, 1000, 2000, 3000, 4000]; //testing "@TGE" claimable amounts without penalty

    address[] public users = new address[](333);
    bool logging = false;
    // Helpers-----------------------------------------------------------------------------

    // generate list of random addresses
    function generateUserAddressListAndDealEther() public {
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
        }
        vm.deal(deployer, 1 ether); // and YOU get an ETH
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
        address _user,
        uint256 _amount,
        uint256 _round
    ) public returns (bytes memory) {
        chainid = block.chainid;
        bytes32 messageHash = keccak256(abi.encodePacked(_user, _amount, _round, chainid));
        bytes32 prefixedHash = prefixed(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, prefixedHash);
        bytes memory signature = toBytesConcat(r, s, v);

        if (logging) {
            emit log_named_bytes32("hash", messageHash);
            emit log_named_bytes("signature", signature);
        }

        return signature;
    }

    function advanceBlockNumberAndTimestampByTimestamp(uint256 _seconds) public {
        uint256 blocks = _seconds / 12; //seconds per block
        advanceBlockNumberAndTimestamp(blocks);
    }

    function advanceBlockNumberAndTimestamp(uint256 _blocks) public {
        for (uint256 i = 0; i < _blocks; i++) {
            blockNumber += 1;
            blockTimestamp += 12; //seconds per block
        }
        vm.warp(blockTimestamp);
        vm.roll(blockNumber);
    }


}