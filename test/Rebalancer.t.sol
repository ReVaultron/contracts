// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/RebalanceExecutor.sol";
import "../src/UserVault.sol";
import "../src/VolatilityIndex.sol";
import "../src/SaucerSwapper.sol";
import "../src/interfaces/IHederaTokenService.sol";
import {ISaucerSwapRouter, ISaucerSwapFactory, ISaucerSwapPair} from "../src/interfaces/ISaucerSwapRouter.sol";
import "../src/libraries/HederaResponseCodes.sol";

/// @title Mock HTS Precompile
/// @notice Simulates the Hedera Token Service precompile at 0x167
contract MockHederaTokenService {
    // token => (account => balance)
    mapping(address => mapping(address => int64)) public balances;
    // account => token association status
    mapping(address => mapping(address => bool)) public isAssociated;

    int32 constant SUCCESS = 22; // mimics HederaResponseCodes.SUCCESS
    int32 constant TOKEN_NOT_ASSOCIATED = 2001;

    // Associate a token with an account
    function associateToken(address account, address token) external returns (int32) {
        isAssociated[account][token] = true;
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
        require(balances[token][from] >= amount, "Insufficient balance");
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

    // Approve spender to spend tokens
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external returns (int32) {
        // Check if caller (token owner) is associated with the token
        // In HTS, you need to be associated to approve
        address tokenOwner = msg.sender;
        if (!isAssociated[tokenOwner][token]) {
            return TOKEN_NOT_ASSOCIATED;
        }
        // For testing, we just return success
        // In real HTS, this would set an allowance
        return SUCCESS;
    }

    // Helper for tests: set a balance directly
    function setBalance(address token, address account, int64 amount) external {
        balances[token][account] = amount;
    }

    // Helper for tests: associate token
    function associateTokenFor(address account, address token) external {
        isAssociated[account][token] = true;
    }
}

/// @title Mock VolatilityIndex
/// @notice Mock contract for testing RebalanceExecutor
contract MockVolatilityIndex {
    mapping(bytes32 => uint256) public volatilityData;
    
    function getVolatility(bytes32 priceFeedId) external view returns (uint256) {
        return volatilityData[priceFeedId];
    }
    
    function setVolatility(bytes32 priceFeedId, uint256 volatility) external {
        volatilityData[priceFeedId] = volatility;
    }
}

/// @title Mock SaucerSwap Router
/// @notice Mock contract for testing SaucerSwapper
contract MockSaucerSwapRouter is ISaucerSwapRouter {
    bool public shouldRevert;
    string public revertReason;
    uint256 public mockAmountOut;
    uint256 public mockAmountReceived;
    address public whbar;
    address public factoryAddress;
    
    // Exchange rate: 1 tokenIn = 2 tokenOut (for testing)
    uint256 constant EXCHANGE_RATE = 2;
    
    constructor(address _whbar, address _factory) {
        whbar = _whbar;
        factoryAddress = _factory;
    }
    
    function setShouldRevert(bool _shouldRevert, string memory _reason) external {
        shouldRevert = _shouldRevert;
        revertReason = _reason;
    }
    
    function setMockAmountOut(uint256 _amountOut) external {
        mockAmountOut = _amountOut;
    }
    
    function setMockAmountReceived(uint256 _amountReceived) external {
        mockAmountReceived = _amountReceived;
    }
    
    function WHBAR() external view returns (address) {
        return whbar;
    }
    
    function factory() external view returns (address) {
        return factoryAddress;
    }
    
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        // Don't revert in getAmountsOut - let swapExactTokensForTokens handle the revert
        // This allows getAmountOut to work even when swap will fail
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        uint256 currentAmount = amountIn;
        for (uint256 i = 1; i < path.length; i++) {
            if (mockAmountOut > 0 && i == path.length - 1) {
                currentAmount = mockAmountOut;
            } else {
                currentAmount = currentAmount * EXCHANGE_RATE;
            }
            amounts[i] = currentAmount;
        }
        
        return amounts;
    }
    
    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;
        
        uint256 currentAmount = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            currentAmount = currentAmount / EXCHANGE_RATE;
            amounts[i - 1] = currentAmount;
        }
        
        return amounts;
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        if (shouldRevert) {
            revert(revertReason);
        }
        
        require(block.timestamp <= deadline, "Deadline expired");
        
        uint256 amountOut;
        if (mockAmountReceived > 0) {
            amountOut = mockAmountReceived;
        } else {
            amountOut = amountIn * EXCHANGE_RATE;
        }
        
        require(amountOut >= amountOutMin, "Insufficient output");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;
        
        // Transfer tokens via HTS (simulated)
        address HTS_PRECOMPILE = address(0x167);
        // Transfer tokenIn from caller to this contract
        (bool success1, bytes memory result1) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                path[0],
                msg.sender,
                address(this),
                int64(uint64(amountIn))
            )
        );
        require(success1, "HTS transfer failed");
        int32 responseCode1 = abi.decode(result1, (int32));
        require(responseCode1 == HederaResponseCodes.SUCCESS, "HTS transfer failed");
        
        // Transfer tokenOut from this contract to recipient
        (bool success2, bytes memory result2) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                path[path.length - 1],
                address(this),
                to,
                int64(uint64(amountOut))
            )
        );
        require(success2, "HTS transfer failed");
        int32 responseCode2 = abi.decode(result2, (int32));
        require(responseCode2 == HederaResponseCodes.SUCCESS, "HTS transfer failed");
        
        return amounts;
    }
    
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        revert("Not implemented in mock");
    }
    
    function swapExactHBARForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        revert("Not implemented in mock");
    }
    
    function swapTokensForExactHBAR(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        revert("Not implemented in mock");
    }
    
    function swapExactTokensForHBAR(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        revert("Not implemented in mock");
    }
}

