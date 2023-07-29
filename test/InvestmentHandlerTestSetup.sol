//SPDX-License-Identifier: MIT

/**
 * Setup for any tests for InvestmentHandler written with Foundry test framework
 * issues with signature creation being valid...
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
    uint8 public phase = 1;
    uint public latestInvestmentId = 0;
    uint128 public stableAmount = 1000000 * 1e6; // 1 million usdc
    uint128 public projectAmount = 5000000000000000 * 1e18; // 1 million project tokens
    
    uint public deployerKey = 1234;
    uint public defaultAdminControllerKey = 12345; //will likely be multisig 
    uint public investmentManagerKey = 123456;
    uint public contributionAndRefundManagerKey = 1234567;
    uint public signerKey = 12345678;
    
    address deployer = vm.addr(deployerKey);
    address defaultAdminController = vm.addr(defaultAdminControllerKey);
    address investmentManager = vm.addr(investmentManagerKey);
    address contributionAndRefundManager = vm.addr(contributionAndRefundManagerKey);
    address signer = vm.addr(signerKey);

    struct SignatureStruct {
        address userAddress;
        uint pledgeAmount;
        uint phase;
    }
    
    function setUp() public virtual {
        vm.startPrank(deployer, deployer);
            investmentHandler = new InvestmentHandler(defaultAdminController, investmentManager, contributionAndRefundManager);
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

    function getSignature(address _user, uint120 _amount, uint8 _phase) public view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            _user,
            _amount,
            _phase
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageHash);
        return toBytesConcat(r, s, v);
    }


    // Additional Setup--------------------------------------------------------------------

    function createInvestment() public {
        vm.startPrank(investmentManager, investmentManager);
            investmentHandler.addInvestment(signer, address(mockStable), stableAmount);
            ++latestInvestmentId;
            investmentHandler.setInvestmentProjectTokenAddress(latestInvestmentId, address(mockProject));
            investmentHandler.setInvestmentProjectTokenAllocation(latestInvestmentId, projectAmount);
            investmentHandler.setInvestmentContributionPhase(latestInvestmentId, phase);
        vm.stopPrank();
    }

    function usersInvestRandomAmounts() public {
        for (uint i = 0; i < users.length; i++) {
            uint112 randomAmountWithinBalance = uint112(uint(keccak256(abi.encodePacked(block.timestamp, i))) % mockStable.balanceOf(users[i]));
            userInvest(users[i], users[i],  randomAmountWithinBalance);
        }
    }

    function userInvest(address _caller, address _kycAddress, uint112 _amount) public {
            vm.startPrank(signer, signer);
                bytes memory thisSignature = getSignature(_kycAddress, _amount, phase);
            vm.stopPrank();

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
        uint128 claimableAmount = investmentHandler.computeUserClaimableAllocationForInvestment(_kycAddress, latestInvestmentId);

        vm.startPrank(_caller, _caller);
            investmentHandler.claim(
                latestInvestmentId,
                claimableAmount,
                _caller,
                _kycAddress
            );
        vm.stopPrank();
    }

}