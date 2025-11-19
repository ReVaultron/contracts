// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/VolatilityIndex.sol";
import "../src/RebalanceExecutor.sol";
import "../src/SaucerSwapper.sol";
import "../src/UserVault.sol";
import "../src/interfaces/IHederaTokenService.sol";

/**
 * @title OnChainIntegrationTest
 * @notice Integration tests for ReVaultron system on Hedera testnet
 */
contract OnChainIntegrationTest is Test {
    
    // Known testnet addresses
    address constant PYTH_CONTRACT = 0xa2aa501b19aff244d90cc15a4cf739d2725b5729;
    address constant SWAPPER_ROUTER = 0x0000000000000000000000000000000000159398;
    address constant HTS_PRECOMPILE = address(0x167);
    
    // Contract instances
    VaultFactory public factory;
    VolatilityIndex public volatilityIndex;
    RebalanceExecutor public rebalanceExecutor;
    SaucerSwapper public swapper;
    UserVault public vault;
    
    // Test tokens
    address public tokenA;
    address public tokenB;
    
    // Test users
    address public user1;
    address public user2;
    
    function setUp() public {
        // Setup test environment
        user1 = vm.addr(vm.envUint("PRIVATE_KEY_1"));
        user2 = vm.addr(vm.envUint("PRIVATE_KEY_2"));
        
        vm.startPrank(user1);
        
        // Deploy contracts
        volatilityIndex = new VolatilityIndex(PYTH_CONTRACT);
        swapper = new SaucerSwapper(SWAPPER_ROUTER);
        rebalanceExecutor = new RebalanceExecutor(address(volatilityIndex), address(swapper));
        factory = new VaultFactory(address(rebalanceExecutor));
        
        // Create test tokens
        createTestTokens();
        
        // Configure system
        configureSystem();
        
        vm.stopPrank();
    }
    
    function createTestTokens() internal {
        // Create HTS tokens for testing
        IHederaTokenService.HederaToken memory tokenInfo = IHederaTokenService.HederaToken({
            name: "ReVaultron Test A",
            symbol: "RVA",
            treasury: user1,
            memo: "Test token A",
            tokenSupplyType: true,
            maxSupply: 1000000 * 1e8,
            freezeDefault: false,
            tokenKeys: new IHederaTokenService.TokenKey[](0),
            expiry: IHederaTokenService.Expiry(0, address(0), 0)
        });
        
        (int32 responseA, address createdTokenA) = IHederaTokenService(HTS_PRECOMPILE)
            .createFungibleToken(tokenInfo, 8, 100000 * 1e8);
        require(responseA == 22, "Token A creation failed");
        tokenA = createdTokenA;
        
        tokenInfo.name = "ReVaultron Test B";
        tokenInfo.symbol = "RVB";
        tokenInfo.memo = "Test token B";
        
        (int32 responseB, address createdTokenB) = IHederaTokenService(HTS_PRECOMPILE)
            .createFungibleToken(tokenInfo, 8, 100000 * 1e8);
        require(responseB == 22, "Token B creation failed");
        tokenB = createdTokenB;
    }
    
    function configureSystem() internal {
        // Add price feeds
        bytes32 feedA = 0x0000000000000000000000000000000000000000000000000000000000000001;
        bytes32 feedB = 0x0000000000000000000000000000000000000000000000000000000000000002;
        
        volatilityIndex.addPriceFeed(feedA);
        volatilityIndex.addPriceFeed(feedB);
        volatilityIndex.setAuthorizedUpdater(address(rebalanceExecutor), true);
        volatilityIndex.setAuthorizedUpdater(user1, true);
        
        // Configure swapper
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        swapper.addSupportedTokens(tokens);
        
        // Configure rebalancer
        rebalanceExecutor.setAuthorizedAgent(user1, true);
    }
    
    function testFullWorkflow() public {
        vm.startPrank(user1);
        
        // Create vault
        vault = UserVault(factory.createVault());
        
        // Associate and setup tokens
        address[] memory tokensToAssociate = new address[](2);
        tokensToAssociate[0] = tokenA;
        tokensToAssociate[1] = tokenB;
        
        // Associate tokens with vault and user
        vault.associateTokens(tokensToAssociate);
        IHederaTokenService(HTS_PRECOMPILE).associateToken(user1, tokenA);
        IHederaTokenService(HTS_PRECOMPILE).associateToken(user1, tokenB);
        
        // Add tokens to vault
        vault.addToken(tokenA);
        vault.addToken(tokenB);
        
        // Transfer initial tokens to vault
        int64 initialAmount = 5000 * 1e8; // 5000 tokens each
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenA, user1, address(vault), initialAmount);
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenB, user1, address(vault), initialAmount);
        
        // Deposit tokens
        vault.deposit(tokenA, initialAmount);
        vault.deposit(tokenB, initialAmount);
        
        // Verify balances
        assertEq(vault.tokenBalances(tokenA), initialAmount, "Token A balance mismatch");
        assertEq(vault.tokenBalances(tokenB), initialAmount, "Token B balance mismatch");
        
        vm.stopPrank();
    }
    
    function testVolatilityUpdate() public {
        vm.startPrank(user1);
        
        bytes32 feedId = 0x0000000000000000000000000000000000000000000000000000000000000001;
        
        // Update volatility data (simulating oracle update)
        volatilityIndex.updateVolatility(
            feedId,
            2500, // 25% volatility (2500 bps)
            1000000000, // $10.00 price (with 8 decimal places)
            1000000, // confidence
            -8, // exponent
            block.timestamp
        );
        
        // Verify volatility data
        (uint256 volatilityBps, int64 price, uint64 confidence, int32 expo, uint256 timestamp) = 
            volatilityIndex.volatilityData(feedId);
            
        assertEq(volatilityBps, 2500, "Volatility not updated correctly");
        assertEq(price, 1000000000, "Price not updated correctly");
        assertEq(expo, -8, "Exponent not updated correctly");
        
        vm.stopPrank();
    }
    
    function testRebalancing() public {
        // First run the full workflow
        testFullWorkflow();
        
        vm.startPrank(user1);
        
        // Update volatility to trigger rebalancing threshold
        bytes32 feedId = 0x0000000000000000000000000000000000000000000000000000000000000001;
        volatilityIndex.updateVolatility(feedId, 8000, 1000000000, 1000000, -8, block.timestamp); // 80% volatility
        
        // Check if rebalancing is needed
        bool needsRebalance = rebalanceExecutor.checkRebalanceNeeded(address(vault));
        
        if (needsRebalance) {
            // Execute rebalancing
            rebalanceExecutor.executeRebalance(
                address(vault),
                tokenA, // sell token A
                tokenB, // buy token B
                1000 * 1e8 // amount to rebalance
            );
            
            // Verify rebalancing was executed
            assertTrue(rebalanceExecutor.getRebalanceHistoryLength() > 0, "No rebalance history recorded");
        }
        
        vm.stopPrank();
    }
    
    function testWithdrawal() public {
        testFullWorkflow();
        
        vm.startPrank(user1);
        
        int64 withdrawAmount = 1000 * 1e8; // 1000 tokens
        int64 initialBalance = vault.tokenBalances(tokenA);
        
        // Withdraw tokens
        vault.withdraw(tokenA, withdrawAmount, user1);
        
        // Verify balance updated
        assertEq(vault.tokenBalances(tokenA), initialBalance - withdrawAmount, "Withdrawal balance not updated");
        
        vm.stopPrank();
    }
    
    function testMultiUserScenario() public {
        vm.startPrank(user1);
        
        // User 1 creates vault
        UserVault vault1 = UserVault(factory.createVault());
        
        vm.stopPrank();
        vm.startPrank(user2);
        
        // Associate user2 with tokens
        IHederaTokenService(HTS_PRECOMPILE).associateToken(user2, tokenA);
        IHederaTokenService(HTS_PRECOMPILE).associateToken(user2, tokenB);
        
        // Transfer some tokens to user2 for testing
        vm.stopPrank();
        vm.startPrank(user1);
        
        int64 transferAmount = 10000 * 1e8;
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenA, user1, user2, transferAmount);
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenB, user1, user2, transferAmount);
        
        vm.stopPrank();
        vm.startPrank(user2);
        
        // User 2 creates vault
        UserVault vault2 = UserVault(factory.createVault());
        
        // Setup vault2 similar to vault1
        address[] memory tokensToAssociate = new address[](2);
        tokensToAssociate[0] = tokenA;
        tokensToAssociate[1] = tokenB;
        
        vault2.associateTokens(tokensToAssociate);
        vault2.addToken(tokenA);
        vault2.addToken(tokenB);
        
        // Transfer and deposit
        int64 depositAmount = 2000 * 1e8;
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenA, user2, address(vault2), depositAmount);
        IHederaTokenService(HTS_PRECOMPILE).transferToken(tokenB, user2, address(vault2), depositAmount);
        
        vault2.deposit(tokenA, depositAmount);
        vault2.deposit(tokenB, depositAmount);
        
        // Verify independent operation
        assertTrue(address(vault1) != address(vault2), "Vaults should be different");
        assertEq(vault2.tokenBalances(tokenA), depositAmount, "User2 vault balance incorrect");
        
        vm.stopPrank();
    }
}
