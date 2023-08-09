//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./InvestmentHandlerTestSetup.sol";
import { HandlerForInvestmentHandler } from "./HandlerForInvestmentHandler.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * Excuse my learning invariant testing during this project :)
 *
 * Notes:
 * Following https://mirror.xyz/horsefacts.eth/Jex2YVaO65dda6zEyfM_-DXlXhOWCAoSpOx5PLocYgw to invariant test the InvestmentHandler contract.
 *
 * Invariants:
 * 1. The paymentToken balance of the InvestmentHandler contract should be equal to the total amount of paymentTokens deposited by all users.
 * 2. The projectToken balance of the InvestmentHandler contract should be equal to the total amount of projectTokens deposited to the contract minus the total amount of projectTokens (for this investmentId) that have been claimed by users
 * 3. The paymentToken to projectToken ratio should be the same for each user who deposits paymentToken
 * 4. The amount of projectToken a user receives is independent of the time and frequency of claims
 *
 * Possible Setbacks:
 * 1. Dividing among many users and different amounts will cause slight rounding errors, requiring a tolerance for the invariant tests.
 * 2. Regarding what claim patterns are "within reason" claiming 1e-18 of a token at a time 10e24 times is not considered a realistic condition, lets consider first a range of 1-100 claims for a particular investment and examine how timing and projectToken supply affect this desired invariant.
 *
 * Approach:
 * 1. Create a handler contract that will call InvestmentHandler functions and keep track of state variables outside of the contract.
 */

contract InvestmentHandlerInvariantTests is InvestmentHandlerTestSetup {
    function setUp() public {
        vm.startPrank(deployer, deployer);
        investmentHandler = new InvestmentHandler(
            defaultAdminController,
            investmentManager,
            contributionManager,
            refundManager
        );
        mockStable = new MockStable(6); //usdc decimals
        mockProject = new MockProject(18); //project token
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
                ghost_investedTotal[ghost_latestInvestmentId]
        );
    }

    /**
     * Invariant 2: The projectToken balance of the InvestmentHandler contract should be equal to the total amount of projectTokens deposited to the contract minus the total amount of projectTokens (for this investmentId) that have been claimed by users.
     */
    function invariant_contractProjectTokenBalanceIsEqualToDepositsMinusClaims() public {
        console.log("contract balance: ", IERC20(mockProject).balanceOf(address(handler)));
        console.log(
            "deposited-claimed: ",
            ghost_depositedProjectTokens[ghost_latestInvestmentId] -
                ghost_claimedTotal[ghost_latestInvestmentId]
        );

        assertTrue(IERC20(mockProject).balanceOf(address(handler)) > 0);
        assertTrue(
            (IERC20(mockProject).balanceOf(address(handler)) ==
                (ghost_depositedProjectTokens[ghost_latestInvestmentId] -
                    ghost_claimedTotal[ghost_latestInvestmentId]))
        );
    }

    /**
     * Invariant 3: The paymentToken to projectToken ratio should be the same for each user who deposits paymentToken and claims projectToken
     *
     * How to get this to run with many addresses? Perhaps better as a regular fuzz test with an address input? Perhaps that is possible
     * Requires that the user whose activity is used to create the project/payment ratio has invested more than 0
     */
    function invariant_constantProjectTokenToPaymentTokenRatioPerProject() public {
        uint index = 9;
        address user = users[index];
        uint totalClaimed = handler.getTotalClaimedForInvestment(user, ghost_latestInvestmentId);
        uint remainingClaimable = handler.computeUserClaimableAllocationForInvestment(
            user,
            ghost_latestInvestmentId
        );
        uint investedAmount = handler.getTotalInvestedForInvestment(user, ghost_latestInvestmentId);
        uint projectToPaymentRatio = Math.mulDiv(totalClaimed + remainingClaimable, 1, investedAmount);

        uint projectToPaymentRatio2 = getProjectToPaymentTokenRatioRandomAddress_HandlerForInvestmentHandler(
                index
            );

        console.log("totalClaimed: ", totalClaimed);
        console.log("remainingClaimable: ", remainingClaimable);
        console.log("investedAmount: ", investedAmount);
        console.log("projectToPaymentRatio: ", projectToPaymentRatio);
        console.log("projectToPaymentRatio2: ", projectToPaymentRatio2);

        assertEq(projectToPaymentRatio, projectToPaymentRatio2);

        assertEq(
            ghost_claimedTotal[ghost_latestInvestmentId] / ghost_investedTotal[ghost_latestInvestmentId],
            projectToPaymentRatio
        );
    }

    /**
     * Invariant 4: The amount of projectToken a user receives is independent of the time and frequency of claims
     */
    function invariant_timeIndependentTokenClaimCorrectAmount() public {
        assertEq()
    }
}