/// @title Mock SaucerSwap Factory
/// @notice Mock contract for testing SaucerSwapper
contract MockSaucerSwapFactory is ISaucerSwapFactory {
    mapping(address => mapping(address => address)) public pairs;
    address public mockPair;
    
    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function setMockPair(address _pair) external {
        mockPair = _pair;
    }
    
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair) {
        address pairAddress = pairs[tokenA][tokenB];
        if (pairAddress != address(0)) {
            return pairAddress;
        }
        // Return mock pair if no specific pair set
        return mockPair;
    }
    
    function allPairsLength() external pure returns (uint256) {
        return 0;
    }
    
    function allPairs(uint256) external pure returns (address) {
        return address(0);
    }
    
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair) {
        revert("Not implemented in mock");
    }
}

/// @title Mock UserVault
/// @notice Mock contract for testing RebalanceExecutor
contract MockUserVault {
    mapping(address => int64) public balances;
    address public owner;
    address constant HTS_PRECOMPILE = address(0x167);
    
    constructor(address _owner) {
        owner = _owner;
    }
    
    function getBalance(address token) external view returns (int64) {
        // Return actual HTS balance if available, otherwise internal balance
        (bool success, bytes memory result) = HTS_PRECOMPILE.staticcall(
            abi.encodeWithSelector(
                IHederaTokenService.balanceOf.selector,
                token,
                address(this)
            )
        );
        if (success) {
            (int32 responseCode, int64 htsBalance) = abi.decode(result, (int32, int64));
            if (responseCode == HederaResponseCodes.SUCCESS) {
                return htsBalance;
            }
        }
        return balances[token];
    }
    
    function setBalance(address token, int64 amount) external {
        balances[token] = amount;
    }
    
    function withdrawTo(address token, int64 amount, address to) external {
        require(balances[token] >= amount, "Insufficient balance");
        balances[token] -= amount;
        
        // Actually transfer via HTS for testing
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                address(this),
                to,
                amount
            )
        );
        require(success, "HTS transfer failed in withdrawTo");
        int32 responseCode = abi.decode(result, (int32));
        require(responseCode == HederaResponseCodes.SUCCESS, "HTS transfer failed in withdrawTo");
    }
}

