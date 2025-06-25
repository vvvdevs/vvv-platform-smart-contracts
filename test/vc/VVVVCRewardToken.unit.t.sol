//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { VVVVCTestBase } from "test/vc/VVVVCTestBase.sol";
import { VVVVCRewardToken } from "contracts/vc/VVVVCRewardToken.sol";
import { VVVAuthorizationRegistry } from "contracts/auth/VVVAuthorizationRegistry.sol";
import { VVVAuthorizationRegistryChecker } from "contracts/auth/VVVAuthorizationRegistryChecker.sol";

/**
 * @title VVVVCRewardToken Unit Tests
 * @dev use "forge test --match-contract VVVVCRewardTokenUnitTests" to run tests
 * @dev use "forge coverage --match-contract VVVVCRewardToken" to run coverage
 */
contract VVVVCRewardTokenUnitTests is VVVVCTestBase {
    VVVVCRewardToken RewardTokenInstance;

    /// @notice Role for reward token minting
    bytes32 rewardTokenMinterRole = keccak256("REWARD_TOKEN_MINTER_ROLE");

    /// @notice Sample investment rounds for testing
    uint256[] sampleInvestmentRounds = [1, 2, 3, 4, 5];

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

        // Set permission for setBaseTokenURI function
        bytes4 setBaseTokenURISelector = RewardTokenInstance.setBaseTokenURI.selector;
        AuthRegistry.setPermission(
            address(RewardTokenInstance),
            setBaseTokenURISelector,
            rewardTokenMinterRole
        );

        vm.stopPrank();
    }

    /// @notice Tests deployment of VVVVCRewardToken
    function testDeployment() public {
        assertTrue(address(RewardTokenInstance) != address(0));
        assertEq(RewardTokenInstance.name(), "REWARD");
        assertEq(RewardTokenInstance.symbol(), "REWARD");
        assertEq(RewardTokenInstance.currentTokenId(), 0);
    }

    /// @notice Tests successful minting of a reward token
    function testMint() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        vm.startPrank(ledgerManager, ledgerManager);

        RewardTokenInstance.mint(recipient, investmentRound);

        vm.stopPrank();

        assertEq(RewardTokenInstance.currentTokenId(), 1);
        assertEq(RewardTokenInstance.ownerOf(1), recipient);
        assertEq(RewardTokenInstance.tokenIdToInvestmentRound(1), investmentRound);
    }

    /// @notice Tests minting multiple tokens
    function testMintMultiple() public {
        address[] memory recipients = new address[](3);
        recipients[0] = sampleUser;
        recipients[1] = sampleKycAddress;
        recipients[2] = address(uint160(0xBEEF));

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < recipients.length; i++) {
            RewardTokenInstance.mint(recipients[i], sampleInvestmentRounds[i]);
        }

        vm.stopPrank();

        assertEq(RewardTokenInstance.currentTokenId(), 3);

        for (uint256 i = 1; i <= 3; i++) {
            assertEq(RewardTokenInstance.ownerOf(i), recipients[i - 1]);
            assertEq(RewardTokenInstance.tokenIdToInvestmentRound(i), sampleInvestmentRounds[i - 1]);
        }
    }

    /// @notice Tests that unauthorized users cannot mint tokens
    function testMintUnauthorized() public {
        vm.startPrank(sampleUser, sampleUser);

        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        RewardTokenInstance.mint(sampleUser, sampleInvestmentRounds[0]);

        vm.stopPrank();
    }

    /// @notice Tests that tokens are soulbound and cannot be transferred
    function testTokenIsSoulbound() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Try to transfer the token
        vm.startPrank(recipient, recipient);

        vm.expectRevert(VVVVCRewardToken.TokenIsSoulbound.selector);
        RewardTokenInstance.transferFrom(recipient, sampleKycAddress, 1);

        vm.stopPrank();
    }

    /// @notice Tests that tokens cannot be approved for transfer
    function testCannotApproveTransfer() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Try to approve transfer
        vm.startPrank(recipient, recipient);

        vm.expectRevert(VVVVCRewardToken.TokenIsSoulbound.selector);
        RewardTokenInstance.approve(sampleKycAddress, 1);

        vm.stopPrank();
    }

    /// @notice Tests that tokens cannot be approved for all
    function testCannotApproveForAll() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Try to approve for all
        vm.startPrank(recipient, recipient);

        vm.expectRevert(VVVVCRewardToken.TokenIsSoulbound.selector);
        RewardTokenInstance.setApprovalForAll(sampleKycAddress, true);

        vm.stopPrank();
    }

    /// @notice Tests tokenURI function returns correct placeholder
    function testTokenURI() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Check tokenURI returns token ID as string
        assertEq(RewardTokenInstance.tokenURI(1), "1");
    }

    /// @notice Tests tokenURI reverts for non-existent token
    function testTokenURINonExistentToken() public {
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 1));
        RewardTokenInstance.tokenURI(1);
    }

    /// @notice Tests RewardTokenMinted event emission
    function testRewardTokenMintedEvent() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        vm.startPrank(ledgerManager, ledgerManager);

        vm.expectEmit(true, true, true, true);
        emit VVVVCRewardToken.RewardTokenMinted(1, recipient, investmentRound);

        RewardTokenInstance.mint(recipient, investmentRound);

        vm.stopPrank();
    }

    /// @notice Tests that token IDs increment correctly
    function testTokenIdIncrement() public {
        address recipient = sampleUser;

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < 5; i++) {
            uint256 expectedTokenId = i + 1;
            RewardTokenInstance.mint(recipient, sampleInvestmentRounds[i]);
            assertEq(RewardTokenInstance.currentTokenId(), expectedTokenId);
        }

        vm.stopPrank();
    }

    /// @notice Tests that the same recipient can receive multiple tokens
    function testSameRecipientMultipleTokens() public {
        address recipient = sampleUser;

        vm.startPrank(ledgerManager, ledgerManager);

        for (uint256 i = 0; i < 3; i++) {
            RewardTokenInstance.mint(recipient, sampleInvestmentRounds[i]);
        }

        vm.stopPrank();

        assertEq(RewardTokenInstance.balanceOf(recipient), 3);
        assertEq(RewardTokenInstance.ownerOf(1), recipient);
        assertEq(RewardTokenInstance.ownerOf(2), recipient);
        assertEq(RewardTokenInstance.ownerOf(3), recipient);
    }

    /// @notice Tests that zero address cannot be used as recipient
    function testMintToZeroAddress() public {
        vm.startPrank(ledgerManager, ledgerManager);
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidReceiver(address)", address(0)));
        RewardTokenInstance.mint(address(0), sampleInvestmentRounds[0]);
        vm.stopPrank();
    }

    /// @notice Tests ERC721 standard functions work correctly
    function testERC721StandardFunctions() public {
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Test balanceOf
        assertEq(RewardTokenInstance.balanceOf(recipient), 1);
        assertEq(RewardTokenInstance.balanceOf(sampleKycAddress), 0);

        // Test ownerOf
        assertEq(RewardTokenInstance.ownerOf(1), recipient);
    }

    /// @notice Tests that the contract supports ERC721 interface
    function testSupportsERC721Interface() public {
        bytes4 erc721InterfaceId = 0x80ac58cd;
        assertTrue(RewardTokenInstance.supportsInterface(erc721InterfaceId));
    }

    /// @notice Tests that the contract supports ERC721Metadata interface
    function testSupportsERC721MetadataInterface() public {
        bytes4 erc721MetadataInterfaceId = 0x5b5e139f;
        assertTrue(RewardTokenInstance.supportsInterface(erc721MetadataInterfaceId));
    }

    /// @notice Tests that the contract does not support invalid interface
    function testDoesNotSupportInvalidInterface() public {
        bytes4 invalidInterfaceId = 0x12345678;
        assertFalse(RewardTokenInstance.supportsInterface(invalidInterfaceId));
    }

    /// @notice Tests setting and using the baseTokenURI
    function testSetBaseTokenURIAndTokenURI() public {
        string memory base = "https://example.com/metadata/";
        uint256 investmentRound = sampleInvestmentRounds[0];
        address recipient = sampleUser;

        // Only admin can set baseTokenURI
        vm.startPrank(ledgerManager, ledgerManager);
        emit VVVVCRewardToken.BaseTokenURISet(base);
        RewardTokenInstance.setBaseTokenURI(base);
        vm.stopPrank();

        // Mint a token
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(recipient, investmentRound);
        vm.stopPrank();

        // Token URI should be base + tokenId
        assertEq(RewardTokenInstance.tokenURI(1), string(abi.encodePacked(base, "1")));
    }

    /// @notice Tests that only admin can set the baseTokenURI
    function testSetBaseTokenURIUnauthorized() public {
        string memory base = "https://example.com/metadata/";
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVAuthorizationRegistryChecker.UnauthorizedCaller.selector);
        RewardTokenInstance.setBaseTokenURI(base);
        vm.stopPrank();
    }

    /// @notice Tests that approvals are always blocked (prevents listing on marketplaces)
    function testSetApprovalForAllAlwaysReverts() public {
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCRewardToken.TokenIsSoulbound.selector);
        RewardTokenInstance.setApprovalForAll(address(0xBEEF), true);
        vm.stopPrank();
    }

    function testApproveAsOwnerAlwaysReverts() public {
        // Mint a token to sampleUser
        uint256 investmentRound = sampleInvestmentRounds[0];
        vm.startPrank(ledgerManager, ledgerManager);
        RewardTokenInstance.mint(sampleUser, investmentRound);
        vm.stopPrank();

        // Try to approve as owner
        vm.startPrank(sampleUser, sampleUser);
        vm.expectRevert(VVVVCRewardToken.TokenIsSoulbound.selector);
        RewardTokenInstance.approve(address(0xBEEF), 1);
        vm.stopPrank();
    }
}
