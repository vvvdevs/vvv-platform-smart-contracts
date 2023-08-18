//SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { InvestmentHandler } from "contracts/InvestmentHandler.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import "lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev a handler to act between the fuzzer and the investmentHandler contract

contract HandlerForInvestmentHandler is Test {
    InvestmentHandler public investmentHandler;
    MockERC20 public mockStable;
    MockERC20 public mockProject;

    constructor(InvestmentHandler _investmentHandler, MockERC20 _mockStable, MockERC20 _mockProject) {
        investmentHandler = _investmentHandler;
        mockStable = _mockStable;
        mockProject = _mockProject;
    }

    modifier useActor(address _actor) {
        vm.startPrank(_actor, _actor);
        _;
        vm.stopPrank();
    }

    function claim(
        address _caller,
        uint16 _investmentId,
        uint256 _claimAmount,
        address _tokenRecipient,
        address _kycAddress
    ) public useActor(_caller) {
        investmentHandler.claim(_investmentId, _claimAmount, _tokenRecipient, _kycAddress);
    }

    function invest(
        address _caller,
        InvestmentHandler.InvestParams memory _params
    ) public useActor(_caller) {
        mockStable.approve(address(investmentHandler), type(uint256).max);
        investmentHandler.invest(_params);
    }

    function addAddressToKycAddressNetwork(address _caller, address _newAddress) public useActor(_caller) {
        investmentHandler.addAddressToKycAddressNetwork(_newAddress);
    }

    function computeUserClaimableAllocationForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) public view returns (uint256) {
        return investmentHandler.computeUserClaimableAllocationForInvestment(_kycAddress, _investmentId);
    }

    function addInvestment(
        address _caller,
        address _signer,
        address _paymentToken,
        uint128 _totalAllocatedPaymentToken,
        bool _pauseAfterCall
    ) public useActor(_caller) {
        uint256 totalAllocatedPaymentToken = bound(
            _totalAllocatedPaymentToken,
            10_000 * 1e6,
            10_000_000 * 1e6
        );

        investmentHandler.addInvestment(
            _signer,
            _paymentToken,
            uint128(totalAllocatedPaymentToken),
            _pauseAfterCall
        );
    }

    function setInvestmentContributionPhase(
        address _caller,
        uint16 _investmentId,
        uint8 _investmentPhase,
        bool _pauseAfterCall
    ) public useActor(_caller) {
        investmentHandler.setInvestmentContributionPhase(_investmentId, _investmentPhase, _pauseAfterCall);
    }

    function setInvestmentProjectTokenAddress(
        address _caller,
        uint16 _investmentId,
        address _projectTokenAddress,
        bool _pauseAfterCall
    ) public useActor(_caller) {
        investmentHandler.setInvestmentProjectTokenAddress(
            _investmentId,
            _projectTokenAddress,
            _pauseAfterCall
        );
    }

    function setInvestmentProjectTokenAllocation(
        address _caller,
        uint16 _investmentId,
        uint256 _totalTokensAllocated,
        bool _pauseAfterCall
    ) public useActor(_caller) {
        uint16 minId = 1;
        uint16 maxId = 333;
        uint256 minTokens = 1000 * 1e18;

        uint256 boundInvestmentId = bound(_investmentId, minId, maxId);
        uint256 boundTotalTokensAllocated = bound(_totalTokensAllocated, minTokens, type(uint128).max);

        investmentHandler.setInvestmentProjectTokenAllocation(
            uint16(boundInvestmentId),
            boundTotalTokensAllocated,
            _pauseAfterCall
        );
    }

    function latestInvestmentId() public view returns (uint16) {
        return investmentHandler.latestInvestmentId();
    }

    function getTotalInvestedForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) public view returns (uint256) {
        return investmentHandler.getTotalInvestedForInvestment(_kycAddress, _investmentId);
    }

    function getTotalClaimedForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) public view returns (uint256) {
        return investmentHandler.getTotalClaimedForInvestment(_kycAddress, _investmentId);
    }
}
