// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/UserVault.sol";

/// @title Mock HTS Precompile for tests
contract MockHederaTokenService {
    // token => (account => balance)
    mapping(address => mapping(address => int64)) public balances;
    // account => token association status
    mapping(address => mapping(address => bool)) public isAssociated;

    int32 constant SUCCESS = 22; // mimic HederaResponseCodes.SUCCESS
    int32 constant TOKEN_NOT_ASSOCIATED = 2001;

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
            return (TOKEN_NOT_ASSOCIATED, 0);
        }
        return (SUCCESS, balances[token][account]);
    }

    // Helper for tests: set a balance directly
    function setBalance(address token, address account, int64 amount) external {
        balances[token][account] = amount;
    }
}

contract UserVaultTest is Test {
    VaultFactory factory;
    MockHederaTokenService mockHTS;

    address owner = address(0xABCD);
    address user1 = address(0xAAAA);
    address user2 = address(0xBBBB);
    address token = address(0x100);

    address constant HTS_PRECOMPILE = address(0x167);

    function setUp() public {
        vm.startPrank(owner);
        factory = new VaultFactory(0); // free for tests
        vm.stopPrank();

        // deploy mock and copy runtime code to HTS precompile address so UserVault can call it
        mockHTS = new MockHederaTokenService();
        bytes memory code = address(mockHTS).code;
        vm.etch(HTS_PRECOMPILE, code);
    }

    function test_AssociateDepositWithdrawFlow() public {
        // create vault for user1
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
    address vaultAddr = factory.createVault{value: 0}();
    UserVault vault = UserVault(payable(vaultAddr));

        // ensure HTS mock has associations: associate both user1 and vault and recipient
        MockHederaTokenService(HTS_PRECOMPILE).associateToken(vaultAddr, token);
        MockHederaTokenService(HTS_PRECOMPILE).associateToken(user1, token);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(token, user1, 1_000);

        // Owner (user1) calls associateToken on vault which will call HTS precompile
        vault.associateToken(token);

        // deposit 500
        vault.deposit(token, 500);

        // check internal tracked balance
        int64 tracked = vault.getTrackedBalance(token);
        assertEq(int64(500), tracked);

        // prepare recipient
        MockHederaTokenService(HTS_PRECOMPILE).associateToken(user2, token);

        // withdraw to user2
        vault.withdrawTo(token, 300, user2);

        // tracked balance should be 200 now
        assertEq(int64(200), vault.getTrackedBalance(token));

        vm.stopPrank();
    }

    function test_HBARDepositAndWithdraw() public {
        // create vault and send HBAR to it
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
    address vaultAddr = factory.createVault{value: 0}();
    UserVault vault = UserVault(payable(vaultAddr));
        vm.stopPrank();

        // send some HBAR to vault
        vm.deal(address(this), 1 ether);
        (bool s, ) = payable(vaultAddr).call{value: 0.1 ether}("");
        assertTrue(s);

        // owner withdraws HBAR
        vm.startPrank(user1);
        uint256 before = address(user2).balance;
        vault.withdrawHBAR(0.05 ether, payable(user2));
        vm.stopPrank();

        assertEq(address(user2).balance, before + 0.05 ether);
    }
}
