// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./interfaces/IHederaTokenService.sol";
import "./libraries/HederaResponseCodes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title UserVault
 * @dev Individual vault contract for each user using Hedera Token Service (HTS)
 * @notice Supports HTS tokens (fungible and non-fungible) with native Hedera integration
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

    // Auto-sync threshold (in seconds) - sync if last sync was more than this ago
    uint256 public constant AUTO_SYNC_THRESHOLD = 300; // 5 minutes

    // Hedera Token Service precompiled contract address
    address constant HTS_PRECOMPILE = address(0x167);

    // Events
    event TokensReceived(
        address indexed token,
        int64 amount,
        address indexed from,
        uint256 timestamp
    );
    event TokensWithdrawn(
        address indexed token,
        int64 amount,
        address indexed to,
        uint256 timestamp
    );
    event TokenAssociated(address indexed token, uint256 timestamp);
    event TokenDissociated(address indexed token, uint256 timestamp);
    event TokenAdded(address indexed token, uint256 timestamp);
    event TokenRemoved(address indexed token, uint256 timestamp);
    event BalanceSynced(
        address indexed token,
        int64 oldBalance,
        int64 newBalance,
        uint256 timestamp
    );
    event AutoSyncTriggered(address indexed token, uint256 timestamp);
    event HTSOperationFailed(
        address indexed token,
        int responseCode,
        string operation
    );

    /**
     * @dev Constructor sets the owner and factory
     * @param _owner The wallet address that owns this vault
     * @param _factory The VaultFactory contract address
     */
    constructor(address _owner, address _factory) Ownable(_owner) {
        require(_owner != address(0), "UserVault: Invalid owner");
        require(_factory != address(0), "UserVault: Invalid factory");
        factory = _factory;
    }

    /**
     * @dev Associates an HTS token with this vault (required before receiving tokens)
     * @param token The HTS token address
     */
    function associateToken(address token) external onlyOwner nonReentrant {
        require(token != address(0), "UserVault: Invalid token address");
        require(
            !isTokenAssociated[token],
            "UserVault: Token already associated"
        );

        // Call HTS precompiled contract to associate token
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.associateToken.selector,
                address(this),
                token
            )
        );

        require(success, "UserVault: HTS call failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "associateToken");
            revert("UserVault: Token association failed");
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
    function associateTokens(
        address[] calldata tokens
    ) external onlyOwner nonReentrant {
        require(tokens.length > 0, "UserVault: Empty tokens array");

        // Call HTS precompiled contract to associate multiple tokens
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.associateTokens.selector,
                address(this),
                tokens
            )
        );

        require(success, "UserVault: HTS call failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(
                address(0),
                responseCode,
                "associateTokens"
            );
            revert("UserVault: Tokens association failed");
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
     * @dev Deposits HTS tokens into the vault with auto-sync
     * @param token The HTS token address
     * @param amount The amount of tokens to deposit (int64 for HTS)
     */
    function deposit(address token, int64 amount) external nonReentrant {
        require(token != address(0), "UserVault: Invalid token address");
        require(amount > 0, "UserVault: Amount must be greater than 0");
        require(isTokenAssociated[token], "UserVault: Token not associated");

        // Auto-sync before deposit to ensure accurate balance
        _autoSyncIfNeeded(token);

        // Transfer HTS tokens from sender to this contract
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.transferToken.selector,
                token,
                msg.sender,
                address(this),
                amount
            )
        );

        require(success, "UserVault: HTS transfer failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert("UserVault: Token transfer failed");
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
     */
    function withdrawTo(
        address token,
        int64 amount,
        address to
    ) external onlyOwner nonReentrant {
        require(token != address(0), "UserVault: Invalid token address");
        require(to != address(0), "UserVault: Invalid recipient address");
        require(amount > 0, "UserVault: Amount must be greater than 0");
        require(isTokenAssociated[token], "UserVault: Token not associated");

        // Auto-sync before withdrawal to ensure accurate balance
        _autoSyncIfNeeded(token);

        // Check if we have enough balance
        int64 availableBalance = _getActualBalance(token);
        require(
            availableBalance >= amount,
            "UserVault: Insufficient vault balance"
        );

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

        require(success, "UserVault: HTS transfer failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert("UserVault: Token transfer failed");
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
    function getTrackedBalance(
        address token
    ) external view returns (int64 balance) {
        return tokenBalances[token];
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
        require(token != address(0), "UserVault: Invalid token address");
        require(isTokenAssociated[token], "UserVault: Token not associated");

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
    function getLastSyncTimestamp(
        address token
    ) external view returns (uint256 timestamp) {
        return lastSyncTimestamp[token];
    }

    /**
     * @dev Gets all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getAllSupportedTokens()
        external
        view
        returns (address[] memory tokens)
    {
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
    function checkTokenAssociation(
        address token
    ) external view returns (bool associated) {
        return isTokenAssociated[token];
    }

    /**
     * @dev Internal function to get actual on-chain HTS balance
     * @param token The HTS token address
     * @return balance The actual balance
     */
    function _getActualBalance(
        address token
    ) internal view returns (int64 balance) {
        // Call HTS precompiled contract to get token balance
        (bool success, bytes memory result) = HTS_PRECOMPILE.staticcall(
            abi.encodeWithSelector(
                IHederaTokenService.balanceOf.selector,
                token,
                address(this)
            )
        );

        if (!success) {
            return 0;
        }

        (int32 responseCode, int64 tokenBalance) = abi.decode(
            result,
            (int32, int64)
        );

        if (responseCode != HederaResponseCodes.SUCCESS) {
            return 0;
        }

        return tokenBalance;
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

        return
            (block.timestamp - lastSyncTimestamp[token]) > AUTO_SYNC_THRESHOLD;
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
        require(token != address(0), "UserVault: Invalid token address");
        require(isTokenAssociated[token], "UserVault: Token not associated");

        // Sync first to ensure accurate balance
        _syncTokenBalance(token);

        // Check balance is 0
        require(
            tokenBalances[token] == 0,
            "UserVault: Token balance must be 0"
        );

        // Call HTS precompiled contract to dissociate token
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSelector(
                IHederaTokenService.dissociateToken.selector,
                address(this),
                token
            )
        );

        require(success, "UserVault: HTS call failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "dissociateToken");
            revert("UserVault: Token dissociation failed");
        }

        isTokenAssociated[token] = false;

        emit TokenDissociated(token, block.timestamp);
    }

    /**
     * @dev Removes a token from supported list (only owner)
     * @param token The HTS token address
     */
    function removeToken(address token) external onlyOwner {
        require(isTokenSupported[token], "UserVault: Token not supported");
        require(!isTokenAssociated[token], "UserVault: Dissociate token first");

        // Remove from supported list
        isTokenSupported[token] = false;

        // Remove from array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
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
    function emergencyRecover(
        address token,
        int64 amount,
        address to
    ) external onlyOwner nonReentrant {
        require(token != address(0), "UserVault: Invalid token address");
        require(to != address(0), "UserVault: Invalid recipient address");
        require(isTokenAssociated[token], "UserVault: Token not associated");

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

        require(success, "UserVault: HTS transfer failed");

        int32 responseCode = abi.decode(result, (int32));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            emit HTSOperationFailed(token, responseCode, "transferToken");
            revert("UserVault: Emergency recovery failed");
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
     * @dev Withdraw HBAR from the vault (only owner)
     * @param amount The amount of HBAR to withdraw (in tinybars)
     * @param to The address to send HBAR to
     */
    function withdrawHBAR(
        uint256 amount,
        address payable to
    ) external onlyOwner nonReentrant {
        require(to != address(0), "UserVault: Invalid recipient");
        require(amount > 0, "UserVault: Invalid amount");
        require(
            address(this).balance >= amount,
            "UserVault: Insufficient HBAR balance"
        );

        (bool success, ) = to.call{value: amount}("");
        require(success, "UserVault: HBAR transfer failed");
    }

    /**
     * @dev Get HBAR balance of the vault
     * @return balance The HBAR balance in tinybars
     */
    function getHBARBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }
}
