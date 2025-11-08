// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/UserVault.sol";


/// @title Mock HTS Precompile
/// @notice Simulates the Hedera Token Service precompile at 0x167
contract MockHederaTokenService {
    // token => (account => balance)
    mapping(address => mapping(address => int64)) public balances;
    // account => token association status
    mapping(address => mapping(address => bool)) public isAssociated;

    int32 constant SUCCESS = 22; // mimics HederaResponseCodes.SUCCESS

    // Associate a token with an account
    function associateToken(address account, address token) external returns (int32) {
        isAssociated[account][token] = true;
        return SUCCESS;
    }

    // Associate multiple tokens
    function associateTokens(address account, address[] calldata tokens) external returns (int32) {
        for (uint256 i = 0; i < tokens.length; i++) {
            isAssociated[account][tokens[i]] = true;
        }
        return SUCCESS;
    }

    // Transfer token
    function transferToken(
        address token,
        address from,
        address to,
        int64 amount
    ) external returns (int32) {
        require(isAssociated[from][token], "Sender not associated");
        require(isAssociated[to][token], "Receiver not associated");
        balances[token][from] -= amount;
        balances[token][to] += amount;
        return SUCCESS;
    }

    // Get token balance
    function balanceOf(address token, address account) external view returns (int32, int64) {
        if (!isAssociated[account][token]) {
            return (2001, 0); // HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT
        }
        return (SUCCESS, balances[token][account]);
    }
}


contract VaultFactoryTest is Test {

        
        VaultFactory factory;
        address owner = address(0xABCD);
        address user1 = address(0xAAAA);
        address user2 = address(0xBBBB);

        function setUp() public {
            vm.startPrank(owner);
            factory = new VaultFactory(1 ether);
            vm.stopPrank();
        }

        function test_CreateVault_Success() public {
            vm.deal(user1, 5 ether);
            vm.startPrank(user1);
            address vaultAddress = factory.createVault{value: 1 ether}();
            vm.stopPrank();
            assertTrue(factory.hasVault(user1));
            assertEq(factory.getVault(user1), vaultAddress);
            emit log("Vault created successfully!");
            emit log_named_address("User vault address", vaultAddress);
            emit log_named_uint("Factory vault count", factory.getVaultCount());
        }
        
        function test_CreateVault_FailsIfUserAlreadyHasVault() public {
            vm.deal(user1, 5 ether);
            vm.startPrank(user1);
            factory.createVault{value: 1 ether}();
            vm.expectRevert(bytes("VaultFactory: User already has a vault"));
            factory.createVault{value: 1 ether}();
            vm.stopPrank();
        }

        function test_OwnerCanWithdrawFeesAndUpdateFee() public {
            // owner set in setUp
            vm.deal(user1, 5 ether);
            vm.startPrank(user1);
            factory.createVault{value: 1 ether}();
            vm.stopPrank();

            uint256 before = address(this).balance;
            vm.startPrank(owner);
            // change fee
            factory.setCreationFee(2 ether);
            assertEq(factory.getCreationFee(), 2 ether);

            // withdraw fees to owner
            uint256 balance = factory.getBalance();
            address payable to = payable(owner);
            factory.withdrawFees(to);
            vm.stopPrank();

            // factory balance should be zero
            assertEq(factory.getBalance(), 0);
        }
    }

