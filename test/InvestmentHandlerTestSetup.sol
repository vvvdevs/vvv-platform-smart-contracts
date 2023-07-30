//SPDX-License-Identifier: MIT

/**
 * Setup for any tests for InvestmentHandler written with Foundry test framework
 * issues with signature creation being valid...
 */

pragma solidity 0.8.20;

import "lib/forge-std/src/Test.sol"; //for stateless tests

import { InvestmentHandler } from "contracts/InvestmentHandler.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvestmentHandlerTestSetup is Test {
    
    InvestmentHandler public investmentHandler;
    MockERC20 public mockStable;
    MockERC20 public mockProject;

    address[] public users = new address[](10);
    uint8 public phase = 1;
    uint public latestInvestmentIdFromTesting = 0;
    uint128 public stableAmount = 1000000 * 1e6; // 1 million usdc
    uint128 public projectAmount = 5000000000000000 * 1e18; // 1 million project tokens
    
    uint public deployerKey = 1234;
    uint public defaultAdminControllerKey = 12345; //will likely be multisig 
    uint public investmentManagerKey = 123456;
    uint public contributionManagerKey = 1234567;
    uint public refundManagerKey = 12345678;
    uint public signerKey = 123456789;
    
    address deployer = vm.addr(deployerKey);
    address defaultAdminController = vm.addr(defaultAdminControllerKey);
    address investmentManager = vm.addr(investmentManagerKey);
    address contributionManager = vm.addr(contributionManagerKey);
    address refundManager = vm.addr(refundManagerKey);
    address signer = vm.addr(signerKey);

    address sampleUser;
    address sampleKycAddress;

    bool logging = true;

    struct SignatureStruct {
        address userAddress;
        uint pledgeAmount;
        uint phase;
    }
    
    function setUp() public virtual {
        vm.startPrank(deployer, deployer);
            investmentHandler = new InvestmentHandler(defaultAdminController, investmentManager, contributionManager, refundManager);
            mockStable = new MockERC20(6); //usdc decimals
            mockProject = new MockERC20(18); //project token
        vm.stopPrank();        
        createInvestment();
        generateUserAddressListAndDealEtherAndMockERC20();
    }

    // Helpers-----------------------------------------------------------------------------

    // generate list of random addresses
    function generateUserAddressListAndDealEtherAndMockERC20() public {
        for (uint i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
            mockStable.mint(users[i], stableAmount);
        }
        vm.deal(investmentManager, 1 ether); // and YOU get an ETH
        mockStable.mint(investmentManager, stableAmount);

        sampleKycAddress = users[0];
        sampleUser = users[1];
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

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
    }

    function getSignature(address _user, uint120 _amount, uint8 _phase) public returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            _user,
            _amount,
            _phase
        ));
        bytes32 prefixedHash = prefixed(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, prefixedHash);
        bytes memory signature = toBytesConcat(r, s, v);

        if(logging){
            emit log_named_bytes32("hash", messageHash);
            emit log_named_bytes("signature", signature);
        }

        return signature;
    }


    // Additional Setup--------------------------------------------------------------------

    function createInvestment() public {
        vm.startPrank(investmentManager, investmentManager);
            investmentHandler.addInvestment(signer, address(mockStable), stableAmount);
            ++latestInvestmentIdFromTesting;
            investmentHandler.setInvestmentProjectTokenAddress(latestInvestmentIdFromTesting, address(mockProject));
            investmentHandler.setInvestmentProjectTokenAllocation(latestInvestmentIdFromTesting, projectAmount);
            investmentHandler.setInvestmentContributionPhase(latestInvestmentIdFromTesting, phase);
        vm.stopPrank();
    }

    function usersInvestRandomAmounts() public {
        for (uint i = 0; i < users.length; i++) {
            uint112 randomAmountWithinBalance = uint112(uint(keccak256(abi.encodePacked(block.timestamp, i))) % mockStable.balanceOf(users[i]));
            userInvest(users[i], users[i],  randomAmountWithinBalance);
        }
    }

    function userInvest(address _caller, address _kycAddress, uint120 _amount) public {
            vm.startPrank(signer, signer);
                bytes memory thisSignature = getSignature(_kycAddress, _amount, phase);
            vm.stopPrank();

            if(_caller != _kycAddress){
                vm.startPrank(_kycAddress, _kycAddress);
                    investmentHandler.addAddressToKycAddressNetwork(_caller);
                vm.stopPrank();                
            }

            vm.startPrank(_caller, _caller);
                mockStable.approve(address(investmentHandler), type(uint).max);
                
                InvestmentHandler.InvestParams memory investParams = InvestmentHandler.InvestParams({
                    investmentId: uint16(investmentHandler.latestInvestmentId()),
                    thisInvestmentAmount: _amount,
                    maxInvestableAmount: uint120(_amount),
                    userPhase: 1,
                    kycAddress: _kycAddress,
                    signature: thisSignature
                });
                
                investmentHandler.invest(investParams);
            vm.stopPrank();
    }

    function userClaim(address _caller, address _kycAddress) public {
        uint claimableAmount = investmentHandler.computeUserClaimableAllocationForInvestment(_kycAddress, latestInvestmentIdFromTesting);

        vm.startPrank(_caller, _caller);
            investmentHandler.claim(
                latestInvestmentIdFromTesting,
                claimableAmount,
                _caller,
                _kycAddress
            );
        vm.stopPrank();
    }

}