/// @title RebalanceExecutorTest
/// @notice Comprehensive tests for RebalanceExecutor contract
contract RebalanceExecutorTest is Test {
    RebalanceExecutor public executor;
    MockVolatilityIndex public volatilityIndex;
    SaucerSwapper public swapper;
    MockSaucerSwapRouter public mockRouter;
    MockSaucerSwapFactory public mockFactory;
    MockUserVault public vault;
    MockHederaTokenService public mockHTS;
    
    address constant HTS_PRECOMPILE = address(0x167);
    
    address public owner = address(0xABCD);
    address public agent = address(0xAAAA);
    address public unauthorized = address(0xBBBB);
    
    address public tokenA = address(0x100);
    address public tokenB = address(0x200);
    address public whbar = address(0x300); // Mock WHBAR address
    
    bytes32 public priceFeedId = keccak256("HBAR_USDC");
    
    uint256 public constant BASIS_POINTS_VALUE = 10000;
    
    event RebalanceExecuted(
        address indexed vault,
        address indexed tokenSold,
        address indexed tokenBought,
        int64 amountSold,
        int64 amountBought,
        uint256 volatility,
        uint256 timestamp
    );
    
    event AgentAuthorized(address indexed agent, uint256 timestamp);
    event AgentRevoked(address indexed agent, uint256 timestamp);
    event MaxDriftUpdated(uint256 oldDrift, uint256 newDrift);
    event RebalanceFailed(address indexed vault, string reason);
    
    function setUp() public {
        // Deploy mock contracts
        volatilityIndex = new MockVolatilityIndex();
        mockHTS = new MockHederaTokenService();
        mockFactory = new MockSaucerSwapFactory();
        mockRouter = new MockSaucerSwapRouter(whbar, address(mockFactory));
        
        // Deploy real SaucerSwapper with mocked router and factory
        vm.startPrank(owner);
        swapper = new SaucerSwapper(address(mockRouter), address(mockFactory));
        vault = new MockUserVault(owner);
        
        // Deploy executor
        executor = new RebalanceExecutor(
            payable(address(volatilityIndex)),
            payable(address(swapper))
        );
        vm.stopPrank();
        
        // Setup HTS precompile mock
        bytes memory code = address(mockHTS).code;
        vm.etch(HTS_PRECOMPILE, code);
        
        // Setup factory to return a pair for tokenA/tokenB
        address mockPair = address(0x400); // Mock pair address
        mockFactory.setMockPair(mockPair);
        mockFactory.setPair(tokenA, tokenB, mockPair);
        
        // Associate tokens for executor, vault, and swapper
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(executor), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(executor), tokenB);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(vault), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(vault), tokenB);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(swapper), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(swapper), tokenB);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(mockRouter), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(mockRouter), tokenB);
        
        // Set initial balances
        vault.setBalance(tokenA, 10000); // 10,000 tokenA
        vault.setBalance(tokenB, 10000); // 10,000 tokenB
        
        // Set HTS balances
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 10000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 10000);
        // Give router some initial tokenB balance for swaps (it will receive tokenA and send tokenB)
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(mockRouter), 1000000);
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor_Success() public {
        // Create new volatility index and swapper for this test
        MockVolatilityIndex newVolatilityIndex = new MockVolatilityIndex();
        MockSaucerSwapFactory newFactory = new MockSaucerSwapFactory();
        MockSaucerSwapRouter newRouter = new MockSaucerSwapRouter(whbar, address(newFactory));
        
        vm.startPrank(owner);
        SaucerSwapper newSwapper = new SaucerSwapper(address(newRouter), address(newFactory));
        RebalanceExecutor newExecutor = new RebalanceExecutor(
            payable(address(newVolatilityIndex)),
            payable(address(newSwapper))
        );
        vm.stopPrank();
        
        assertEq(address(newExecutor.volatilityIndex()), address(newVolatilityIndex));
        assertEq(address(newExecutor.swapper()), address(newSwapper));
        assertTrue(newExecutor.isAuthorizedAgent(owner));
        assertEq(newExecutor.maxDriftBps(), 500); // 5% default
    }
    
    function test_Constructor_RevertsIfVolatilityIndexZero() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        new RebalanceExecutor(payable(address(0)), payable(address(swapper)));
        vm.stopPrank();
    }
    
    function test_Constructor_RevertsIfSwapperZero() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        new RebalanceExecutor(payable(address(volatilityIndex)), payable(address(0)));
        vm.stopPrank();
    }
    
    // ============ Agent Authorization Tests ============
    
    function test_AuthorizeAgent_Success() public {
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit AgentAuthorized(agent, block.timestamp);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        assertTrue(executor.isAuthorizedAgent(agent));
    }
    
    function test_AuthorizeAgent_RevertsIfNotOwner() public {
        vm.startPrank(unauthorized);
        vm.expectRevert();
        executor.authorizeAgent(agent);
        vm.stopPrank();
    }
    
    function test_AuthorizeAgent_RevertsIfZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.authorizeAgent(address(0));
        vm.stopPrank();
    }
    
    function test_RevokeAgent_Success() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        assertTrue(executor.isAuthorizedAgent(agent));
        
        vm.expectEmit(true, false, false, false);
        emit AgentRevoked(agent, block.timestamp);
        executor.revokeAgent(agent);
        vm.stopPrank();
        
        assertFalse(executor.isAuthorizedAgent(agent));
    }
    
    // ============ Max Drift Tests ============
    
    function test_SetMaxDrift_Success() public {
        vm.startPrank(owner);
        uint256 newDrift = 1000; // 10%
        vm.expectEmit(true, false, false, false);
        emit MaxDriftUpdated(500, newDrift);
        executor.setMaxDrift(newDrift);
        vm.stopPrank();
        
        assertEq(executor.maxDriftBps(), newDrift);
    }
    
    function test_SetMaxDrift_RevertsIfTooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidConfiguration.selector);
        executor.setMaxDrift(2001); // > 20%
        vm.stopPrank();
    }
    
    function test_SetMaxDrift_RevertsIfNotOwner() public {
        vm.startPrank(unauthorized);
        vm.expectRevert();
        executor.setMaxDrift(1000);
        vm.stopPrank();
    }
    
    // ============ Execute Rebalance Tests ============
    
    function test_ExecuteRebalance_Success() public {
        // Setup: authorize agent
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Setup: set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000); // 40% volatility
        uint256 volatilityThreshold = 3000; // 30%
        
        // Setup: vault has 60% tokenA, 40% tokenB (target: 50/50)
        // Total value: 20,000
        // Current: tokenA = 12,000 (60%), tokenB = 8,000 (40%)
        // Target: tokenA = 10,000 (50%), tokenB = 10,000 (50%)
        // Need to sell 2,000 tokenA to get back to 50%
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        
        // Setup: set router to return 2x (2000 tokenA -> 4000 tokenB)
        mockRouter.setMockAmountOut(4000);
        mockRouter.setMockAmountReceived(4000);
        
        // Execute rebalance - check event with flexible timestamp
        vm.startPrank(agent);
        vm.expectEmit(true, true, true, false); // Don't check timestamp
        emit RebalanceExecuted(
            address(vault),
            tokenA,
            tokenB,
            2000,
            4000,
            4000,
            0 // timestamp will be checked separately
        );
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000, // target allocation for tokenA (50%)
            5000, // target allocation for tokenB (50%)
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
        
        // Verify rebalance history
        assertEq(executor.getRebalanceCount(), 1);
    }
    
    function test_ExecuteRebalance_RevertsIfUnauthorized() public {
        vm.startPrank(unauthorized);
        vm.expectRevert(RebalanceExecutor.Unauthorized.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_RevertsIfVolatilityTooLow() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Set volatility below threshold
        volatilityIndex.setVolatility(priceFeedId, 2000); // 20% volatility
        uint256 volatilityThreshold = 3000; // 30%
        
        vm.startPrank(agent);
        vm.expectRevert(RebalanceExecutor.RebalanceNotNeeded.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_RevertsIfDriftTooSmall() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000); // 40% volatility
        uint256 volatilityThreshold = 3000; // 30%
        
        // Setup: vault is already balanced (drift < 5%)
        // Current: tokenA = 10,200 (51%), tokenB = 9,800 (49%)
        // Drift: 1% < 5% threshold
        vault.setBalance(tokenA, 10200);
        vault.setBalance(tokenB, 9800);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 10200);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 9800);
        
        vm.startPrank(agent);
        vm.expectRevert(RebalanceExecutor.RebalanceNotNeeded.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000, // target 50%
            5000, // target 50%
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_RevertsIfInsufficientBalance() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000);
        uint256 volatilityThreshold = 3000;
        
        // Setup: vault has very little tokenA
        // Current: tokenA = 100 (0.5%), tokenB = 19900 (99.5%)
        // Target: 50% each
        // Since tokenA is below target, we can't sell it to rebalance
        // We would need to sell tokenB instead, but the test is trying to sell tokenA
        vault.setBalance(tokenA, 100);
        vault.setBalance(tokenB, 19900);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 100);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 19900);
        
        vm.startPrank(agent);
        // Since tokenA is below target, _calculateSellAmount returns 0, triggering InsufficientBalance
        vm.expectRevert(RebalanceExecutor.InsufficientBalance.selector);
        executor.executeRebalance(
            address(vault),
            tokenA, // Trying to sell tokenA, but it's below target
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_HandlesSwapFailure() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000);
        uint256 volatilityThreshold = 3000;
        
        // Setup: vault needs rebalancing
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        
        // Setup: router will revert in swapExactTokensForTokens
        mockRouter.setShouldRevert(true, "Swap failed");
        
        vm.startPrank(agent);
        // The function will revert, and the RebalanceFailed event should be emitted
        // We can't easily test events emitted before revert, so just check the revert
        vm.expectRevert("Swap failed");
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_RevertsIfZeroAddresses() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        volatilityIndex.setVolatility(priceFeedId, 4000);
        
        vm.startPrank(agent);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.executeRebalance(
            address(0),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.executeRebalance(
            address(vault),
            address(0),
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            address(0),
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    // ============ Needs Rebalancing Tests ============
    
    function test_NeedsRebalancing_ReturnsTrue() public {
        // Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000);
        uint256 volatilityThreshold = 3000;
        
        // Setup: vault has significant drift
        vault.setBalance(tokenA, 12000); // 60%
        vault.setBalance(tokenB, 8000);  // 40%
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        
        (bool needed, uint256 currentDrift) = executor.needsRebalancing(
            address(vault),
            tokenA,
            tokenB,
            5000, // target 50%
            5000, // target 50%
            volatilityThreshold,
            priceFeedId
        );
        
        assertTrue(needed);
        assertGt(currentDrift, 500); // Drift > 5% threshold (maxDriftBps = 500)
    }
    
    function test_NeedsRebalancing_ReturnsFalseIfVolatilityLow() public {
        // Set volatility below threshold
        volatilityIndex.setVolatility(priceFeedId, 2000);
        uint256 volatilityThreshold = 3000;
        
        (bool needed, uint256 currentDrift) = executor.needsRebalancing(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        
        assertFalse(needed);
        assertEq(currentDrift, 0);
    }
    
    function test_NeedsRebalancing_ReturnsFalseIfDriftSmall() public {
        // Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 4000);
        uint256 volatilityThreshold = 3000;
        
        // Setup: vault is balanced (drift < 5%)
        vault.setBalance(tokenA, 10200); // 51%
        vault.setBalance(tokenB, 9800);  // 49%
        
        (bool needed, uint256 currentDrift) = executor.needsRebalancing(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        
        assertFalse(needed);
        assertLt(currentDrift, 500); // Drift < 5% threshold
    }
    
    // ============ Rebalance History Tests ============
    
    function test_GetRebalanceHistory_ReturnsEmptyInitially() public {
        RebalanceExecutor.RebalanceRecord[] memory records = executor.getRebalanceHistory(address(vault));
        assertEq(records.length, 0);
    }
    
    function test_GetRebalanceHistory_ReturnsRecordsForVault() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Execute first rebalance
        volatilityIndex.setVolatility(priceFeedId, 4000);
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        mockRouter.setMockAmountOut(4000);
        mockRouter.setMockAmountReceived(4000);
        
        vm.startPrank(agent);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
        
        // Create second vault and execute rebalance
        MockUserVault vault2 = new MockUserVault(owner);
        vault2.setBalance(tokenA, 15000);
        vault2.setBalance(tokenB, 5000);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(vault2), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(vault2), tokenB);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault2), 15000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault2), 5000);
        // Also need to associate executor with tokens for vault2 transfers
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(executor), tokenA);
        MockHederaTokenService(HTS_PRECOMPILE).associateTokenFor(address(executor), tokenB);
        
        vm.startPrank(agent);
        mockRouter.setMockAmountOut(10000);
        mockRouter.setMockAmountReceived(10000);
        executor.executeRebalance(
            address(vault2),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
        
        // Get history for first vault
        RebalanceExecutor.RebalanceRecord[] memory records = executor.getRebalanceHistory(address(vault));
        assertEq(records.length, 1);
        assertEq(records[0].vault, address(vault));
        assertEq(records[0].tokenSold, tokenA);
        assertEq(records[0].tokenBought, tokenB);
        
        // Get history for second vault
        RebalanceExecutor.RebalanceRecord[] memory records2 = executor.getRebalanceHistory(address(vault2));
        assertEq(records2.length, 1);
        assertEq(records2[0].vault, address(vault2));
        
        // Total count should be 2
        assertEq(executor.getRebalanceCount(), 2);
    }
    
    // ============ Contract Update Tests ============
    
    function test_UpdateVolatilityIndex_Success() public {
        MockVolatilityIndex newVolatilityIndex = new MockVolatilityIndex();
        
        vm.startPrank(owner);
        executor.updateVolatilityIndex(payable(address(newVolatilityIndex)));
        vm.stopPrank();
        
        assertEq(address(executor.volatilityIndex()), address(newVolatilityIndex));
    }
    
    function test_UpdateVolatilityIndex_RevertsIfZero() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.updateVolatilityIndex(payable(address(0)));
        vm.stopPrank();
    }
    
    function test_UpdateVolatilityIndex_RevertsIfNotOwner() public {
        MockVolatilityIndex newVolatilityIndex = new MockVolatilityIndex();
        
        vm.startPrank(unauthorized);
        vm.expectRevert();
        executor.updateVolatilityIndex(payable(address(newVolatilityIndex)));
        vm.stopPrank();
    }
    
    function test_UpdateSwapper_Success() public {
        // Create new swapper with new router and factory
        MockSaucerSwapFactory newFactory = new MockSaucerSwapFactory();
        MockSaucerSwapRouter newRouter = new MockSaucerSwapRouter(whbar, address(newFactory));
        
        vm.startPrank(owner);
        SaucerSwapper newSwapper = new SaucerSwapper(address(newRouter), address(newFactory));
        executor.updateSwapper(payable(address(newSwapper)));
        vm.stopPrank();
        
        assertEq(address(executor.swapper()), address(newSwapper));
    }
    
    function test_UpdateSwapper_RevertsIfZero() public {
        vm.startPrank(owner);
        vm.expectRevert(RebalanceExecutor.InvalidAddress.selector);
        executor.updateSwapper(payable(address(0)));
        vm.stopPrank();
    }
    
    function test_UpdateSwapper_RevertsIfNotOwner() public {
        // Create new swapper with new router and factory
        MockSaucerSwapFactory newFactory = new MockSaucerSwapFactory();
        MockSaucerSwapRouter newRouter = new MockSaucerSwapRouter(whbar, address(newFactory));
        
        vm.startPrank(owner);
        SaucerSwapper newSwapper = new SaucerSwapper(address(newRouter), address(newFactory));
        vm.stopPrank();
        
        vm.startPrank(unauthorized);
        vm.expectRevert();
        executor.updateSwapper(payable(address(newSwapper)));
        vm.stopPrank();
    }
    
    // ============ Edge Case Tests ============
    
    function test_ExecuteRebalance_WithZeroTotalValue() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Setup: vault has zero balance
        vault.setBalance(tokenA, 0);
        vault.setBalance(tokenB, 0);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 0);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 0);
        
        volatilityIndex.setVolatility(priceFeedId, 4000);
        
        vm.startPrank(agent);
        // When total value is 0, amountToSell will be 0, which triggers InsufficientBalance
        vm.expectRevert(RebalanceExecutor.InsufficientBalance.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_WithExactTargetAllocation() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Setup: vault is exactly at target (50/50)
        vault.setBalance(tokenA, 10000);
        vault.setBalance(tokenB, 10000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 10000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 10000);
        
        volatilityIndex.setVolatility(priceFeedId, 4000);
        
        vm.startPrank(agent);
        vm.expectRevert(RebalanceExecutor.RebalanceNotNeeded.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_ExecuteRebalance_WithCurrentAllocationBelowTarget() public {
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Setup: vault has less tokenA than target (40% vs 50% target)
        // Should not sell tokenA, but this test verifies the logic
        vault.setBalance(tokenA, 8000);  // 40%
        vault.setBalance(tokenB, 12000);  // 60%
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 12000);
        
        volatilityIndex.setVolatility(priceFeedId, 4000);
        
        vm.startPrank(agent);
        // Should revert because we're trying to sell tokenA but it's below target
        // _calculateSellAmount returns 0 when currentAllocation <= targetAllocation
        vm.expectRevert(RebalanceExecutor.InsufficientBalance.selector);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000, // target 50% for tokenA
            5000, // target 50% for tokenB
            3000,
            priceFeedId
        );
        vm.stopPrank();
    }
    
    function test_GetRebalanceCount_ReturnsCorrectCount() public {
        assertEq(executor.getRebalanceCount(), 0);
        
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // Execute multiple rebalances
        volatilityIndex.setVolatility(priceFeedId, 4000);
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        mockRouter.setMockAmountOut(4000);
        mockRouter.setMockAmountReceived(4000);
        
        vm.startPrank(agent);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        assertEq(executor.getRebalanceCount(), 1);
        
        // Reset balances and execute again
        // Need to reset vault balances and HTS balances
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        // Reset executor balances
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(executor), 0);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(executor), 0);
        // Reset router balances - give it tokenB for the swap
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(mockRouter), 0);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(mockRouter), 1000000);
        
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            3000,
            priceFeedId
        );
        assertEq(executor.getRebalanceCount(), 2);
        vm.stopPrank();
    }
    
    // ============ Integration Tests ============
    
    function test_FullRebalancingFlow() public {
        // 1. Authorize agent
        vm.startPrank(owner);
        executor.authorizeAgent(agent);
        vm.stopPrank();
        
        // 2. Set volatility above threshold
        volatilityIndex.setVolatility(priceFeedId, 3800); // 38% volatility (crisis scenario)
        uint256 volatilityThreshold = 3000; // 30% threshold
        
        // 3. Setup unbalanced portfolio
        // Current: 60% tokenA, 40% tokenB
        // Target: 50% tokenA, 50% tokenB
        vault.setBalance(tokenA, 12000);
        vault.setBalance(tokenB, 8000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenA, address(vault), 12000);
        MockHederaTokenService(HTS_PRECOMPILE).setBalance(tokenB, address(vault), 8000);
        
        // 4. Check if rebalancing is needed
        (bool needed, uint256 drift) = executor.needsRebalancing(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        assertTrue(needed);
        assertGt(drift, 500);
        
        // 5. Execute rebalancing
        mockRouter.setMockAmountOut(4000);
        mockRouter.setMockAmountReceived(4000);
        
        vm.startPrank(agent);
        executor.executeRebalance(
            address(vault),
            tokenA,
            tokenB,
            5000,
            5000,
            volatilityThreshold,
            priceFeedId
        );
        vm.stopPrank();
        
        // 6. Verify rebalance was recorded
        RebalanceExecutor.RebalanceRecord[] memory records = executor.getRebalanceHistory(address(vault));
        assertEq(records.length, 1);
        assertEq(records[0].volatility, 3800);
        assertEq(records[0].amountSold, 2000);
        assertEq(records[0].amountBought, 4000);
    }
}
