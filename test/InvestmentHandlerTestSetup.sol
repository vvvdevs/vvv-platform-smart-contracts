//SPDX-License-Identifier: MIT

/**
 * Setup for any tests for InvestmentHandler written with Foundry test framework
 */

pragma solidity 0.8.20;

import "lib/forge-std/src/Test.sol";
import { InvestmentHandler } from "contracts/InvestmentHandler.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";

contract InvestmentHandlerTestSetup is Test {
    
    InvestmentHandler public investmentHandler;
    MockERC20 public mockStable;
    MockERC20 public mockProject;

    address[] public users = new address[](10);
    uint public phase = 1;
    uint public latestInvestmentId = 0;
    uint public stableAmount = 1000000 * 1e6; // 1 million usdc
    uint public ownerKey = 12345;
    address ownerAddress = vm.addr(ownerKey);

    struct SignatureStruct {
        address userAddress;
        uint pledgeAmount;
        uint phase;
    }
    
    function setUp() public {
        vm.startPrank(ownerAddress, ownerAddress);
            investmentHandler = new InvestmentHandler();
            mockStable = new MockERC20(6); //usdc decimals
            mockProject = new MockERC20(18); //project token
            investmentHandler.unPause();
        vm.stopPrank();        

        generateUserAddressListAndDealEtherAndMockERC20();
        createInvestment();
    }

    // Helpers-----------------------------------------------------------------------------

    // generate list of random addresses
    function generateUserAddressListAndDealEtherAndMockERC20() public {
        for (uint i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
            mockStable.mint(users[i], stableAmount);
        }
        vm.deal(ownerAddress, 1 ether); // and YOU get an ETH
        mockStable.mint(ownerAddress, stableAmount);
    }

    // create concat'd 65 byte signature that ethers would generate instead of r,s,v
    function toBytesConcat(bytes32 r, bytes32 s, uint8 v) public pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        for (uint i = 0; i < 32; i++) {
            signature[i] = r[i];
            signature[i + 32] = s[i];
        }
        signature[64] = bytes1(v);
        return signature;
    }


    // Additional Setup--------------------------------------------------------------------

    function createInvestment() public {
        vm.startPrank(ownerAddress, ownerAddress);
            investmentHandler.addInvestment(ownerAddress, address(mockStable), 1500000 * 1e18);
            ++latestInvestmentId;
            investmentHandler.setInvestmentProjectTokenAddress(latestInvestmentId, address(mockProject));
        vm.stopPrank();
    }

    function usersInvestRandomAmounts() public {
        for (uint i = 0; i < users.length; i++) {
            
            vm.startPrank(ownerAddress, ownerAddress);
                uint randomAmountWithinBalance = uint(keccak256(abi.encodePacked(block.timestamp, i))) % mockStable.balanceOf(users[i]);

                bytes32 thisMessageHash = keccak256(abi.encodePacked(
                    users[i],
                    randomAmountWithinBalance,
                    phase
                ));

                (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, thisMessageHash);

                bytes memory thisSignature = toBytesConcat(r, s, v);
            vm.stopPrank();


            vm.startPrank(users[i], users[i]);
                mockStable.approve(address(investmentHandler), type(uint).max);
                
                InvestmentHandler.InvestParams memory investParams = InvestmentHandler.InvestParams({
                    investmentId: investmentHandler.latestInvestmentId(),
                    maxInvestableAmount: stableAmount,
                    thisInvestmentAmount: randomAmountWithinBalance,
                    userPhase: 1,
                    kycAddress: users[i],
                    signature: thisSignature
                });
                
                investmentHandler.invest(investParams);
            vm.stopPrank();
        }
    }

}