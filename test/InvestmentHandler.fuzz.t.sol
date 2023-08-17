//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./InvestmentHandlerTestSetup.sol";
import { HandlerForInvestmentHandler } from "./HandlerForInvestmentHandler.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 
Excuse my learning invariant testing during this project :)

Notes:
Following https://mirror.xyz/horsefacts.eth/Jex2YVaO65dda6zEyfM_-DXlXhOWCAoSpOx5PLocYgw to invariant test the InvestmentHandler contract.

The structure of tests here makes sense as if all r/w operations are done in setUp, and only assertions tested in the invariant tests themselves. Each unique setup needs another test contract.

Invariants:
1. The paymentToken balance of the InvestmentHandler contract should be equal to the total amount of paymentTokens deposited by all users.
2. The projectToken balance of the InvestmentHandler contract should be equal to the total amount of projectTokens deposited to the contract minus the total amount of projectTokens (for this investmentId) that have been claimed by users
3. The paymentToken to projectToken ratio should be the same for each user who deposits paymentToken  for a given investmentId

[?] The amount of projectToken a user receives is independent of the time and frequency of claims - this is less-so a contract state invariant and more so a user-outcome invariant maybe. To take a static contract state and then fuzz the contract or handler would not prove this invariant, as each run would require a different order and frequency of claims. 
 
Possible Setbacks:
1. Dividing among many users and different amounts will cause slight rounding errors, requiring a tolerance for the invariant tests.
2. Regarding what claim patterns are "within reason" claiming 1e-18 of a token at a time 10e24 times is not considered a realistic condition, lets consider first a range of 1-100 claims for a particular investment and examine how timing and projectToken supply affect this desired invariant.

Approach:
1. Try both bound and open invariant tests, try redundant tests with both, overkill as much as possible?
 */

contract InvestmentHandlerInvariantTests_Bound is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockERC20(6); //usdc decimals
        mockProject = new MockERC20(18); //project token
        handler = new HandlerForInvestmentHandler(investmentHandler, mockStable, mockProject);
        vm.stopPrank();

        targetContract(address(handler));

        generateUserAddressListAndDealEtherAndMockStable();
        createInvestment_HandlerForInvestmentHandler();
        usersInvestRandomAmounts_HandlerForInvestmentHandler();
        transferProjectTokensTo_HandlerForInvestmentHandler(1_000_000 * 1e6);
        usersClaimRandomAmounts_HandlerForInvestmentHandler();
    }

    /**
     * Invariant 1: The paymentToken balance of the InvestmentHandler contract should be equal to the total amount of paymentTokens deposited by all
     * Note: investmentHandler:invest transferFrom s the paymentToken to the investmentHandler contract, so the balance wont show in the handler, thus we check the investmentHandler balance here
     */
    function invariant_contractPaymentTokenBalanceIsEqualToDeposits() public {
        assertTrue(
            mockStable.balanceOf(address(investmentHandler)) ==
                ghost_bound_investedTotal[ghost_bound_latestInvestmentId]
        );
    }

    /**
     * Invariant 2: The projectToken balance of the InvestmentHandler contract should be equal to the total amount of projectTokens deposited to the contract minus the total amount of projectTokens (for this investmentId) that have been claimed by users.
     */
    function invariant_contractProjectTokenBalanceIsEqualToDepositsMinusClaims() public {
        console.log("contract balance: ", IERC20(mockProject).balanceOf(address(handler)));
        console.log(
            "deposited-claimed: ",
            ghost_bound_depositedProjectTokens[ghost_bound_latestInvestmentId] -
                ghost_bound_claimedTotal[ghost_bound_latestInvestmentId]
        );

        assertTrue(IERC20(mockProject).balanceOf(address(handler)) > 0);
        assertTrue(
            (IERC20(mockProject).balanceOf(address(handler)) ==
                (ghost_bound_depositedProjectTokens[ghost_bound_latestInvestmentId] -
                    ghost_bound_claimedTotal[ghost_bound_latestInvestmentId]))
        );
    }

    /**
     * Invariant 3: The paymentToken to projectToken ratio should be the same for each user who deposits paymentToken and claims projectToken for a given investmentId. Not a strong test, as it only uses 2 addresses.
     */
    function invariant_constantProjectTokenToPaymentTokenRatioPerProject() public {
        assertEq(
            ghost_bound_claimedTotal[ghost_bound_latestInvestmentId] /
                ghost_bound_investedTotal[ghost_bound_latestInvestmentId],
            getProjectToPaymentTokenRatioRandomAddress_HandlerForInvestmentHandler(1)
        );

        assertEq(
            ghost_bound_claimedTotal[ghost_bound_latestInvestmentId] /
                ghost_bound_investedTotal[ghost_bound_latestInvestmentId],
            getProjectToPaymentTokenRatioRandomAddress_HandlerForInvestmentHandler(users.length - 1)
        );
    }
}

