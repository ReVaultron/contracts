// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./UserVault.sol";
import "./VolatilityIndex.sol";
import "./swap.sol";
import "./interfaces/IHederaTokenService.sol";
import "./libraries/HederaResponseCodes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RebalanceExecutor
 * @notice Executes portfolio rebalancing for ReVaultron vaults
 * @dev Integrates with VolatilityIndex, UserVault, and ManualSwapper
 * @custom:security-contact security@revaultron.io
 */
contract RebalanceExecutor is Ownable, ReentrancyGuard {
    
    // Core contracts
    VolatilityIndex public volatilityIndex;
    ManualSwapper public swapper;
    
    // HTS precompile
    address constant HTS_PRECOMPILE = address(0x167);
    
    // Rebalancing configuration
    uint256 public maxDriftBps = 1; // 5% max drift before rebalancing
    uint256 public constant BASIS_POINTS = 10000;
    
    // Authorized agents (can trigger rebalancing)
    mapping(address => bool) public isAuthorizedAgent;
    
    // Rebalancing history
    struct RebalanceRecord {
        address vault;
        address tokenSold;
        address tokenBought;
        int64 amountSold;
        int64 amountBought;
        uint256 volatility;
        uint256 timestamp;
    }
    
    RebalanceRecord[] public rebalanceHistory;
    
    // Events
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
    
    // Custom errors
    error Unauthorized();
    error InvalidAddress();
    error InvalidConfiguration();
    error RebalanceNotNeeded();
    error InsufficientBalance();
    
    /**
     * @dev Constructor
     * @param _volatilityIndex VolatilityIndex contract address
     * @param _swapper ManualSwapper contract address
     */
    constructor(
        address payable _volatilityIndex,
        address payable _swapper
    ) Ownable(msg.sender) {
        if (_volatilityIndex == address(0)) revert InvalidAddress();
        if (_swapper == address(0)) revert InvalidAddress();

        volatilityIndex = VolatilityIndex(_volatilityIndex);
        swapper = ManualSwapper(_swapper);

        // Owner is automatically authorized
        isAuthorizedAgent[msg.sender] = true;
    }
    
    /**
     * @notice Execute rebalancing for a vault
     * @param vault UserVault address
     * @param tokenToSell Token to sell
     * @param tokenToBuy Token to buy
     * @param targetAllocationSell Target allocation for tokenToSell (in basis points)
     * @param targetAllocationBuy Target allocation for tokenToBuy (in basis points)
     * @param volatilityThreshold Minimum volatility to trigger rebalance (in bps)
     * @param priceFeedId Pyth price feed ID for volatility check
     */
    function executeRebalance(
        address vault,
        address tokenToSell,
        address tokenToBuy,
        uint256 targetAllocationSell,
        uint256 targetAllocationBuy,
        uint256 volatilityThreshold,
        bytes32 priceFeedId
    ) external nonReentrant {
        if (!isAuthorizedAgent[msg.sender]) revert Unauthorized();
        if (vault == address(0)) revert InvalidAddress();
        // Note: address(0) is valid for HBAR, so only check if BOTH are address(0)
        if (tokenToSell == address(0) && tokenToBuy == address(0)) revert InvalidAddress();
        
        UserVault userVault = UserVault(payable(vault));
        
        // 1. Check volatility
        uint256 currentVolatility = volatilityIndex.getVolatility(priceFeedId);
        
        if (currentVolatility < volatilityThreshold) {
            revert RebalanceNotNeeded();
        }
        
        // 2. Calculate current allocations using USD values
        (
            uint256 currentAllocationSell,
            uint256 currentAllocationBuy,
            int64 totalValue
        ) = _calculateCurrentAllocations(
            userVault,
            tokenToSell,
            tokenToBuy,
            priceFeedId
        );
        
        // 3. Check if rebalancing is needed (drift > threshold)
        uint256 driftSell = _calculateDrift(currentAllocationSell, targetAllocationSell);
        uint256 driftBuy = _calculateDrift(currentAllocationBuy, targetAllocationBuy);
        
        if (driftSell < maxDriftBps && driftBuy < maxDriftBps) {
            revert RebalanceNotNeeded();
        }
        
        // Get HBAR price for amount calculation
        VolatilityIndex.VolatilityData memory volData = volatilityIndex.getVolatilityData(priceFeedId);
        int64 hbarPriceUSD = volData.price;
        
        // 4. Calculate rebalancing amounts
        int64 amountToSell = _calculateSellAmount(
            userVault,
            tokenToSell,
            currentAllocationSell,
            targetAllocationSell,
            totalValue,
            hbarPriceUSD
        );
        
        if (amountToSell <= 0) revert InsufficientBalance();
        
        // 5. Withdraw HBAR from vault to this executor
        // amountToSell is in tinybars, convert to wei-bar for withdrawal
        // tinybars × 10^10 = wei-bar
        uint256 hbarAmountWeiBar = uint256(uint64(amountToSell)) * (10 ** 10);
        userVault.withdrawHBAR(hbarAmountWeiBar, payable(address(this)));
        
        // 6. Get expected USDC amount from swapper (using wei-bar)
        uint256 expectedUSDC = swapper.getAmountOut(hbarAmountWeiBar);
        int64 amountReceived = int64(uint64(expectedUSDC));
        
        // 7. Execute swap: send HBAR to ManualSwapper and receive USDC
        // Note: On Hedera, msg.value is in tinybars
        uint256 hbarAmountTinybars = uint256(uint64(amountToSell));
        uint256 actualUSDC;
        try swapper.swap{value: hbarAmountTinybars}(address(this)) returns (uint256 amount) {
            actualUSDC = amount;
            // Verify we got the expected amount
            require(actualUSDC == expectedUSDC, "Unexpected USDC amount");
        } catch Error(string memory reason) {
            // Return HBAR to vault on failure (in tinybars)
            (bool success, ) = payable(address(userVault)).call{value: hbarAmountTinybars}("");
            require(success, "Failed to return HBAR to vault");
            emit RebalanceFailed(vault, reason);
            revert(reason);
        }
        
        // 8. Deposit USDC to vault using depositToken function
        // First approve vault to spend USDC, then call depositToken
        IERC20(tokenToBuy).approve(vault, actualUSDC);
        UserVault(payable(vault)).depositToken(tokenToBuy, actualUSDC);
        
        // 9. Record rebalancing
        rebalanceHistory.push(RebalanceRecord({
            vault: vault,
            tokenSold: tokenToSell,
            tokenBought: tokenToBuy,
            amountSold: amountToSell,
            amountBought: amountReceived,
            volatility: currentVolatility,
            timestamp: block.timestamp
        }));
        
        emit RebalanceExecuted(
            vault,
            tokenToSell,
            tokenToBuy,
            amountToSell,
            amountReceived,
            currentVolatility,
            block.timestamp
        );
    }
    
    /**
     * @notice Calculate current allocations for two tokens using USD values
     * @dev Converts HBAR to USD using Pyth price feed, USDC is already in USD
     * @param vault UserVault instance
     * @param token0 First token address (HBAR if address(0))
     * @param token1 Second token address (USDC)
     * @param priceFeedId Pyth price feed ID for HBAR/USD
     * @return allocation0 Allocation of token0 in basis points
     * @return allocation1 Allocation of token1 in basis points
     * @return totalValueUSD Total portfolio value in USD (8 decimals)
     */
    function _calculateCurrentAllocations(
        UserVault vault,
        address token0,
        address token1,
        bytes32 priceFeedId
    ) internal view returns (
        uint256 allocation0,
        uint256 allocation1,
        int64 totalValueUSD
    ) {
        // Get HBAR price from Pyth (price has 8 decimals, e.g., 0.15 USD = 15000000)
        VolatilityIndex.VolatilityData memory volData = volatilityIndex.getVolatilityData(priceFeedId);
        int64 hbarPriceUSD = volData.price; // Price in USD with 8 decimals
        
        int64 value0USD;
        int64 value1USD;
        
        if (token0 == address(0)) {
            // HBAR: convert tinybars to USD value
            // Formula: (tinybars × priceUSD) / 10^8
            uint256 hbarWeiBar = vault.getHBARBalance();
            uint256 hbarTinybars = hbarWeiBar / (10 ** 10);
            // value = (tinybars × price) / 10^8 (price has 8 decimals)
            value0USD = int64(uint64((hbarTinybars * uint256(uint64(hbarPriceUSD))) / (10 ** 8)));
        } else {
            // Token0 is USDC - convert to 8 decimals
            // USDC has 6 decimals, multiply by 100 to get 8 decimals
            uint256 usdcBalance = IERC20(token0).balanceOf(address(vault));
            value0USD = int64(uint64(usdcBalance * 100));
        }
        
        if (token1 == address(0)) {
            // HBAR: convert tinybars to USD value
            uint256 hbarWeiBar = vault.getHBARBalance();
            uint256 hbarTinybars = hbarWeiBar / (10 ** 10);
            value1USD = int64(uint64((hbarTinybars * uint256(uint64(hbarPriceUSD))) / (10 ** 8)));
        } else {
            // Token1 is USDC - convert to 8 decimals
            uint256 usdcBalance = IERC20(token1).balanceOf(address(vault));
            value1USD = int64(uint64(usdcBalance * 100));
        }
        
        totalValueUSD = value0USD + value1USD;
        
        if (totalValueUSD == 0) {
            return (0, 0, 0);
        }
        
        // Calculate allocations in basis points
        allocation0 = (uint256(uint64(value0USD)) * BASIS_POINTS) / uint256(uint64(totalValueUSD));
        allocation1 = (uint256(uint64(value1USD)) * BASIS_POINTS) / uint256(uint64(totalValueUSD));
        
        return (allocation0, allocation1, totalValueUSD);
    }
    
    /**
     * @notice Calculate drift between current and target allocation
     * @param current Current allocation (bps)
     * @param target Target allocation (bps)
     * @return drift Absolute drift in basis points
     */
    function _calculateDrift(
        uint256 current,
        uint256 target
    ) internal pure returns (uint256 drift) {
        if (current > target) {
            drift = current - target;
        } else {
            drift = target - current;
        }
        return drift;
    }
    
    /**
     * @notice Calculate amount to sell for rebalancing (converts USD value to token amount)
     * @param vault UserVault instance
     * @param token Token to sell
     * @param currentAllocation Current allocation (bps)
     * @param targetAllocation Target allocation (bps)
     * @param totalValueUSD Total portfolio value in USD (8 decimals)
     * @param hbarPriceUSD HBAR price in USD (8 decimals)
     * @return amountToSell Amount to sell in native token decimals
     */
    function _calculateSellAmount(
        UserVault vault,
        address token,
        uint256 currentAllocation,
        uint256 targetAllocation,
        int64 totalValueUSD,
        int64 hbarPriceUSD
    ) internal view returns (int64 amountToSell) {
        if (currentAllocation <= targetAllocation) {
            return 0; // No need to sell
        }
        
        // Calculate excess allocation in USD (8 decimals)
        uint256 excessAllocation = currentAllocation - targetAllocation;
        uint256 valueToSellUSD = (uint256(uint64(totalValueUSD)) * excessAllocation) / BASIS_POINTS;
        
        // Convert USD value to token amount
        if (token == address(0)) {
            // HBAR: convert USD to tinybars
            // tinybars = (valueUSD × 10^8) / priceUSD
            uint256 tinybarsToSell = (valueToSellUSD * (10 ** 8)) / uint256(uint64(hbarPriceUSD));
            amountToSell = int64(uint64(tinybarsToSell));
            
            // Check available balance
            uint256 hbarWeiBar = vault.getHBARBalance();
            uint256 hbarTinybars = hbarWeiBar / (10 ** 10);
            int64 availableBalance = int64(uint64(hbarTinybars));
            
            if (amountToSell > availableBalance) {
                amountToSell = availableBalance;
            }
        } else {
            // USDC: valueUSD is already in 8 decimals, convert to 6 decimals
            // USDC units = valueUSD / 100
            amountToSell = int64(uint64(valueToSellUSD / 100));
            
            // Check available balance
            uint256 usdcBalance = IERC20(token).balanceOf(address(vault));
            int64 availableBalance = int64(uint64(usdcBalance));
            
            if (amountToSell > availableBalance) {
                amountToSell = availableBalance;
            }
        }
        
        return amountToSell;
    }
    
    /**
     * @notice Transfer HTS token using precompile
     * @param token Token address
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function _transferToken(
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
        
        require(success, "HTS transfer failed");
        
        int32 responseCode = abi.decode(result, (int32));
        
        require(
            responseCode == HederaResponseCodes.SUCCESS,
            "HTS transfer failed"
        );
    }
    
    /**
     * @notice Check if vault needs rebalancing
     * @param vault Vault address
     * @param token0 First token
     * @param token1 Second token
     * @param targetAllocation0 Target allocation for token0 (bps)
     * @param targetAllocation1 Target allocation for token1 (bps)
     * @param volatilityThreshold Min volatility for rebalancing
     * @param priceFeedId Pyth price feed ID
     * @return needed True if rebalancing is needed
     * @return currentDrift Current drift in basis points
     */
    function needsRebalancing(
        address vault,
        address token0,
        address token1,
        uint256 targetAllocation0,
        uint256 targetAllocation1,
        uint256 volatilityThreshold,
        bytes32 priceFeedId
    ) external view returns (bool needed, uint256 currentDrift) {
        // Check volatility
        uint256 volatility = volatilityIndex.getVolatility(priceFeedId);
        if (volatility < volatilityThreshold) {
            return (false, 0);
        }
        
        // Check drift
        UserVault userVault = UserVault(payable(vault));
        (
            uint256 currentAllocation0,
            uint256 currentAllocation1,
        ) = _calculateCurrentAllocations(userVault, token0, token1, priceFeedId);
        
        uint256 drift0 = _calculateDrift(currentAllocation0, targetAllocation0);
        uint256 drift1 = _calculateDrift(currentAllocation1, targetAllocation1);
        
        currentDrift = drift0 > drift1 ? drift0 : drift1;
        needed = currentDrift >= maxDriftBps;
        
        return (needed, currentDrift);
    }
    
    /**
     * @notice Get rebalancing history for a vault
     * @param vault Vault address
     * @return records Array of rebalance records
     */
    function getRebalanceHistory(
        address vault
    ) external view returns (RebalanceRecord[] memory records) {
        uint256 count = 0;
        
        // Count records for this vault
        for (uint256 i = 0; i < rebalanceHistory.length; i++) {
            if (rebalanceHistory[i].vault == vault) {
                count++;
            }
        }
        
        // Create result array
        records = new RebalanceRecord[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < rebalanceHistory.length; i++) {
            if (rebalanceHistory[i].vault == vault) {
                records[index] = rebalanceHistory[i];
                index++;
            }
        }
        
        return records;
    }
    
    /**
     * @notice Authorize an agent to trigger rebalancing
     * @param agent Agent address
     */
    function authorizeAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert InvalidAddress();
        
        isAuthorizedAgent[agent] = true;
        emit AgentAuthorized(agent, block.timestamp);
    }
    
    /**
     * @notice Revoke agent authorization
     * @param agent Agent address
     */
    function revokeAgent(address agent) external onlyOwner {
        isAuthorizedAgent[agent] = false;
        emit AgentRevoked(agent, block.timestamp);
    }
    
    /**
     * @notice Update max drift threshold
     * @param newMaxDrift New max drift in basis points
     */
    function setMaxDrift(uint256 newMaxDrift) external onlyOwner {
        if (newMaxDrift > 2000) revert InvalidConfiguration(); // Max 20%
        
        uint256 oldDrift = maxDriftBps;
        maxDriftBps = newMaxDrift;
        
        emit MaxDriftUpdated(oldDrift, newMaxDrift);
    }
    
    /**
     * @notice Update volatility index contract
     * @param newVolatilityIndex New contract address
     */
    function updateVolatilityIndex(address payable newVolatilityIndex) external onlyOwner {
        if (newVolatilityIndex == address(0)) revert InvalidAddress();
        volatilityIndex = VolatilityIndex(newVolatilityIndex);
    }
    
    /**
     * @notice Update swapper contract
     * @param newSwapper New swapper address
     */
    function updateSwapper(address payable newSwapper) external onlyOwner {
        if (newSwapper == address(0)) revert InvalidAddress();
        swapper = ManualSwapper(newSwapper);
    }
    
    /**
     * @notice Get total rebalance count
     */
    function getRebalanceCount() external view returns (uint256) {
        return rebalanceHistory.length;
    }
    
    /**
     * @notice Receive HBAR
     */
    receive() external payable {}
}
