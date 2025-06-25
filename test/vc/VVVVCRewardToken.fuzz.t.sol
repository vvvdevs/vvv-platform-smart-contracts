//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { VVVVCRewardToken } from "contracts/vc/VVVVCRewardToken.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title VVVVCRewardToken Fuzz Tests
 * @dev use "forge test --match-contract VVVVCRewardTokenFuzzTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCRewardToken" to run coverage
 */
contract VVVVCRewardTokenFuzzTests is VVVVCTestBase {
    using Strings for uint256;

    VVVVCRewardToken RewardTokenInstance;

    /// @notice Role for reward token minting
    bytes32 rewardTokenMinterRole = keccak256("REWARD_TOKEN_MINTER_ROLE");

    /// @notice sets up the reward token contract and authorization
    function setUp() public {
        vm.startPrank(deployer, deployer);

        // Deploy auth registry if not already deployed
        if (address(AuthRegistry) == address(0)) {
            AuthRegistry = new VVVAuthorizationRegistry(defaultAdminTransferDelay, deployer);
        }

        // Deploy reward token
        RewardTokenInstance = new VVVVCRewardToken(address(AuthRegistry));

        // Grant reward token minter role to ledger manager
        AuthRegistry.grantRole(rewardTokenMinterRole, ledgerManager);

        // Set permission for mint function
        bytes4 mintSelector = RewardTokenInstance.mint.selector;
        AuthRegistry.setPermission(address(RewardTokenInstance), mintSelector, rewardTokenMinterRole);

        vm.stopPrank();
    }

    /// @notice Fuzz test for minting with various investment rounds
    /// @param _investmentRound The investment round to test
    /// @param _recipient The recipient address to test
    function testFuzz_Mint(uint256 _investmentRound, address _recipient) public {
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != address(RewardTokenInstance));
        vm.assume(_recipient.code.length == 0); // Only EOAs

        uint256 initialTokenId = RewardTokenInstance.currentTokenId();

        vm.startPrank(ledgerManager, ledgerManager);

        RewardTokenInstance.mint(_recipient, _investmentRound);

        vm.stopPrank();

        assertEq(RewardTokenInstance.currentTokenId(), initialTokenId + 1);
        assertEq(RewardTokenInstance.ownerOf(initialTokenId + 1), _recipient);
        assertEq(RewardTokenInstance.tokenIdToInvestmentRound(initialTokenId + 1), _investmentRound);
    }

    /// @notice Fuzz test for minting multiple tokens to the same recipient
    /// @param _count The number of tokens to mint
    /// @param _recipient The recipient address
    function testFuzz_MintMultipleToSameRecipient(uint8 _count, address _recipient) public {
        vm.assume(_count > 0 && _count <= 10); // Limit to reasonable range
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != address(RewardTokenInstance));

        uint256 initialTokenId = RewardTokenInstance.currentTokenId();

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < _count; i++) {
            RewardTokenInstance.mint(_recipient, i + 1);
        }

        vm.stopPrank();

        assertEq(RewardTokenInstance.currentTokenId(), initialTokenId + _count);
        assertEq(RewardTokenInstance.balanceOf(_recipient), _count);

        for (uint256 i = 1; i <= _count; i++) {
            assertEq(RewardTokenInstance.ownerOf(initialTokenId + i), _recipient);
            assertEq(RewardTokenInstance.tokenIdToInvestmentRound(initialTokenId + i), i);
        }
    }

    /// @notice Fuzz test for tokenURI with various token IDs
    /// @param _tokenId The token ID to test
    function testFuzz_TokenURI(uint256 _tokenId) public {
        vm.assume(_tokenId > 0 && _tokenId <= 1000); // Reasonable range

        // Set baseTokenURI to empty string for consistent testing
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.setBaseTokenURI("");

        // Mint tokens up to the test token ID
        for (uint256 i = 1; i <= _tokenId; i++) {
            RewardTokenInstance.mint(sampleUser, i);
        }
        vm.stopPrank();

        // Test tokenURI for the specific token ID
        string memory uri = RewardTokenInstance.tokenURI(_tokenId);
        assertEq(uri, _tokenId.toString());
    }

    /// @notice Fuzz test for getInvestmentRound with various token IDs
    /// @param _tokenId The token ID to test
    function testFuzz_GetInvestmentRound(uint256 _tokenId) public {
        vm.assume(_tokenId > 0 && _tokenId <= 1000); // Reasonable range

        // Mint tokens up to the test token ID
        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 1; i <= _tokenId; i++) {
            RewardTokenInstance.mint(sampleUser, i * 100); // Use different investment rounds
        }

        vm.stopPrank();

        // Test getInvestmentRound for the specific token ID
        uint256 investmentRound = RewardTokenInstance.tokenIdToInvestmentRound(_tokenId);
        assertEq(investmentRound, _tokenId * 100);
    }

    /// @notice Fuzz test for balanceOf with various addresses
    /// @param _recipient The recipient address to test
    function testFuzz_BalanceOf(address _recipient) public {
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != address(RewardTokenInstance));
        vm.assume(_recipient.code.length == 0); // Only EOAs

        uint256 mintCount = 3; // Mint 3 tokens to the recipient

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < mintCount; i++) {
            RewardTokenInstance.mint(_recipient, i + 1);
        }

        vm.stopPrank();

        assertEq(RewardTokenInstance.balanceOf(_recipient), mintCount);
    }

    /// @notice Fuzz test for ownerOf with various token IDs
    /// @param _tokenId The token ID to test
    function testFuzz_OwnerOf(uint256 _tokenId) public {
        vm.assume(_tokenId > 0 && _tokenId <= 100); // Reasonable range

        address recipient = sampleUser;

        // Mint tokens up to the test token ID
        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 1; i <= _tokenId; i++) {
            RewardTokenInstance.mint(recipient, i);
        }

        vm.stopPrank();

        // Test ownerOf for the specific token ID
        assertEq(RewardTokenInstance.ownerOf(_tokenId), recipient);
    }

    /// @notice Fuzz test for unauthorized minting attempts
    /// @param _unauthorizedCaller The unauthorized caller address
    /// @param _recipient The intended recipient
    /// @param _investmentRound The investment round
    function testFuzz_UnauthorizedMint(
        address _unauthorizedCaller,
        address _recipient,
        uint256 _investmentRound
    ) public {
        vm.assume(_unauthorizedCaller != ledgerManager);
        vm.assume(_unauthorizedCaller != address(0));
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != address(RewardTokenInstance));
        vm.assume(_recipient.code.length == 0); // Only EOAs

        uint256 initialTokenId = RewardTokenInstance.currentTokenId();

        vm.startPrank(_unauthorizedCaller, _unauthorizedCaller);

        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        RewardTokenInstance.mint(_recipient, _investmentRound);

        vm.stopPrank();

        // Verify no token was minted
        assertEq(RewardTokenInstance.currentTokenId(), initialTokenId);
    }

    /// @notice Fuzz test for soulbound transfer attempts
    /// @param _tokenId The token ID to attempt to transfer
    function testFuzz_SoulboundTransfer(uint256 _tokenId) public {
        vm.assume(_tokenId > 0 && _tokenId <= 100); // Reasonable range

        address recipient = sampleUser;
        address newOwner = sampleKycAddress;

        // Mint tokens up to _tokenId so that _tokenId exists
        vm.startPrank(ledgerManager, ledgerManager);
        for (uint256 i = 1; i <= _tokenId; i++) {
            RewardTokenInstance.mint(recipient, i);
        }
        vm.stopPrank();

        // Attempt to transfer the token
        vm.startPrank(recipient, recipient);
        vm.expectRevert(); // Accept any revert
        RewardTokenInstance.transferFrom(recipient, newOwner, _tokenId);
        vm.stopPrank();
    }

    /// @notice Fuzz test for token ID increment pattern
    /// @param _mintCount The number of tokens to mint
    function testFuzz_TokenIdIncrement(uint8 _mintCount) public {
        vm.assume(_mintCount > 0 && _mintCount <= 20); // Reasonable range

        uint256 initialTokenId = RewardTokenInstance.currentTokenId();

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < _mintCount; i++) {
            uint256 expectedTokenId = initialTokenId + i + 1;
            RewardTokenInstance.mint(sampleUser, i + 1);
            assertEq(RewardTokenInstance.currentTokenId(), expectedTokenId);
        }

        vm.stopPrank();

        assertEq(RewardTokenInstance.currentTokenId(), initialTokenId + _mintCount);
    }
}
