// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./UserVault.sol";
import "./VolatilityIndex.sol";
import "./SaucerSwapper.sol";
import "./interfaces/IHederaTokenService.sol";
import "./libraries/HederaResponseCodes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RebalanceExecutor
 * @notice Executes portfolio rebalancing for ReVaultron vaults
 * @dev Integrates with VolatilityIndex, UserVault, and SaucerSwapper
 * @custom:security-contact security@revaultron.io
 */
contract RebalanceExecutor is Ownable, ReentrancyGuard {
    
    // Core contracts
    VolatilityIndex public volatilityIndex;
    SaucerSwapper public swapper;
    
    // HTS precompile
    address constant HTS_PRECOMPILE = address(0x167);
    
    // Rebalancing configuration
    uint256 public maxDriftBps = 500; // 5% max drift before rebalancing
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
     * @param _swapper SaucerSwapper contract address
     */
    constructor(
        address payable _volatilityIndex,
        address payable _swapper
    ) Ownable(msg.sender) {
        if (_volatilityIndex == address(0)) revert InvalidAddress();
        if (_swapper == address(0)) revert InvalidAddress();

        volatilityIndex = VolatilityIndex(_volatilityIndex);
        swapper = SaucerSwapper(_swapper);

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
        if (tokenToSell == address(0)) revert InvalidAddress();
        if (tokenToBuy == address(0)) revert InvalidAddress();
        
        UserVault userVault = UserVault(payable(vault));
        
        // 1. Check volatility
        uint256 currentVolatility = volatilityIndex.getVolatility(priceFeedId);
        
        if (currentVolatility < volatilityThreshold) {
            revert RebalanceNotNeeded();
        }
        
        // 2. Calculate current allocations
        (
            uint256 currentAllocationSell,
            uint256 currentAllocationBuy,
            int64 totalValue
        ) = _calculateCurrentAllocations(
            userVault,
            tokenToSell,
            tokenToBuy
        );
        
        // 3. Check if rebalancing is needed (drift > threshold)
        uint256 driftSell = _calculateDrift(currentAllocationSell, targetAllocationSell);
        uint256 driftBuy = _calculateDrift(currentAllocationBuy, targetAllocationBuy);
        
        if (driftSell < maxDriftBps && driftBuy < maxDriftBps) {
            revert RebalanceNotNeeded();
        }
        
        // 4. Calculate rebalancing amounts
        int64 amountToSell = _calculateSellAmount(
            userVault,
            tokenToSell,
            currentAllocationSell,
            targetAllocationSell,
            totalValue
        );
        
        if (amountToSell <= 0) revert InsufficientBalance();
        
        // 5. Withdraw tokens from vault to this executor
        userVault.withdrawTo(tokenToSell, amountToSell, address(this));
        
        // 6. Get estimated output
        int64 estimatedOut = swapper.getAmountOut(
            tokenToSell,
            tokenToBuy,
            amountToSell
        );
        
        int64 minAmountOut = swapper.calculateMinOutput(estimatedOut);
        
        // 7. Execute swap
        int64 amountReceived;
        try swapper.swapExactInput(
            tokenToSell,
            tokenToBuy,
            amountToSell,
            minAmountOut,
            address(this)
        ) returns (int64 amount) {
            amountReceived = amount;
        } catch Error(string memory reason) {
            // Return tokens to vault on failure
            _transferToken(tokenToSell, address(this), vault, amountToSell);
            emit RebalanceFailed(vault, reason);
            revert(reason);
        }
        
        // 8. Deposit swapped tokens back to vault
        // First, transfer tokens to vault
        _transferToken(tokenToBuy, address(this), vault, amountReceived);
        
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
     * @notice Calculate current allocations for two tokens
     * @param vault UserVault instance
     * @param token0 First token address
     * @param token1 Second token address
     * @return allocation0 Allocation of token0 in basis points
     * @return allocation1 Allocation of token1 in basis points
     * @return totalValue Total portfolio value
     */
    function _calculateCurrentAllocations(
        UserVault vault,
        address token0,
        address token1
    ) internal view returns (
        uint256 allocation0,
        uint256 allocation1,
        int64 totalValue
    ) {
        int64 balance0 = vault.getBalance(token0);
        int64 balance1 = vault.getBalance(token1);
        
        totalValue = balance0 + balance1;
        
        if (totalValue == 0) {
            return (0, 0, 0);
        }
        
        // Calculate allocations in basis points
        allocation0 = (uint256(uint64(balance0)) * BASIS_POINTS) / uint256(uint64(totalValue));
        allocation1 = (uint256(uint64(balance1)) * BASIS_POINTS) / uint256(uint64(totalValue));
        
        return (allocation0, allocation1, totalValue);
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
     * @notice Calculate amount to sell for rebalancing
     * @param vault UserVault instance
     * @param token Token to sell
     * @param currentAllocation Current allocation (bps)
     * @param targetAllocation Target allocation (bps)
     * @param totalValue Total portfolio value
     * @return amountToSell Amount to sell
     */
    function _calculateSellAmount(
        UserVault vault,
        address token,
        uint256 currentAllocation,
        uint256 targetAllocation,
        int64 totalValue
    ) internal view returns (int64 amountToSell) {
        if (currentAllocation <= targetAllocation) {
            return 0; // No need to sell
        }
        
        // Calculate excess allocation
        uint256 excessAllocation = currentAllocation - targetAllocation;
        
        // Calculate amount to sell
        uint256 amountUint = (uint256(uint64(totalValue)) * excessAllocation) / BASIS_POINTS;
        
        amountToSell = int64(uint64(amountUint));
        
        // Ensure we don't exceed available balance
        int64 availableBalance = vault.getBalance(token);
        if (amountToSell > availableBalance) {
            amountToSell = availableBalance;
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
        ) = _calculateCurrentAllocations(userVault, token0, token1);
        
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
        swapper = SaucerSwapper(newSwapper);
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
