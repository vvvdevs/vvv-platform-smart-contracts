//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
import { VVVNodes } from "contracts/nodes/VVVNodes.sol";
import { VVVNodesTestBase } from "./VVVNodesTestBase.sol";
import { VVVToken } from "contracts/tokens/VvvToken.sol";

contract VVVNodesFuzzTest is VVVNodesTestBase {
    using Strings for uint256;

    struct TestData {
        uint256 tokenId;
        uint256 totalNetClaimedTokens;
        uint256 totalUnvestedChange;
        uint256 cycleNetStakedAmount;
        uint256 cycleNetUnstakedAmount;
        uint256 baseTimeElapsed;
    }

    function setUp() public {
        vm.startPrank(deployer, deployer);
        AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        NodesInstance = new VVVNodes(address(AuthRegistry), defaultBaseURI, activationThreshold);
        vm.stopPrank();
    }

    function testFuzz_claimStakeUnstakeMultipleTimes(
        uint256 _initialStakeAmount,
        uint256 _timeElapsed,
        uint256 _unstakeAmount,
        uint256 _numCycles
    ) public {
        //stake between 2 and 10x activation threshold
        uint256 initialStakeAmount = bound(
            _initialStakeAmount,
            activationThreshold * 2,
            activationThreshold * 10
        );
        uint256 timeElapsed = bound(_timeElapsed, 60 minutes, 525600 minutes * 2); //pass between 1 second and 2 years per cycle
        uint256 numCycles = 5; //bound(_numCycles, 1, 20); //number of interaction cycles

        TestData memory testData = TestData({
            tokenId: 1,
            totalNetClaimedTokens: 0,
            totalUnvestedChange: 0,
            cycleNetStakedAmount: 0,
            cycleNetUnstakedAmount: 0,
            baseTimeElapsed: 360 minutes
        });

        vm.startPrank(sampleUser, sampleUser);
        // mint using placeholder mint function to mint tokenId = 1
        NodesInstance.mint(sampleUser);

        vm.deal(address(NodesInstance), type(uint128).max);
        vm.deal(sampleUser, type(uint128).max);

        NodesInstance.stake{ value: initialStakeAmount }(testData.tokenId);

        //ensure node is active
        bool isActiveAfterStake = NodesInstance.isNodeActive(testData.tokenId);
        assertTrue(isActiveAfterStake);

        for (uint256 i = 0; i < numCycles; i++) {
            testData.cycleNetStakedAmount = 0;
            testData.cycleNetUnstakedAmount = 0;

            // Simulate time passing
            advanceBlockNumberAndTimestampInSeconds(timeElapsed + testData.baseTimeElapsed);

            //check balance and claimable before and after claim
            uint256 preClaimBalance = address(sampleUser).balance;
            (uint256 preClaimUnvestedAmount, , , , ) = NodesInstance.tokenData(testData.tokenId);

            //if there are any claimable tokens, claim them
            if (i % 2 == 0 && preClaimUnvestedAmount > 0) {
                try NodesInstance.claim(testData.tokenId) {} catch {}
            }

            // //every so often, unstake amount, pass some time, and claim
            // //a portion of these runs will deactivate the node
            // else if (i % 2 == 1) {
            //     // see how much there is to unstake and unstake a random amount which
            //     (,,,,uint256 stakedAmount) = NodesInstance.tokenData(testData.tokenId);
            //     uint256 unstakeAmount = bound(_unstakeAmount, 1e18, stakedAmount);

            //     NodesInstance.unstake(testData.tokenId, unstakeAmount);
            //     testData.cycleNetUnstakedAmount += unstakeAmount; // Update total staked amount

            //     advanceBlockNumberAndTimestampInSeconds(timeElapsed + testData.baseTimeElapsed);
            //     try NodesInstance.claim(testData.tokenId) {} catch {}
            // }

            //every so often if deactivated, stake to reactivate,
            //pass some time, and claim
            // if (i % 2 == 1) {
            //     NodesInstance.stake{ value: initialStakeAmount }(testData.tokenId);
            //     testData.cycleNetStakedAmount += initialStakeAmount; // Update total staked amount
            //     advanceBlockNumberAndTimestampInSeconds(timeElapsed + testData.baseTimeElapsed);
            //     try NodesInstance.claim(testData.tokenId) {} catch {}
            // }

            (uint256 postClaimUnvestedAmount, , , , ) = NodesInstance.tokenData(testData.tokenId);
            uint256 postClaimUnvestedDifference = preClaimUnvestedAmount - postClaimUnvestedAmount;

            uint256 postClaimBalance = address(sampleUser).balance;

            /**
            The claimed tokens are: the difference in balance - the net staked amount + the net unstaked amount for this cycle
            The claimed tokens should be equal to the unvested change given VVVNodes:_updateClaimableFromVesting updating both
            claimable and unvested at the same time and in equal amounts.
             */
            emit log_named_uint("postClaimUnvestedAmount", postClaimUnvestedAmount);
            emit log_named_uint("preClaimUnvestedAmount", preClaimUnvestedAmount);
            emit log_named_uint("postClaimUnvestedDifference", postClaimUnvestedDifference);
            emit log_named_uint("postClaimBalance", postClaimBalance);
            emit log_named_uint("preClaimBalance", preClaimBalance);
            uint256 rawBalanceDifference = postClaimBalance > preClaimBalance
                ? postClaimBalance - preClaimBalance
                : preClaimBalance - postClaimBalance;
            emit log_named_uint("balance difference", rawBalanceDifference);
            emit log_named_uint("cycleNetStakedAmount", testData.cycleNetStakedAmount);
            emit log_named_uint("cycleNetUnstakedAmount", testData.cycleNetUnstakedAmount);

            uint256 claimedTokens = rawBalanceDifference - testData.cycleNetStakedAmount;

            testData.totalUnvestedChange += postClaimUnvestedDifference;
            testData.totalNetClaimedTokens += claimedTokens;

            assertEq(claimedTokens, postClaimUnvestedDifference);
        }

        vm.stopPrank();

        assertEq(testData.totalNetClaimedTokens, testData.totalUnvestedChange);

        emit log_named_uint("totalUnvestedChange", testData.totalUnvestedChange);
        emit log_named_uint("totalNetClaimedTokens", testData.totalNetClaimedTokens);
    }
}
