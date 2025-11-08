// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IHederaTokenService.sol";
import {ISaucerSwapRouter} from "./interfaces/ISaucerSwapRouter.sol";
import {ISaucerSwapFactory} from "./interfaces/ISaucerSwapRouter.sol";
import {ISaucerSwapPair} from "./interfaces/ISaucerSwapRouter.sol";
import "./libraries/HederaResponseCodes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SaucerSwapper
 * @notice Handles token swaps on SaucerSwap V2 for ReVaultron protocol
 * @dev Fully compatible with Hedera Token Service (HTS)
 * @custom:security-contact security@revaultron.io
 */
contract SaucerSwapper is Ownable, ReentrancyGuard {
    
    // Hedera Token Service precompiled contract
    address constant HTS_PRECOMPILE = address(0x167);
    
    // SaucerSwap V2 Router interface
    ISaucerSwapRouter public saucerSwapRouter;
    
    // SaucerSwap V2 Factory interface
    ISaucerSwapFactory public saucerSwapFactory;
    
    // WHBAR address on Hedera
    address public WHBAR;
    
    // Default slippage tolerance (1% = 100 basis points)
    uint256 public slippageTolerance = 100;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% max
    
    // Minimum deadline extension (5 minutes)
    uint256 public constant MIN_DEADLINE = 300;
    
    // Events
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        int64 amountIn,
        int64 amountOut,
        address indexed recipient,
        uint256 timestamp
    );
    
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event RouterUpdated(address oldRouter, address newRouter);
    event FactoryUpdated(address oldFactory, address newFactory);
    
    // Custom errors
    error InvalidAddress();
    error InvalidAmount();
    error SlippageTooHigh();
    error SwapFailed(string reason);
    error InsufficientOutput();
    error DeadlineExpired();
    error PairDoesNotExist();
    
    /**
     * @dev Constructor
     * @param _router SaucerSwap V2 Router address on Hedera
     * @param _factory SaucerSwap V2 Factory address on Hedera
     */
    constructor(address _router, address _factory) Ownable(msg.sender) {
        if (_router == address(0)) revert InvalidAddress();
        if (_factory == address(0)) revert InvalidAddress();
        
        saucerSwapRouter = ISaucerSwapRouter(_router);
        saucerSwapFactory = ISaucerSwapFactory(_factory);
        
        // Get WHBAR address from router
        WHBAR = saucerSwapRouter.WHBAR();
        if (WHBAR == address(0)) revert InvalidAddress();
    }
    
    /**
     * @notice Swap exact input amount for output
     * @param tokenIn Input HTS token address
     * @param tokenOut Output HTS token address
     * @param amountIn Input amount (int64 for HTS)
     * @param amountOutMinimum Minimum acceptable output
     * @param recipient Address to receive output tokens
     * @return amountOut Actual output amount received
     */
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        int64 amountIn,
        int64 amountOutMinimum,
        address recipient
    ) external nonReentrant returns (int64 amountOut) {
        if (tokenIn == address(0)) revert InvalidAddress();
        if (tokenOut == address(0)) revert InvalidAddress();
        if (recipient == address(0)) revert InvalidAddress();
        if (amountIn <= 0) revert InvalidAmount();
        
        // Check if pair exists
        if (!pairExists(tokenIn, tokenOut)) revert PairDoesNotExist();
        
        // Transfer tokens from sender to this contract via HTS
        _transferTokenFrom(tokenIn, msg.sender, address(this), amountIn);
        
        // Approve SaucerSwap router to spend tokens
        _approveRouter(tokenIn, amountIn);
        
        // Calculate deadline
        uint256 deadline = block.timestamp + MIN_DEADLINE;
        
        // Build swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Execute swap via SaucerSwap router
        uint256[] memory amounts = saucerSwapRouter.swapExactTokensForTokens(
            uint256(uint64(amountIn)),
            uint256(uint64(amountOutMinimum)),
            path,
            recipient,
            deadline
        );
        
        amountOut = int64(uint64(amounts[amounts.length - 1]));
        
        emit SwapExecuted(
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            recipient,
            block.timestamp
        );
        
        return amountOut;
    }
    
    /**
     * @notice Swap tokens for exact output amount
     * @param tokenIn Input HTS token address
     * @param tokenOut Output HTS token address
     * @param amountOut Desired output amount
     * @param amountInMaximum Maximum input amount willing to spend
     * @param recipient Address to receive output tokens
     * @return amountIn Actual input amount used
     */
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        int64 amountOut,
        int64 amountInMaximum,
        address recipient
    ) external nonReentrant returns (int64 amountIn) {
        if (tokenIn == address(0)) revert InvalidAddress();
        if (tokenOut == address(0)) revert InvalidAddress();
        if (recipient == address(0)) revert InvalidAddress();
        if (amountOut <= 0) revert InvalidAmount();
        
        // Check if pair exists
        if (!pairExists(tokenIn, tokenOut)) revert PairDoesNotExist();
        
        // Transfer max tokens from sender to this contract
        _transferTokenFrom(tokenIn, msg.sender, address(this), amountInMaximum);
        
        // Approve router
        _approveRouter(tokenIn, amountInMaximum);
        
        // Calculate deadline
        uint256 deadline = block.timestamp + MIN_DEADLINE;
        
        // Build swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Execute swap
        uint256[] memory amounts = saucerSwapRouter.swapTokensForExactTokens(
            uint256(uint64(amountOut)),
            uint256(uint64(amountInMaximum)),
            path,
            recipient,
            deadline
        );
        
        amountIn = int64(uint64(amounts[0]));
        
        // Refund unused tokens to sender
        int64 refund = amountInMaximum - amountIn;
        if (refund > 0) {
            _transferTokenFrom(tokenIn, address(this), msg.sender, refund);
        }
        
        emit SwapExecuted(
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            recipient,
            block.timestamp
        );
        
        return amountIn;
    }
    
    /**
     * @notice Get estimated output amount for input
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Estimated output amount
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        int64 amountIn
    ) external view returns (int64 amountOut) {
        if (tokenIn == address(0)) revert InvalidAddress();
        if (tokenOut == address(0)) revert InvalidAddress();
        if (amountIn <= 0) revert InvalidAmount();
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        try saucerSwapRouter.getAmountsOut(uint256(uint64(amountIn)), path) 
            returns (uint256[] memory amounts) {
            amountOut = int64(uint64(amounts[amounts.length - 1]));
        } catch {
            amountOut = 0;
        }
        
        return amountOut;
    }
    
    /**
     * @notice Get estimated input amount for desired output
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountOut Desired output amount
     * @return amountIn Estimated input amount needed
     */
    function getAmountIn(
        address tokenIn,
        address tokenOut,
        int64 amountOut
    ) external view returns (int64 amountIn) {
        if (tokenIn == address(0)) revert InvalidAddress();
        if (tokenOut == address(0)) revert InvalidAddress();
        if (amountOut <= 0) revert InvalidAmount();
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        try saucerSwapRouter.getAmountsIn(uint256(uint64(amountOut)), path) 
            returns (uint256[] memory amounts) {
            amountIn = int64(uint64(amounts[0]));
        } catch {
            amountIn = 0;
        }
        
        return amountIn;
    }
    
    /**
     * @notice Check if a trading pair exists
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return exists True if pair exists
     */
    function pairExists(
        address tokenA,
        address tokenB
    ) public view returns (bool exists) {
        address pair = saucerSwapFactory.getPair(tokenA, tokenB);
        return pair != address(0);
    }
    
    /**
     * @notice Get the pair address for two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Pair contract address
     */
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair) {
        return saucerSwapFactory.getPair(tokenA, tokenB);
    }
    
    /**
     * @notice Get reserves for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return reserveA Reserve of tokenA
     * @return reserveB Reserve of tokenB
     */
    function getReserves(
        address tokenA,
        address tokenB
    ) external view returns (uint256 reserveA, uint256 reserveB) {
        address pairAddress = saucerSwapFactory.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) {
            return (0, 0);
        }
        
        ISaucerSwapPair pair = ISaucerSwapPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        
        address token0 = pair.token0();
        
        // Ensure reserves are returned in the correct order
        if (tokenA == token0) {
            reserveA = uint256(reserve0);
            reserveB = uint256(reserve1);
        } else {
            reserveA = uint256(reserve1);
            reserveB = uint256(reserve0);
        }
        
        return (reserveA, reserveB);
    }
    
    /**
     * @notice Calculate minimum output with slippage tolerance
     * @param amountOut Expected output amount
     * @return minAmount Minimum acceptable amount
     */
    function calculateMinOutput(int64 amountOut) public view returns (int64 minAmount) {
        uint256 amount = uint256(uint64(amountOut));
        uint256 minAmountUint = (amount * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;
        minAmount = int64(uint64(minAmountUint));
        return minAmount;
    }
    
    /**
     * @notice Calculate maximum input with slippage tolerance
     * @param amountIn Expected input amount
     * @return maxAmount Maximum acceptable amount
     */
    function calculateMaxInput(int64 amountIn) public view returns (int64 maxAmount) {
        uint256 amount = uint256(uint64(amountIn));
        uint256 maxAmountUint = (amount * (BASIS_POINTS + slippageTolerance)) / BASIS_POINTS;
        maxAmount = int64(uint64(maxAmountUint));
        return maxAmount;
    }
    
    /**
     * @notice Transfer HTS tokens using precompile
     * @param token HTS token address
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function _transferTokenFrom(
        address token,
        address from,
        address to,
        int64 amount
    ) internal {
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                from,
                to,
                amount
            )
        );
        
        if (!success) revert SwapFailed("HTS transfer failed");
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert SwapFailed(
                string(abi.encodePacked(
                    "HTS transfer failed: ",
                    HederaResponseCodes.getResponseMessage(responseCode)
                ))
            );
        }
    }
    
    /**
     * @notice Approve router to spend HTS tokens
     * @param token HTS token address
     * @param amount Amount to approve
     */
    function _approveRouter(address token, int64 amount) internal {
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.approve.selector,
                token,
                address(saucerSwapRouter),
                uint256(uint64(amount))
            )
        );
        
        if (!success) revert SwapFailed("HTS approval failed");
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert SwapFailed("HTS approval failed");
        }
    }
    
    /**
     * @notice Set slippage tolerance
     * @param newSlippage New slippage in basis points
     */
    function setSlippageTolerance(uint256 newSlippage) external onlyOwner {
        if (newSlippage > MAX_SLIPPAGE) revert SlippageTooHigh();
        
        uint256 oldSlippage = slippageTolerance;
        slippageTolerance = newSlippage;
        
        emit SlippageUpdated(oldSlippage, newSlippage);
    }
    
    /**
     * @notice Update SaucerSwap router address
     * @param newRouter New router address
     */
    function updateRouter(address newRouter) external onlyOwner {
        if (newRouter == address(0)) revert InvalidAddress();
        
        address oldRouter = address(saucerSwapRouter);
        saucerSwapRouter = ISaucerSwapRouter(newRouter);
        WHBAR = saucerSwapRouter.WHBAR();
        
        emit RouterUpdated(oldRouter, newRouter);
    }
    
    /**
     * @notice Update SaucerSwap factory address
     * @param newFactory New factory address
     */
    function updateFactory(address newFactory) external onlyOwner {
        if (newFactory == address(0)) revert InvalidAddress();
        
        address oldFactory = address(saucerSwapFactory);
        saucerSwapFactory = ISaucerSwapFactory(newFactory);
        
        emit FactoryUpdated(oldFactory, newFactory);
    }
    
    /**
     * @notice Emergency token recovery
     * @param token Token address
     * @param amount Amount to recover
     * @param to Recipient address
     */
    function emergencyRecoverToken(
        address token,
        int64 amount,
        address to
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        
        _transferTokenFrom(token, address(this), to, amount);
    }
    
    /**
     * @notice Get swap router address
     */
    function getRouter() external view returns (address) {
        return address(saucerSwapRouter);
    }
    
    /**
     * @notice Get factory address
     */
    function getFactory() external view returns (address) {
        return address(saucerSwapFactory);
    }
    
    /**
     * @notice Get current slippage tolerance
     */
    function getSlippageTolerance() external view returns (uint256) {
        return slippageTolerance;
    }
    
    /**
     * @notice Receive HBAR
     */
    receive() external payable {}
}