//====================================================================================================
// OPEN INVARIANT AND OTHER FUZZ TESTS
//====================================================================================================

contract InvestmentHandlerInvariantTests_Open is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockERC20(6); //usdc decimals
        mockProject = new MockERC20(18); //project token
        vm.stopPrank();

        targetContract(address(investmentHandler));

        generateUserAddressListAndDealEtherAndMockStable();
        createInvestment();
        usersInvestRandomAmounts();
        transferProjectTokensToInvestmentHandler(1_000_000 * 1e6);
        usersClaimRandomAmounts();

        (, , , , investedTotal, , , ) = investmentHandler.investments(
            investmentHandler.latestInvestmentId()
        );
    }

    /**
     * Invariant 1: The paymentToken balance of the InvestmentHandler contract should be equal to the total amount of paymentTokens deposited by all
     */
    function invariant_open_contractPaymentTokenBalanceIsEqualToDeposits() public {
        assertTrue(mockStable.balanceOf(address(investmentHandler)) == investedTotal);
    }

    /**
     * Invariant 2: The projectToken balance of the InvestmentHandler contract should be equal to the total amount of projectTokens deposited to the contract minus the total amount of projectTokens (for this investmentId) that have been claimed by users.
     */
    function invariant_open_contractProjectTokenBalanceIsEqualToDepositsMinusClaims() public {
        console.log("contract balance: ", IERC20(mockProject).balanceOf(address(investmentHandler)));
        console.log(
            "deposited-claimed: ",
            ghost_open_depositedProjectTokens[ghost_open_latestInvestmentId] -
                ghost_open_claimedTotal[ghost_open_latestInvestmentId]
        );

        assertTrue(IERC20(mockProject).balanceOf(address(investmentHandler)) > 0);
        assertTrue(
            (IERC20(mockProject).balanceOf(address(investmentHandler)) ==
                (ghost_open_depositedProjectTokens[ghost_open_latestInvestmentId] -
                    ghost_open_claimedTotal[ghost_open_latestInvestmentId]))
        );
    }

    /**
     * Invariant 3: The paymentToken to projectToken ratio should be the same for each user who deposits paymentToken and claims projectToken for a given investmentId. Not a strong test, as it only uses 2 addresses.
     */
    function invariant_open_constantProjectTokenToPaymentTokenRatioPerProject() public {
        assertEq(
            ghost_open_claimedTotal[ghost_open_latestInvestmentId] /
                ghost_open_investedTotal[ghost_open_latestInvestmentId],
            getProjectToPaymentTokenRatioRandomAddress(1)
        );

        assertEq(
            ghost_open_claimedTotal[ghost_open_latestInvestmentId] /
                ghost_open_investedTotal[ghost_open_latestInvestmentId],
            getProjectToPaymentTokenRatioRandomAddress(users.length - 1)
        );
    }
}

//====================================================================================================
// Misc Fuzz Tests
//====================================================================================================

