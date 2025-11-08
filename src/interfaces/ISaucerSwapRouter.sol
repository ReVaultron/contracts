// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ISaucerSwapRouter
 * @notice Interface for SaucerSwap V2 Router on Hedera
 * @dev Based on Uniswap V2 Router interface
 */
interface ISaucerSwapRouter {
    
    /**
     * @notice Swap exact tokens for tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses representing the swap path
     * @param to Recipient address
     * @param deadline Unix timestamp deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    /**
     * @notice Swap tokens for exact tokens
     * @param amountOut Desired amount of output tokens
     * @param amountInMax Maximum amount of input tokens
     * @param path Array of token addresses
     * @param to Recipient address
     * @param deadline Unix timestamp deadline
     * @return amounts Array of amounts for each step
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    /**
     * @notice Swap exact HBAR for tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses (first must be WHBAR)
     * @param to Recipient address
     * @param deadline Unix timestamp deadline
     * @return amounts Array of amounts for each step
     */
    function swapExactHBARForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    
    /**
     * @notice Swap tokens for exact HBAR
     * @param amountOut Desired amount of HBAR
     * @param amountInMax Maximum amount of input tokens
     * @param path Array of token addresses (last must be WHBAR)
     * @param to Recipient address
     * @param deadline Unix timestamp deadline
     * @return amounts Array of amounts for each step
     */
    function swapTokensForExactHBAR(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    /**
     * @notice Swap exact tokens for HBAR
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of HBAR
     * @param path Array of token addresses (last must be WHBAR)
     * @param to Recipient address
     * @param deadline Unix timestamp deadline
     * @return amounts Array of amounts for each step
     */
    function swapExactTokensForHBAR(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    /**
     * @notice Get amounts out for a given input and path
     * @param amountIn Input amount
     * @param path Array of token addresses
     * @return amounts Array of output amounts for each step
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
    
    /**
     * @notice Get amounts in for a given output and path
     * @param amountOut Output amount
     * @param path Array of token addresses
     * @return amounts Array of input amounts for each step
     */
    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
    
    /**
     * @notice Get WHBAR address
     * @return WHBAR token address
     */
    function WHBAR() external view returns (address);
    
    /**
     * @notice Get factory address
     * @return Factory contract address
     */
    function factory() external view returns (address);
}

/**
 * @title ISaucerSwapFactory
 * @notice Interface for SaucerSwap V2 Factory
 */
interface ISaucerSwapFactory {
    
    /**
     * @notice Get pair address for two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Pair address
     */
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    
    /**
     * @notice Get all pairs count
     * @return count Number of pairs
     */
    function allPairsLength() external view returns (uint256 count);
    
    /**
     * @notice Get pair at index
     * @param index Index
     * @return pair Pair address
     */
    function allPairs(uint256 index) external view returns (address pair);
    
    /**
     * @notice Create pair for two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Created pair address
     */
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

/**
 * @title ISaucerSwapPair
 * @notice Interface for SaucerSwap V2 Pair
 */
interface ISaucerSwapPair {
    
    /**
     * @notice Get reserves
     * @return reserve0 Reserve of token0
     * @return reserve1 Reserve of token1
     * @return blockTimestampLast Last block timestamp
     */
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );
    
    /**
     * @notice Get token0 address
     * @return token0 Token0 address
     */
    function token0() external view returns (address);
    
    /**
     * @notice Get token1 address
     * @return token1 Token1 address
     */
    function token1() external view returns (address);
    
    /**
     * @notice Get cumulative price of token0
     * @return price0CumulativeLast Cumulative price of token0
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @notice Get cumulative price of token1
     * @return price1CumulativeLast Cumulative price of token1
     */
    function price1CumulativeLast() external view returns (uint256);
}
