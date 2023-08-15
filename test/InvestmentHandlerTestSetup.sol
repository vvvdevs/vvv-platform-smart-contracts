//SPDX-License-Identifier: MIT

/**
 * @dev Setup for any tests for InvestmentHandler written with Foundry test framework
 *
 * BIG NOTE: I'm bad a naming things. I learned about handler testing after I had named the contract InvestmentHandler, so the handler for the InvestmentHandler is called HandlerForInvestmentHandler.
 */

pragma solidity ^0.8.20;

import "lib/forge-std/src/Test.sol"; //for stateless tests

import { InvestmentHandler } from "contracts/InvestmentHandler.sol";
import { MockStable } from "contracts/mock/MockStable.sol";
import { MockProject } from "contracts/mock/MockProject.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HandlerForInvestmentHandler } from "test/HandlerForInvestmentHandler.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract InvestmentHandlerTestSetup is Test {
    InvestmentHandler public investmentHandler;
    MockStable public mockStable;
    MockProject public mockProject;

    HandlerForInvestmentHandler public handler;

    address[] public users = new address[](333);
    uint8 public phase = 1;
    uint128 public stableAmount = 1_000_000 * 1e6; // 1 million usdc
    uint128 public projectAmount = 5_000_000_000 * 1e18;

    uint256 public deployerKey = 1234;
    uint256 public defaultAdminControllerKey = 12345; //will likely be multisig
    uint256 public investmentManagerKey = 123456;
    uint256 public contributionManagerKey = 1234567;
    uint256 public refundManagerKey = 12345678;
    uint256 public signerKey = 123456789;
    uint256 public projectSenderKey = 1234567890;
    uint256 public chainid;

    address deployer = vm.addr(deployerKey);
    address defaultAdminController = vm.addr(defaultAdminControllerKey);
    address investmentManager = vm.addr(investmentManagerKey);
    address contributionManager = vm.addr(contributionManagerKey);
    address refundManager = vm.addr(refundManagerKey);
    address signer = vm.addr(signerKey);
    address projectSender = vm.addr(projectSenderKey);

    address sampleUser;
    address sampleKycAddress;
    address sampleProjectTreasury;

    bool pauseAfterCall = false;

    bool logging = false;

    uint256 blockNumber;
    uint256 blockTimestamp;
    uint128 investedTotal;

    struct SignatureStruct {
        address userAddress;
        uint256 pledgeAmount;
        uint256 phase;
    }

    //added for use with invariant testing
    // bound testing
    uint16 public ghost_bound_latestInvestmentId = 0;
    mapping(uint256 id => uint256 amount) public ghost_bound_investedTotal;
    mapping(uint256 id => uint256 amount) public ghost_bound_claimedTotal;
    mapping(uint256 id => uint256 amount) public ghost_bound_depositedProjectTokens;
    mapping(uint256 id => mapping(address => uint256)) public ghost_bound_userInvestedTotal;
    mapping(uint256 id => mapping(address => uint256)) public ghost_bound_userClaimedTotal;

    // open testing
    uint16 public ghost_open_latestInvestmentId = 0;
    mapping(uint256 id => uint256 amount) public ghost_open_investedTotal;
    mapping(uint256 id => uint256 amount) public ghost_open_claimedTotal;
    mapping(uint256 id => uint256 amount) public ghost_open_depositedProjectTokens;
    mapping(uint256 id => mapping(address => uint256)) public ghost_open_userInvestedTotal;
    mapping(uint256 id => mapping(address => uint256)) public ghost_open_userClaimedTotal;

    // Helpers-----------------------------------------------------------------------------

    // generate list of random addresses
    function generateUserAddressListAndDealEtherAndMockStable() public {
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i)))));
            vm.deal(users[i], 1 ether); // and YOU get an ETH
            mockStable.mint(users[i], stableAmount);
        }
        vm.deal(investmentManager, 1 ether); // and YOU get an ETH
        mockStable.mint(investmentManager, stableAmount);

        sampleKycAddress = users[0];
        sampleUser = users[1];

        sampleProjectTreasury = address(
            uint160(uint256(keccak256(abi.encodePacked(string("sampleTreasury!!!"), uint256(1234)))))
        );
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
        uint16 _investmentId,
        address _user,
        uint120 _amount,
        uint8 _phase
    ) public returns (bytes memory) {
        chainid = block.chainid;
        bytes32 messageHash = keccak256(abi.encodePacked(_investmentId, _user, _amount, _phase, chainid));
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
    // INVESTMENT HANDLER SETUP FUNCTIONS (OPEN INVARIANT TESTING)
    //==================================================================================================

    function createInvestment() public {
        vm.startPrank(investmentManager, investmentManager);
        investmentHandler.addInvestment(
            signer,
            address(mockStable),
            uint128(stableAmount * users.length),
            pauseAfterCall
        );
        ++ghost_open_latestInvestmentId; //during addInvestment, contract's investmentId is incremented
        investmentHandler.setInvestmentProjectTokenAddress(
            investmentHandler.latestInvestmentId(),
            address(mockProject),
            pauseAfterCall
        );
        investmentHandler.setInvestmentProjectTokenAllocation(
            investmentHandler.latestInvestmentId(),
            projectAmount,
            pauseAfterCall
        );
        investmentHandler.setInvestmentContributionPhase(
            investmentHandler.latestInvestmentId(),
            phase,
            pauseAfterCall
        );
        vm.stopPrank();
    }

    function mintProjectTokensToInvestmentHandler() public {
        vm.startPrank(projectSender, projectSender);
        mockProject.mint(address(investmentHandler), projectAmount);
        vm.stopPrank();
    }

    function usersInvestRandomAmounts() public {
        for (uint256 i = 0; i < users.length; i++) {
            uint112 randomAmountWithinBalance = uint112(
                uint256(keccak256(abi.encodePacked(block.timestamp, i))) % mockStable.balanceOf(users[i])
            );
            userInvest(ghost_open_latestInvestmentId, users[i], users[i], randomAmountWithinBalance);
        }
    }

    function userInvest(
        uint16 _investmentId,
        address _caller,
        address _kycAddress,
        uint120 _amount
    ) public {
        vm.startPrank(signer, signer);
        bytes memory thisSignature = getSignature(_investmentId, _kycAddress, _amount, phase);
        vm.stopPrank();

        if (_caller != _kycAddress) {
            vm.startPrank(_kycAddress, _kycAddress);
            investmentHandler.addAddressToKycAddressNetwork(_caller);
            vm.stopPrank();
        }

        vm.startPrank(_caller, _caller);
        mockStable.approve(address(investmentHandler), type(uint256).max);

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

        //update ghosts
        ghost_open_investedTotal[ghost_open_latestInvestmentId] += _amount;
        ghost_open_userInvestedTotal[ghost_open_latestInvestmentId][_caller] += _amount;
    }

    function userClaim(address _caller, address _kycAddress, uint256 _amount) public {
        uint256 claimableAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
            _kycAddress,
            investmentHandler.latestInvestmentId()
        );

        if (_amount == 0) {
            _amount = claimableAmount;
        }

        vm.startPrank(_caller, _caller);
        investmentHandler.claim(investmentHandler.latestInvestmentId(), _amount, _caller, _kycAddress);
        vm.stopPrank();

        //update ghosts
        ghost_open_claimedTotal[ghost_open_latestInvestmentId] += _amount;
        ghost_open_userClaimedTotal[ghost_open_latestInvestmentId][_caller] += _amount;
    }

    function usersClaimRandomAmounts() public {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 claimableAmount = investmentHandler.computeUserClaimableAllocationForInvestment(
                users[i],
                investmentHandler.latestInvestmentId()
            );
            if (claimableAmount == 0) {
                userClaim(users[i], users[i], claimableAmount);
            }
        }
    }

    function transferProjectTokensToInvestmentHandler(uint256 _amount) public {
        vm.startPrank(projectSender, projectSender);
        mockProject.mint(address(investmentHandler), _amount);
        vm.stopPrank();
        //update ghosts
        ghost_open_depositedProjectTokens[ghost_open_latestInvestmentId] += _amount;
    }

    function getProjectToPaymentTokenRatioRandomAddress(uint256 _index) public view returns (uint256) {
        address user = users[_index];
        uint totalClaimed = investmentHandler.getTotalClaimedForInvestment(
            user,
            ghost_open_latestInvestmentId
        );
        uint remainingClaimable = investmentHandler.computeUserClaimableAllocationForInvestment(
            user,
            ghost_open_latestInvestmentId
        );
        uint investedAmount = investmentHandler.getTotalInvestedForInvestment(
            user,
            ghost_open_latestInvestmentId
        );
        uint projectToPaymentRatio = Math.mulDiv(totalClaimed + remainingClaimable, 1, investedAmount);
        return projectToPaymentRatio;
    }

    //==================================================================================================
    // HANDLER FOR INVESTMENTHANDLER HELPERS (BOUND INVARIANT TESTS)
    // amazing clear naming I know
    // tracks ghost variables for use in invariant testing as well
    // part of following https://mirror.xyz/horsefacts.eth/Jex2YVaO65dda6zEyfM_-DXlXhOWCAoSpOx5PLocYgw
    //==================================================================================================

    function createInvestment_HandlerForInvestmentHandler() public {
        handler.addInvestment(
            investmentManager,
            signer,
            address(mockStable),
            stableAmount,
            pauseAfterCall
        );
        ++ghost_bound_latestInvestmentId; //during addInvestment, contract's investmentId is incremented
        handler.setInvestmentProjectTokenAddress(
            investmentManager,
            ghost_bound_latestInvestmentId,
            address(mockProject),
            pauseAfterCall
        );
        handler.setInvestmentProjectTokenAllocation(
            investmentManager,
            ghost_bound_latestInvestmentId,
            projectAmount,
            pauseAfterCall
        );
        handler.setInvestmentContributionPhase(
            investmentManager,
            ghost_bound_latestInvestmentId,
            phase,
            pauseAfterCall
        );
    }

    function usersInvestRandomAmounts_HandlerForInvestmentHandler() public {
        for (uint256 i = 0; i < users.length; i++) {
            uint112 randomAmountWithinBalance = uint112(
                uint256(keccak256(abi.encodePacked(block.timestamp, i))) % mockStable.balanceOf(users[i])
            );
            userInvest_HandlerForInvestmentHandler(
                ghost_bound_latestInvestmentId,
                users[i],
                users[i],
                users[i],
                randomAmountWithinBalance
            );
        }
    }

    function userInvest_HandlerForInvestmentHandler(
        uint16 _investmentId,
        address _caller,
        address _newAddress,
        address _kycAddress,
        uint120 _amount
    ) public {
        vm.startPrank(signer, signer);
        bytes memory thisSignature = getSignature(_investmentId, _kycAddress, _amount, phase);
        vm.stopPrank();

        if (_caller != _kycAddress) {
            handler.addAddressToKycAddressNetwork(_caller, _newAddress);
        }

        vm.startPrank(_caller, _caller);
        mockStable.approve(address(handler), type(uint256).max);
        vm.stopPrank();

        InvestmentHandler.InvestParams memory investParams = InvestmentHandler.InvestParams({
            investmentId: uint16(handler.latestInvestmentId()),
            thisInvestmentAmount: _amount,
            maxInvestableAmount: uint120(_amount),
            userPhase: 1,
            kycAddress: _kycAddress,
            signature: thisSignature
        });

        handler.invest(_caller, investParams);

        //update ghosts
        ghost_bound_investedTotal[ghost_bound_latestInvestmentId] += _amount;
        ghost_bound_userInvestedTotal[ghost_bound_latestInvestmentId][_caller] += _amount;
    }

    function userClaim_HandlerForInvestmentHandler(
        address _caller,
        address _kycAddress,
        uint256 _amount
    ) public {
        uint256 claimableAmount = handler.computeUserClaimableAllocationForInvestment(
            _kycAddress,
            ghost_bound_latestInvestmentId
        );

        if (_amount == 0) {
            _amount = claimableAmount;
        }

        handler.claim(_caller, ghost_bound_latestInvestmentId, _amount, _caller, _kycAddress);

        //update ghosts
        ghost_bound_claimedTotal[ghost_bound_latestInvestmentId] += _amount;
        ghost_bound_userClaimedTotal[ghost_bound_latestInvestmentId][_caller] += _amount;
    }

    function usersClaimRandomAmounts_HandlerForInvestmentHandler() public {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 claimableAmount = handler.computeUserClaimableAllocationForInvestment(
                users[i],
                ghost_bound_latestInvestmentId
            );
            if (claimableAmount > 0) {
                userClaim_HandlerForInvestmentHandler(users[i], users[i], claimableAmount);
            }
        }
    }

    function transferProjectTokensTo_HandlerForInvestmentHandler(uint256 _amount) public {
        vm.startPrank(projectSender, projectSender);
        mockProject.mint(projectSender, _amount);
        mockProject.transfer(address(handler), _amount);
        vm.stopPrank();

        //update ghosts
        ghost_bound_depositedProjectTokens[ghost_bound_latestInvestmentId] += _amount;
    }

    function getProjectToPaymentTokenRatioRandomAddress_HandlerForInvestmentHandler(
        uint256 _index
    ) public view returns (uint256) {
        address user = users[_index];
        uint totalClaimed = handler.getTotalClaimedForInvestment(user, ghost_bound_latestInvestmentId);
        uint remainingClaimable = handler.computeUserClaimableAllocationForInvestment(
            user,
            ghost_bound_latestInvestmentId
        );
        uint investedAmount = handler.getTotalInvestedForInvestment(user, ghost_bound_latestInvestmentId);
        uint projectToPaymentRatio = Math.mulDiv(totalClaimed + remainingClaimable, 1, investedAmount);
        return projectToPaymentRatio;
    }
}
