
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
            signer, //signer
            block.timestamp, //start timestamp
            block.timestamp + VESTING_LENGTH //end timestamp
        );
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
    function testVestingFlow() public {
        //1. get signature for total nominal claimable amount of 1000e18
        uint256 nominalTotalAmount = 1000e18;
        bytes memory signature = getSignature(users[0], nominalTotalAmount);

        vm.startPrank(users[0], users[0]);
        //2. claim 1/2 of nominal claimable amount at t=0.5 == 250/500 (500 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 5 / 10);
        uint256 thisClaimAmount = vestingContract.claimableNow(nominalTotalAmount, msg.sender)/2;
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, signature);

        //3. claim 1/2 of remaining nominal claimable amount at t=0.9 == 225/900 (250 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 4 / 10);
        uint256 nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.claimableNow(nominalTotalAmount - nominalClaimedTokens, msg.sender)/2;
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, signature);

        //4. claim remaining nominal claimable amount at t=1 == 250/1000 (0 nominal remains)
        advanceBlockNumberAndTimestampByTimestamp(VESTING_LENGTH * 1 / 10);
        nominalClaimedTokens = vestingContract.claimedNominalTokens(users[0]);
        thisClaimAmount = vestingContract.claimableNow(nominalTotalAmount - nominalClaimedTokens, msg.sender);
        vestingContract.claim(users[0], thisClaimAmount, nominalTotalAmount, signature);

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
    

}