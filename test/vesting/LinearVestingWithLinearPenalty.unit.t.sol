
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { LinearVestingWithLinearPenaltyBase } from "./LinearVestingWithLinearPenaltyBase.sol";
import { MockERC20 } from "contracts/mock/MockERC20.sol";
import { LinearVestingWithLinearPenalty } from "contracts/vesting/LinearVestingWithLinearPenalty.sol";

contract LinearVestingWithLinearPenaltyUnitTests is LinearVestingWithLinearPenaltyBase {

    function setUp() public {
        vm.startPrank(deployer, deployer);

        mockToken = new MockERC20(18);

        vestingContract = new LinearVestingWithLinearPenalty(
            address(mockToken), //vested token (needs to give minting permission)
            signer //signer
        );

        uint256 roundNumber = 1;
        uint256 startTimestamp = block.timestamp;
        vestingContract.setVestingParams(roundNumber, startTimestamp, startTimestamp + VESTING_LENGTH, NON_PENALIZED_PROPORTIONS[0]);

        roundNumber = 2;
        startTimestamp = block.timestamp;
        vestingContract.setVestingParams(roundNumber, startTimestamp, startTimestamp + VESTING_LENGTH, NON_PENALIZED_PROPORTIONS[1]);

        vm.stopPrank();
        generateUserAddressListAndDealEther();
        targetContract(address(vestingContract));
    }
    
    /**
     * @dev deployment test
     */
    function testDeployment() public {
        assertTrue(address(vestingContract) != address(0));
    }
    /**
        @dev test the vesting math
            1. get signature for total nominal claimable amount of 1000
            2. claim 1/2 of nominal claimable amount at t=0.5 == 250/500 (500 nominal remains)
            3. claim 1/2 of remaining nominal claimable amount at t=0.9 == 225/900 (250 nominal remains)
            4. claim remaining nominal claimable amount at t=1 == 250/1000 (0 nominal remains)
            5. confirm a total claimed amount of 725 +/- 0.1% to allow for some truncation error
     */
    function testVestingFlowWithoutInitialUnpenalizedAmount() public {
        //1. get signature for total nominal claimable amount of 1000e18
        uint256 nominalTotalAmount = 1000e18;
        uint256 investmentRound = 1;
        bytes memory signature = getSignature(users[0], nominalTotalAmount, investmentRound);

        vm.startPrank(users[0], users[0]);
        //2. claim 1/2 of nominal claimable amount at t=0.5 == 250/500 (500 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 5 / 10);
        uint256 thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount, investmentRound)/2;
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        //3. claim 1/2 of remaining nominal claimable amount at t=0.9 == 225/900 (250 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 4 / 10);
        uint256 nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount - nominalClaimedTokens, investmentRound)/2;
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        //4. claim remaining nominal claimable amount at t=1 == 250/1000 (0 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 1 / 10);
        nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount - nominalClaimedTokens, investmentRound);
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        //5. confirm a total claimed amount of 725
        uint256 expectedClaimedAmount = 725e18;
        uint256 actualClaimedAmount = vestingContract.claimedActualTokens(users[0]);
        
        emit log_named_uint("expectedClaimedAmount", expectedClaimedAmount);
        emit log_named_uint("actualClaimedAmount", actualClaimedAmount);

        assertTrue(
            actualClaimedAmount > (expectedClaimedAmount * 999 / 1000) && 
            actualClaimedAmount < (expectedClaimedAmount * 1001 / 1000)
        );

        vm.stopPrank();

    }   

    /**
        @dev should operate similarly to above with the difference of there being an initial unpenalized claim amount

        1. user is allotted 1000 nominal tokens
        2. 10% is unpenalized, 90% is penalized
        3. user claims 500 nominal tokens at t=0.5
        4. should see that 1000 - 100 - (400/0.5) nominal tokens are claimed, leaving 100 nominal tokens remaining
        5. user claims 100 nominal tokens at t=1.0, a total of 600 nominal tokens are claimed
        6. check total within 0.1% tolerance
     */

    function testVestingFlowWithInitialUnpenalizedAmount() public {
        //1. get signature for total nominal claimable amount of 1000e18
        uint256 nominalTotalAmount = 1000e18;
        uint256 investmentRound = 2;
        bytes memory signature = getSignature(users[0], nominalTotalAmount, investmentRound);

        vm.startPrank(users[0], users[0]);
        //2. claim 1/2 of nominal claimable amount - at t=0.5 == 500 total == 100 actual unpenalized==100 nominal, 400 actual penalized==800 nominal (100 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 5 / 10);
        uint256 thisClaimAmount = nominalTotalAmount/2; //500e18
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);
        
        uint256 claimedActual1 = vestingContract.claimedActualTokens(users[0]);
        uint256 claimedNominal1 = vestingContract.claimedNominalTokens(users[0]);
        uint256 claimableNowCheck1 = vestingContract.nominalToActual(nominalTotalAmount - claimedNominal1, investmentRound);
        emit log_named_uint("claimedActualTokens1 (unp. + pen.)", claimedActual1/1e18);
        emit log_named_uint("claimedNominalTokens1 (unp. + pen.)", claimedNominal1/1e18);
        emit log_named_uint("claimableNowCheck1", claimableNowCheck1/1e18);

        //3. claim remaining nominal (100) at t>1
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 10);
        uint256 nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount - nominalClaimedTokens, investmentRound);
        emit log_named_uint("thisClaimAmount", thisClaimAmount/1e18);
        emit log_named_uint("nominalClaimedTokens", nominalClaimedTokens/1e18);

        vestingContract.claim(msg.sender, thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        uint256 claimedActual2 = vestingContract.claimedActualTokens(users[0]);
        uint256 claimedNominal2 = vestingContract.claimedNominalTokens(users[0]);
        uint256 claimableNowCheck2 = vestingContract.nominalToActual(nominalTotalAmount - claimedNominal2, investmentRound);
        emit log_named_uint("claimedActual2 (unp. + pen.)", claimedActual2/1e18);
        emit log_named_uint("claimedNominal2 (unp. + pen.)", claimedNominal2/1e18);
        emit log_named_uint("claimableNowCheck2", claimableNowCheck2/1e18);

        //4. confirm a total claimed amount of ~600
        uint256 expectedClaimedAmount = 600e18;
        uint256 actualClaimedAmount = vestingContract.claimedActualTokens(users[0]);
        emit log_named_uint("expectedClaimedAmount", expectedClaimedAmount);
        emit log_named_uint("actualClaimedAmount", actualClaimedAmount);

        assertTrue(
            actualClaimedAmount > (expectedClaimedAmount * 999 / 1000) && 
            actualClaimedAmount < (expectedClaimedAmount * 1001 / 1000)
        );
    }

    /// @dev ensures that a user cannot claim more than their allotted amount in a single case. This should be tested more thoroughly
    function testFailClaimMoreAfterLimit() public {
        //1. get signature for total nominal claimable amount of 1000e18
        uint256 nominalTotalAmount = 1000e18;
        uint256 investmentRound = 2;
        bytes memory signature = getSignature(users[0], nominalTotalAmount, investmentRound);

        vm.startPrank(users[0], users[0]);
        //2. claim 1/2 of nominal claimable amount - at t=0.5 == 500 total == 100 actual unpenalized==100 nominal, 400 actual penalized==800 nominal (100 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 5 / 10);
        uint256 thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount, investmentRound); //500e18
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        //3. claim remaining nominal (100) at t>1
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 10);
        uint256 nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount, investmentRound);

        //should fail here
        vestingContract.claim(msg.sender, thisClaimAmount, nominalTotalAmount, investmentRound, signature);   

    }

    /// @dev ensures no truncation occurrs if waiting full vesting period
    function testFullAmountAtEndOfVesting() public {
        uint256 nominalTotalAmount = 1000e18;
        uint256 investmentRound = 1;
        bytes memory signature = getSignature(users[0], nominalTotalAmount, investmentRound);

        vm.startPrank(users[0], users[0]);

        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 10);
        uint256 nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        uint256 thisClaimAmount = vestingContract.nominalToActual(nominalTotalAmount - nominalClaimedTokens, investmentRound);
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, investmentRound, signature);

        emit log_named_uint("claimedActualTokens", vestingContract.claimedActualTokens(users[0]));
        assertTrue(vestingContract.claimedActualTokens(users[0]) == nominalTotalAmount);

        vm.stopPrank();
    }
    

}