contract InvestmentHandlerFuzzTests is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            pauser,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockERC20(6); //usdc decimals
        mockProject = new MockERC20(18); //project token
        vm.stopPrank();

        targetContract(address(investmentHandler));

        generateUserAddressListAndDealEtherAndMockStable();
        createInvestment();
        usersInvestRandomAmounts();
        transferProjectTokensToInvestmentHandler(1_000_000 * 1e6);
        usersClaimRandomAmounts();

        (, , , , investedTotal, , , ) = investmentHandler.investments(
            investmentHandler.latestInvestmentId()
        );
    }

    /**
     * Related to invariant 3 - checks for seeing if users' ratio of claimed to invested tokens can change
     */
    function testFuzz_open_compareProjectToPaymentTokenRatio(uint16 _index) public {
        if (_index > 1 && _index < users.length) {
            uint256 ratio1 = getProjectToPaymentTokenRatioRandomAddress(_index - 1);
            uint256 ratio2 = getProjectToPaymentTokenRatioRandomAddress(_index);
            assertEq(ratio1, ratio2);

            console.log("ratio1: ", ratio1);
            console.log("ratio2: ", ratio2);
        }
    }

    /**
     * Fuzz claim
     * Expects revert for all calls, since there is a low chance of guessing all inputs correctly
     */
    function testFuzz_claim(
        uint16 _investmentId,
        uint256 _claimAmount,
        address _tokenRecipient,
        address _kycAddress
    ) public {
        vm.expectRevert();
        investmentHandler.claim(_investmentId, _claimAmount, _tokenRecipient, _kycAddress);
    }

    /**
     * Fuzz invest
     * Expects revert for all calls, since there is a low chance of guessing all inputs correctly
     */
    function testFuzz_invest(
        uint16 investmentId,
        uint120 thisInvestmentAmount,
        uint120 maxInvestableAmount,
        uint8 userPhase,
        address kycAddress,
        bytes calldata signature
    ) public {
        InvestmentHandler.InvestParams memory params = InvestmentHandler.InvestParams(
            investmentId,
            thisInvestmentAmount,
            maxInvestableAmount,
            userPhase,
            kycAddress,
            signature
        );

        vm.expectRevert();
        investmentHandler.invest(params);
    }

    /**
     * Fuzz computeUserTotalAllocationForInvesment
     * Just showing a non-revert
     */
    function testFuzz_computeUserTotalAllocationForInvesment(
        address _kycAddress,
        uint16 _investmentId
    ) public {
        uint256 allocation = investmentHandler.computeUserTotalAllocationForInvesment(
            _kycAddress,
            _investmentId
        );
    }

    /**
     * Fuzz computeUserClaimableAllocationForInvestment
     * Just showing a non-revert
     */
    function testFuzz_computeUserClaimableAllocationForInvestment(
        address _kycAddress,
        uint16 _investmentId
    ) public {
        uint256 allocation = investmentHandler.computeUserTotalAllocationForInvesment(
            _kycAddress,
            _investmentId
        );
    }

    /**
     * Fuzz investmentIsOpen
     * Just showing a non-revert
     */
    function testFuzz_investmentIsOpen(uint16 _investmentId, uint8 _userPhase) public {
        bool isOpen = investmentHandler.investmentIsOpen(_investmentId, _userPhase);
    }

    /**
     * Fuzz addInvestment
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_addInvestment(
        address _signer,
        address _paymentToken,
        uint128 _totalAllocatedPaymentToken,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.addInvestment(
            _signer,
            _paymentToken,
            _totalAllocatedPaymentToken,
            _pauseAfterCall
        );
    }

    /**
     * Fuzz setInvestmentContributionPhase
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_setInvestmentContributionPhase(
        uint16 _investmentId,
        uint8 _contributionPhase,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.setInvestmentContributionPhase(
            _investmentId,
            _contributionPhase,
            _pauseAfterCall
        );
    }

    /**
     * Fuzz setInvestmentPaymentTokenAddress
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_setInvestmentPaymentTokenAddress(
        uint16 _investmentId,
        address _paymentToken,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.setInvestmentPaymentTokenAddress(_investmentId, _paymentToken, _pauseAfterCall);
    }

    /**
     * Fuzz setInvestmentProjectTokenAddress
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_setInvestmentProjectTokenAddress(
        uint16 _investmentId,
        address _projectToken,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.setInvestmentProjectTokenAddress(_investmentId, _projectToken, _pauseAfterCall);
    }

    /**
     * Fuzz setInvestmentProjectTokenAllocation
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_setInvestmentProjectTokenAllocation(
        uint16 _investmentId,
        uint256 _totalAllocatedProjectToken,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.setInvestmentProjectTokenAllocation(
            _investmentId,
            _totalAllocatedProjectToken,
            _pauseAfterCall
        );
    }

    /**
     * Fuzz manualAddContribution
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_manualAddContribution(
        address _kycAddress,
        uint16 _investmentId,
        uint128 _thisInvestmentAmount,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.manualAddContribution(
            _kycAddress,
            _investmentId,
            _thisInvestmentAmount,
            _pauseAfterCall
        );
    }

    /**
     * Fuzz refundUser
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_refundUser(
        address _kycAddress,
        uint16 _investmentId,
        uint128 _thisInvestmentAmount,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.refundUser(_kycAddress, _investmentId, _thisInvestmentAmount, _pauseAfterCall);
    }

    /**
     * Fuzz transferPaymentToken
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_transferPaymentToken(
        uint16 _investmentId,
        address _destinationAddress,
        uint128 _paymentTokenAmount,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.transferPaymentToken(
            _investmentId,
            _destinationAddress,
            _paymentTokenAmount,
            _pauseAfterCall
        );
    }

    /**
     * Fuzz recoverERC20
     * Just showing a revert since function is not called with correct admin user except by chance, so shouldn't happen
     */
    function testFuzz_recoverERC20(
        address _tokenAddress,
        address _destinationAddress,
        uint256 _tokenAmount,
        bool _pauseAfterCall
    ) public {
        vm.expectRevert();
        investmentHandler.recoverERC20(_tokenAddress, _destinationAddress, _tokenAmount, _pauseAfterCall);
    }
}
