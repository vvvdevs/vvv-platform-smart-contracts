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
        uint256 initialStakeAmount = bound(
            _initialStakeAmount,
            activationThreshold,
            activationThreshold * 2
        );
        uint256 timeElapsed = bound(_timeElapsed, 60 minutes, 525600 minutes * 2); //pass between 1 second and 2 years per cycle
        uint256 unstakeAmount = bound(_unstakeAmount, activationThreshold, initialStakeAmount);
        uint256 numCycles = bound(_numCycles, 1, 20); //roughly 20 cycles of attempting interactions

        uint256 tokenId = 1;
        uint256 totalClaimedAmount = 0;
        uint256 totalUnvestedChange = 0;
        uint256 unclaimedCycles = 0;
        uint256 claimedCycles = 0;

        vm.startPrank(sampleUser, sampleUser);
        // mint using placeholder mint function to mint tokenId = 1
        NodesInstance.mint(sampleUser);

        vm.deal(address(NodesInstance), type(uint128).max);
        vm.deal(sampleUser, type(uint128).max);

        NodesInstance.stake{ value: initialStakeAmount }(tokenId);

        //ensure node is active
        bool isActiveAfterStake = NodesInstance.isNodeActive(tokenId);
        assertTrue(isActiveAfterStake);

        // Check the claimed amount is as expected
        // struct TokenData {
        //     uint256 unvestedAmount; //Remaining tokens to be vested, starts at 60% of $VVV initially locked in each node
        //     uint256 vestingSince; //timestamp of most recent token activation or claim
        //     uint256 claimableAmount; //claimable $VVV across vesting, transaction, and launchpad yield sources
        //     uint256 amountToVestPerSecond; //amount of $VVV to vest per second
        //     uint256 stakedAmount; //total staked $VVV for the node
        // }

        for (uint256 i = 0; i < numCycles; i++) {
            // Simulate time passing
            advanceBlockNumberAndTimestampInSeconds(timeElapsed);
            advanceBlockNumberAndTimestampInSeconds(2 weeks);

            //check balance and claimable before and after claim
            uint256 preClaimBalance = address(sampleUser).balance;
            (uint256 preClaimUnvestedAmount, , , , ) = NodesInstance.tokenData(tokenId);

            //if there are any claimable tokens, claim them
            if (numCycles % 2 == 0 && preClaimUnvestedAmount > 0) {
                NodesInstance.claim(tokenId);
                ++claimedCycles;
            }
            //every so often, unstake a random amount, pass some time, and claim.
            //a portion of these runs will deactivate the node
            else if (numCycles % 2 == 1) {
                NodesInstance.unstake(tokenId, unstakeAmount);
                advanceBlockNumberAndTimestampInSeconds(timeElapsed);
                NodesInstance.claim(tokenId);

                //every so often if deactivated, stake to reactivate,
                //pass some time, and claim
                if (numCycles % 3 == 0) {
                    NodesInstance.stake{ value: initialStakeAmount }(tokenId);
                    advanceBlockNumberAndTimestampInSeconds(timeElapsed);
                    NodesInstance.claim(tokenId);
                }
                ++claimedCycles;
            } else {
                ++unclaimedCycles;
            }

            (uint256 postClaimUnvestedAmount, , , , ) = NodesInstance.tokenData(tokenId);
            uint256 postClaimUnvestedDifference = preClaimUnvestedAmount - postClaimUnvestedAmount;

            uint256 postClaimBalance = address(sampleUser).balance;
            uint256 claimedAmount = postClaimBalance - preClaimBalance;

            totalUnvestedChange += postClaimUnvestedDifference;
            totalClaimedAmount += claimedAmount;

            assertEq(claimedAmount, postClaimUnvestedDifference);
        }

        vm.stopPrank();

        assertEq(totalClaimedAmount, totalUnvestedChange);

        emit log_named_uint("unclaimedCycles", unclaimedCycles);
        emit log_named_uint("claimedCycles", claimedCycles);
        emit log_named_uint("totalUnvestedChange", totalUnvestedChange);
        emit log_named_uint("totalClaimedAmount", totalClaimedAmount);
    }
}
