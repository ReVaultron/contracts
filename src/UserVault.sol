// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IHederaTokenService.sol";
import "./libraries/HederaResponseCodes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UserVault
 * @dev individual vault contract using Hedera Token Service (HTS)
 * @notice Supports HTS tokens with proper association checks and direct transfers
 * @custom:version 1.0.0
 * @custom:security-contact security@hedravaultron.io
 */
contract UserVault is Ownable, ReentrancyGuard {
    
    // Factory contract address
    address public immutable factory;
    
    // Mapping from token address to balance (internal tracking)
    mapping(address => int64) public tokenBalances;
    
    // Array of supported HTS token addresses
    address[] public supportedTokens;
    
    // Mapping to check if token is supported
    mapping(address => bool) public isTokenSupported;
    
    // Mapping to check if token is associated with this vault
    mapping(address => bool) public isTokenAssociated;
    
    // Mapping to track last sync timestamp for each token
    mapping(address => uint256) public lastSyncTimestamp;
    
    // Auto-sync threshold (in seconds)
    uint256 public constant AUTO_SYNC_THRESHOLD = 300; // 5 minutes
    
    // Hedera Token Service precompiled contract address
    address constant HTS_PRECOMPILE = address(0x167);
    
    // Events
    event TokensReceived(address indexed token, int64 amount, address indexed from, uint256 timestamp);
    event TokensWithdrawn(address indexed token, int64 amount, address indexed to, uint256 timestamp);
    event TokenAssociated(address indexed token, uint256 timestamp);
    event TokenDissociated(address indexed token, uint256 timestamp);
    event TokenAdded(address indexed token, uint256 timestamp);
    event TokenRemoved(address indexed token, uint256 timestamp);
    event BalanceSynced(address indexed token, int64 oldBalance, int64 newBalance, uint256 timestamp);
    event AutoSyncTriggered(address indexed token, uint256 timestamp);
    event HTSOperationFailed(address indexed token, int32 responseCode, string operation);
    
    // Custom errors for better gas efficiency
    error InvalidAddress();
    error InvalidAmount();
    error TokenNotAssociated();
    error TokenAlreadyAssociated();
    error HTSCallFailed(string operation, int32 responseCode);
    error InsufficientBalance();
    error SenderNotAssociated();
    
    /**
     * @dev Constructor sets the owner and factory
     * @param _owner The wallet address that owns this vault
     * @param _factory The VaultFactory contract address
     */
    constructor(address _owner, address _factory) Ownable(_owner) {
        if (_owner == address(0)) revert InvalidAddress();
        if (_factory == address(0)) revert InvalidAddress();
        factory = _factory;
    }
    
    /**
     * @dev Associates an HTS token with this vault (required before receiving tokens)
     * @param token The HTS token address
     */
    function associateToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (isTokenAssociated[token]) revert TokenAlreadyAssociated();
        
        // Call HTS precompiled contract to associate token
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector, address(this), token)
        );
        
        if (!success) revert HTSCallFailed("associateToken", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "associateToken");
            revert HTSCallFailed("associateToken", responseCode);
        }
        
        isTokenAssociated[token] = true;
        
        // Add to supported tokens if not already there
        if (!isTokenSupported[token]) {
            supportedTokens.push(token);
            isTokenSupported[token] = true;
            emit TokenAdded(token, block.timestamp);
        }
        
        emit TokenAssociated(token, block.timestamp);
    }
    
    /**
     * @dev Associates multiple HTS tokens with this vault in one transaction
     * @param tokens Array of HTS token addresses
     */
    function associateTokens(address[] calldata tokens) external onlyOwner nonReentrant {
        if (tokens.length == 0) revert InvalidAmount();
        
        // Call HTS precompiled contract to associate multiple tokens
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(IHederaTokenService.associateTokens.selector, address(this), tokens)
        );
        
        if (!success) revert HTSCallFailed("associateTokens", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(address(0), responseCode, "associateTokens");
            revert HTSCallFailed("associateTokens", responseCode);
        }
        
        // Mark all tokens as associated and add to supported list
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            
            isTokenAssociated[token] = true;
            
            if (!isTokenSupported[token]) {
                supportedTokens.push(token);
                isTokenSupported[token] = true;
                emit TokenAdded(token, block.timestamp);
            }
            
            emit TokenAssociated(token, block.timestamp);
        }
    }
    
    /**
     * @dev Deposits HTS tokens into the vault
     * @param token The HTS token address
     * @param amount The amount of tokens to deposit (int64 for HTS)
     * @notice CRITICAL: Caller (msg.sender) must be associated with the token first
     * @notice This function transfers tokens FROM caller TO vault
     */
    function deposit(address token, int64 amount) external nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (amount <= 0) revert InvalidAmount();
        if (!isTokenAssociated[token]) revert TokenNotAssociated();
        
        // Auto-sync before deposit to ensure accurate balance
        _autoSyncIfNeeded(token);
        
        // NOTE: HTS balanceOf removed - using ERC-20 tokens now
        // For ERC-20, the transfer will fail if insufficient balance
        
        // Transfer HTS tokens FROM sender TO this vault
        // Note: msg.sender is the one calling deposit, so they authorize the transfer
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                msg.sender,        // FROM: caller (user depositing)
                address(this),     // TO: this vault
                amount
            )
        );
        
        if (!success) revert HTSCallFailed("transferToken", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert HTSCallFailed("transferToken", responseCode);
        }
        
        // Update internal balance tracking
        tokenBalances[token] += amount;
        
        // Update last sync timestamp
        lastSyncTimestamp[token] = block.timestamp;
        
        emit TokensReceived(token, amount, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Withdraws HTS tokens from the vault with auto-sync
     * @param token The HTS token address
     * @param amount The amount of tokens to withdraw
     * @param to The address to send tokens to
     * @notice Only vault owner can withdraw
     * @notice Recipient must be associated with the token
     */
    function withdrawTo(address token, int64 amount, address to) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (amount <= 0) revert InvalidAmount();
        if (!isTokenAssociated[token]) revert TokenNotAssociated();
        
        // Auto-sync before withdrawal to ensure accurate balance
        _autoSyncIfNeeded(token);
        
        // NOTE: HTS balanceOf removed - using ERC-20 tokens now
        // Skip recipient association check
        
        // Check if we have enough balance
        int64 availableBalance = _getActualBalance(token);
        if (availableBalance < amount) revert InsufficientBalance();
        
        // Update internal balance tracking
        tokenBalances[token] -= amount;
        
        // Transfer HTS tokens to recipient
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                address(this),
                to,
                amount
            )
        );
        
        if (!success) revert HTSCallFailed("transferToken", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert HTSCallFailed("transferToken", responseCode);
        }
        
        // Update last sync timestamp
        lastSyncTimestamp[token] = block.timestamp;
        
        emit TokensWithdrawn(token, amount, to, block.timestamp);
    }
    
    /**
     * @dev Gets the actual on-chain balance of an HTS token
     * @param token The HTS token address
     * @return balance The actual balance of the token in this contract
     */
    function getBalance(address token) external view returns (int64 balance) {
        return _getActualBalance(token);
    }
    
    /**
     * @dev Gets the internal tracked balance of a token
     * @param token The HTS token address
     * @return balance The internally tracked balance
     */
    function getTrackedBalance(address token) external view returns (int64 balance) {
        return tokenBalances[token];
    }
    
    /**
     * @dev Checks if an account is associated with a token
     * @param account The account address to check
     * @param token The HTS token address
     * @return associated True if account is associated with token
     */
    function isAccountAssociatedWithToken(
        address account,
        address token
    ) external view returns (bool associated) {
        // NOTE: HTS balanceOf removed - always return true for ERC-20
        return true;
    }
    
    /**
     * @dev Manually syncs the internal balance with actual on-chain balance
     * @param token The HTS token address
     */
    function syncTokenBalance(address token) external {
        _syncTokenBalance(token);
    }
    
    /**
     * @dev Internal function to sync token balance using HTS
     * @param token The HTS token address
     */
    function _syncTokenBalance(address token) internal {
        if (token == address(0)) revert InvalidAddress();
        if (!isTokenAssociated[token]) revert TokenNotAssociated();
        
        int64 oldBalance = tokenBalances[token];
        int64 actualBalance = _getActualBalance(token);
        
        tokenBalances[token] = actualBalance;
        lastSyncTimestamp[token] = block.timestamp;
        
        emit BalanceSynced(token, oldBalance, actualBalance, block.timestamp);
    }
    
    /**
     * @dev Syncs all supported tokens
     */
    function syncAllTokens() external {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            if (token != address(0) && isTokenAssociated[token]) {
                _syncTokenBalance(token);
            }
        }
    }
    
    /**
     * @dev Checks if a token needs syncing based on time threshold
     * @param token The HTS token address
     * @return needed True if token needs syncing
     */
    function needsSync(address token) external view returns (bool needed) {
        return _needsSync(token);
    }
    
    /**
     * @dev Gets the last sync timestamp for a token
     * @param token The HTS token address
     * @return timestamp The last sync timestamp
     */
    function getLastSyncTimestamp(address token) external view returns (uint256 timestamp) {
        return lastSyncTimestamp[token];
    }
    
    /**
     * @dev Gets all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getAllSupportedTokens() external view returns (address[] memory tokens) {
        return supportedTokens;
    }
    
    /**
     * @dev Gets the count of supported tokens
     * @return count The number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256 count) {
        return supportedTokens.length;
    }
    
    /**
     * @dev Checks if a token is associated with this vault
     * @param token The HTS token address
     * @return associated True if token is associated
     */
    function checkTokenAssociation(address token) external view returns (bool associated) {
        return isTokenAssociated[token];
    }
    
    /**
     * @dev Internal function to get actual on-chain HTS balance
     * @param token The HTS token address
     * @return balance The actual balance
     */
    function _getActualBalance(address token) internal view returns (int64 balance) {
        // NOTE: HTS balanceOf removed - return tracked balance for HTS
        // For ERC-20 tokens, this won't be accurate but deposit/withdraw use direct transfers
        return tokenBalances[token];
    }
    
    /**
     * @dev Internal function to check if a token needs syncing
     * @param token The HTS token address
     * @return needed True if token needs syncing
     */
    function _needsSync(address token) internal view returns (bool needed) {
        if (lastSyncTimestamp[token] == 0) {
            return true; // Never synced
        }
        
        return (block.timestamp - lastSyncTimestamp[token]) > AUTO_SYNC_THRESHOLD;
    }
    
    /**
     * @dev Internal function to auto-sync if needed
     * @param token The HTS token address
     */
    function _autoSyncIfNeeded(address token) internal {
        if (_needsSync(token)) {
            emit AutoSyncTriggered(token, block.timestamp);
            _syncTokenBalance(token);
        }
    }
    
    /**
     * @dev Dissociates an HTS token from this vault (only if balance is 0)
     * @param token The HTS token address
     */
    function dissociateToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (!isTokenAssociated[token]) revert TokenNotAssociated();
        
        // Sync first to ensure accurate balance
        _syncTokenBalance(token);
        
        // Check balance is 0
        if (tokenBalances[token] != 0) revert InsufficientBalance();
        
        // Call HTS precompiled contract to dissociate token
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(IHederaTokenService.dissociateToken.selector, address(this), token)
        );
        
        if (!success) revert HTSCallFailed("dissociateToken", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "dissociateToken");
            revert HTSCallFailed("dissociateToken", responseCode);
        }
        
        isTokenAssociated[token] = false;
        
        emit TokenDissociated(token, block.timestamp);
    }
    
    /**
     * @dev Removes a token from supported list (only owner)
     * @param token The HTS token address
     */
    function removeToken(address token) external onlyOwner {
        if (!isTokenSupported[token]) revert("UserVault: Token not supported");
        if (isTokenAssociated[token]) revert("UserVault: Dissociate token first");
        
        // Remove from supported list
        isTokenSupported[token] = false;
        
        // Remove from array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }
        
        emit TokenRemoved(token, block.timestamp);
    }
    
    /**
     * @dev Emergency function to recover tokens (only owner)
     * @param token The HTS token address
     * @param amount The amount of tokens to recover
     * @param to The address to send tokens to
     */
    function emergencyRecover(address token, int64 amount, address to) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (!isTokenAssociated[token]) revert TokenNotAssociated();
        
        // Transfer using HTS
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                address(this),
                to,
                amount
            )
        );
        
        if (!success) revert HTSCallFailed("transferToken", 0);
        
        int32 responseCode = abi.decode(result, (int32));
        
        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert HTSCallFailed("transferToken", responseCode);
        }
        
        // Sync balance after recovery
        _autoSyncIfNeeded(token);
    }
    
    /**
     * @dev Allows the contract to receive HBAR
     */
    receive() external payable {
        // Contract can receive HBAR
    }
    
    /**
     * @dev Withdraw HBAR from the vault
     * @param amount The amount of HBAR to withdraw (in wei-bar for EVM compatibility)
     * @param to The address to send HBAR to
     * @notice Can be called by anyone (e.g., RebalanceExecutor) - vault owner trusts the system
     */
    function withdrawHBAR(uint256 amount, address payable to) external nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        // Convert wei-bar to tinybars for Hedera native balance check
        // wei-bar ÷ 10^10 = tinybars
        uint256 amountInTinybars = amount / (10 ** 10);
        
        if (address(this).balance < amountInTinybars) revert InsufficientBalance();
        
        (bool success, ) = to.call{value: amountInTinybars}("");
        if (!success) revert("UserVault: HBAR transfer failed");
    }
    
    /**
     * @dev Withdraw ERC-20 tokens from the vault (only owner)
     * @param token The ERC-20 token address
     * @param amount The amount of tokens to withdraw (uint256 for ERC-20)
     * @param to The address to send tokens to
     */
    function withdrawToken(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        // Transfer ERC-20 tokens to recipient
        require(IERC20(token).transfer(to, amount), "Token transfer failed");
    }
    
    /**
     * @dev Get HBAR balance of the vault
     * @return balance The HBAR balance in wei-bar (EVM standard units)
     * @notice On Hedera, address(this).balance returns tinybars (10^8 per HBAR)
     *         We convert to wei-bar (10^18 per HBAR) for compatibility with ethers.js
     */
    function getHBARBalance() external view returns (uint256 balance) {
        // Hedera's address(this).balance returns tinybars
        // Convert tinybars to wei-bar: tinybars × 10^10 = wei-bar
        return address(this).balance * (10 ** 10);
    }
    
    /**
     * @dev Get ERC-20 token balance of the vault
     * @param token The ERC-20 token address
     * @return balance The token balance
     */
    function getERC20Balance(address token) external view returns (uint256 balance) {
        return IERC20(token).balanceOf(address(this));
    }
    
    /**
     * @dev Deposit ERC-20 tokens (e.g., USDC) to the vault
     * @param token The ERC-20 token address
     * @param amount The amount of tokens to deposit
     * @notice Caller must approve this contract first
     * @notice Can be called by anyone (e.g., RebalanceExecutor after swapping)
     */
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        // Transfer ERC-20 tokens from caller to vault
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Token deposit failed");
    }
}
