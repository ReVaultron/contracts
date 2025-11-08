import {
  Contract,
  Provider,
  Signer,
  Wallet,
  JsonRpcProvider,
  BrowserProvider,
  type Abi,
  type ContractTransactionResponse
} from 'ethers';

/**
 * Services for interacting with Revaultron smart contracts
 * Uses ethers.js v6 for blockchain interactions
 * Primary method uses private key signing for transactions
 */

// Type definitions for contract ABIs
export type ContractABI = Abi;

// Type definitions for contract addresses
export interface ContractAddresses {
  userVault?: string;
  vaultFactory: string;
  volatilityIndex: string;
}

/**
 * UserVault Service
 * Handles all interactions with the UserVault contract
 * Individual vault contract for each user using Hedera Token Service (HTS)
 */
export class UserVaultService {
  private contract: Contract;
  private signer: Signer;

  constructor(
    address: string,
    abi: ContractABI,
    signer: Signer
  ) {
    this.contract = new Contract(address, abi, signer);
    this.signer = signer;
  }

  // ============ VIEW FUNCTIONS ============

  /**
   * Gets the factory contract address that created this vault
   * @returns {Promise<string>} The factory contract address
   */
  async factory(): Promise<string> {
    return await this.contract.factory();
  }

  /**
   * Gets the internally tracked balance for a specific token
   * @param {string} token - The HTS token address
   * @returns {Promise<bigint>} The internally tracked balance (int64 in Solidity, bigint in JS)
   */
  async tokenBalances(token: string): Promise<bigint> {
    return await this.contract.tokenBalances(token);
  }

  /**
   * Gets a supported token address by index
   * @param {bigint} index - The index in the supported tokens array
   * @returns {Promise<string>} The token address at the given index
   */
  async supportedTokens(index: bigint): Promise<string> {
    return await this.contract.supportedTokens(index);
  }

  /**
   * Checks if a token is supported by this vault
   * @param {string} token - The HTS token address
   * @returns {Promise<boolean>} True if the token is supported
   */
  async isTokenSupported(token: string): Promise<boolean> {
    return await this.contract.isTokenSupported(token);
  }

  /**
   * Checks if a token is associated with this vault
   * @param {string} token - The HTS token address
   * @returns {Promise<boolean>} True if the token is associated
   */
  async isTokenAssociated(token: string): Promise<boolean> {
    return await this.contract.isTokenAssociated(token);
  }

  /**
   * Gets the last sync timestamp for a token
   * @param {string} token - The HTS token address
   * @returns {Promise<bigint>} The last sync timestamp in seconds
   */
  async lastSyncTimestamp(token: string): Promise<bigint> {
    return await this.contract.lastSyncTimestamp(token);
  }

  /**
   * Gets the auto-sync threshold constant
   * @returns {Promise<bigint>} The auto-sync threshold in seconds (default: 300)
   */
  async AUTO_SYNC_THRESHOLD(): Promise<bigint> {
    return await this.contract.AUTO_SYNC_THRESHOLD();
  }

  /**
   * Gets the actual on-chain balance of an HTS token
   * @param {string} token - The HTS token address
   * @returns {Promise<bigint>} The actual on-chain balance (int64 in Solidity, bigint in JS)
   */
  async getBalance(token: string): Promise<bigint> {
    return await this.contract.getBalance(token);
  }

  /**
   * Gets the internally tracked balance of a token
   * @param {string} token - The HTS token address
   * @returns {Promise<bigint>} The internally tracked balance (int64 in Solidity, bigint in JS)
   */
  async getTrackedBalance(token: string): Promise<bigint> {
    return await this.contract.getTrackedBalance(token);
  }

  /**
   * Checks if a token needs syncing based on time threshold
   * @param {string} token - The HTS token address
   * @returns {Promise<boolean>} True if the token needs syncing
   */
  async needsSync(token: string): Promise<boolean> {
    return await this.contract.needsSync(token);
  }

  /**
   * Gets the last sync timestamp for a token
   * @param {string} token - The HTS token address
   * @returns {Promise<bigint>} The last sync timestamp in seconds
   */
  async getLastSyncTimestamp(token: string): Promise<bigint> {
    return await this.contract.getLastSyncTimestamp(token);
  }

  /**
   * Gets all supported token addresses
   * @returns {Promise<string[]>} Array of supported token addresses
   */
  async getAllSupportedTokens(): Promise<string[]> {
    return await this.contract.getAllSupportedTokens();
  }

  /**
   * Gets the count of supported tokens
   * @returns {Promise<bigint>} The number of supported tokens
   */
  async getSupportedTokenCount(): Promise<bigint> {
    return await this.contract.getSupportedTokenCount();
  }

  /**
   * Checks if a token is associated with this vault
   * @param {string} token - The HTS token address
   * @returns {Promise<boolean>} True if the token is associated
   */
  async checkTokenAssociation(token: string): Promise<boolean> {
    return await this.contract.checkTokenAssociation(token);
  }

  /**
   * Gets the HBAR balance of the vault
   * @returns {Promise<bigint>} The HBAR balance in tinybars
   */
  async getHBARBalance(): Promise<bigint> {
    return await this.contract.getHBARBalance();
  }

  // ============ WRITE FUNCTIONS ============

  /**
   * Associates an HTS token with this vault (required before receiving tokens)
   * @param {string} token - The HTS token address to associate
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async associateToken(
    token: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.associateToken(token, options || {});
  }

  /**
   * Associates multiple HTS tokens with this vault in one transaction
   * @param {string[]} tokens - Array of HTS token addresses to associate
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async associateTokens(
    tokens: string[],
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.associateTokens(tokens, options || {});
  }

  /**
   * Deposits HTS tokens into the vault with auto-sync
   * @param {string} token - The HTS token address
   * @param {bigint} amount - The amount of tokens to deposit (int64 in Solidity, bigint in JS)
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async deposit(
    token: string,
    amount: bigint,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.deposit(token, amount, options || {});
  }

  /**
   * Withdraws HTS tokens from the vault with auto-sync
   * @param {string} token - The HTS token address
   * @param {bigint} amount - The amount of tokens to withdraw (int64 in Solidity, bigint in JS)
   * @param {string} to - The address to send tokens to
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async withdrawTo(
    token: string,
    amount: bigint,
    to: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.withdrawTo(token, amount, to, options || {});
  }

  /**
   * Manually syncs the internal balance with actual on-chain balance
   * @param {string} token - The HTS token address
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async syncTokenBalance(
    token: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.syncTokenBalance(token, options || {});
  }

  /**
   * Syncs all supported tokens
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async syncAllTokens(
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.syncAllTokens(options || {});
  }

  /**
   * Dissociates an HTS token from this vault (only if balance is 0)
   * @param {string} token - The HTS token address to dissociate
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async dissociateToken(
    token: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.dissociateToken(token, options || {});
  }

  /**
   * Removes a token from supported list (only if not associated)
   * @param {string} token - The HTS token address to remove
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async removeToken(
    token: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.removeToken(token, options || {});
  }

  /**
   * Emergency function to recover tokens (only owner)
   * @param {string} token - The HTS token address
   * @param {bigint} amount - The amount of tokens to recover (int64 in Solidity, bigint in JS)
   * @param {string} to - The address to send tokens to
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async emergencyRecover(
    token: string,
    amount: bigint,
    to: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.emergencyRecover(token, amount, to, options || {});
  }

  /**
   * Withdraws HBAR from the vault (only owner)
   * @param {bigint} amount - The amount of HBAR to withdraw in tinybars
   * @param {string} to - The address to send HBAR to
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async withdrawHBAR(
    amount: bigint,
    to: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.withdrawHBAR(amount, to, options || {});
  }

  /**
   * Get the underlying contract instance for advanced usage
   * @returns {Contract} The ethers Contract instance
   */
  getContract(): Contract {
    return this.contract;
  }
}

/**
 * VaultFactory Service
 * Handles all interactions with the VaultFactory contract
 * Factory contract for creating user-specific vaults on Hedera
 */
export class VaultFactoryService {
  private contract: Contract;
  private signer: Signer;

  constructor(
    address: string,
    abi: ContractABI,
    signer: Signer
  ) {
    this.contract = new Contract(address, abi, signer);
    this.signer = signer;
  }

  // ============ VIEW FUNCTIONS ============

  /**
   * Gets the vault address for a specific user
   * @param {string} user - The user's address
   * @returns {Promise<string>} The vault address, or zero address if none exists
   */
  async userVaults(user: string): Promise<string> {
    return await this.contract.userVaults(user);
  }

  /**
   * Gets a vault address by index from the allVaults array
   * @param {bigint} index - The index in the allVaults array
   * @returns {Promise<string>} The vault address at the given index
   */
  async allVaults(index: bigint): Promise<string> {
    return await this.contract.allVaults(index);
  }

  /**
   * Checks if an address is a valid vault created by this factory
   * @param {string} vault - The address to check
   * @returns {Promise<boolean>} True if the address is a valid vault
   */
  async isVault(vault: string): Promise<boolean> {
    return await this.contract.isVault(vault);
  }

  /**
   * Gets the current vault creation fee
   * @returns {Promise<bigint>} The creation fee in tinybars
   */
  async vaultCreationFee(): Promise<bigint> {
    return await this.contract.vaultCreationFee();
  }

  /**
   * Gets the vault address for a specific user
   * @param {string} user - The user's address
   * @returns {Promise<string>} The vault address, or zero address if none exists
   */
  async getVault(user: string): Promise<string> {
    return await this.contract.getVault(user);
  }

  /**
   * Checks if a user has a vault
   * @param {string} user - The user's address
   * @returns {Promise<boolean>} True if the user has a vault
   */
  async hasVault(user: string): Promise<boolean> {
    return await this.contract.hasVault(user);
  }

  /**
   * Checks if an address is a valid vault created by this factory
   * @param {string} vault - The address to check
   * @returns {Promise<boolean>} True if the address is a valid vault
   */
  async isValidVault(vault: string): Promise<boolean> {
    return await this.contract.isValidVault(vault);
  }

  /**
   * Gets the total number of vaults created
   * @returns {Promise<bigint>} The number of vaults
   */
  async getVaultCount(): Promise<bigint> {
    return await this.contract.getVaultCount();
  }

  /**
   * Gets vault addresses (paginated for gas efficiency)
   * @param {bigint} offset - Starting index
   * @param {bigint} limit - Maximum number of vaults to return
   * @returns {Promise<string[]>} Array of vault addresses
   */
  async getVaults(offset: bigint, limit: bigint): Promise<string[]> {
    return await this.contract.getVaults(offset, limit);
  }

  /**
   * Gets all vault addresses (only owner, use with caution for large arrays)
   * @returns {Promise<string[]>} Array of all vault addresses
   */
  async getAllVaults(): Promise<string[]> {
    return await this.contract.getAllVaults();
  }

  /**
   * Gets the current vault creation fee
   * @returns {Promise<bigint>} The creation fee in tinybars
   */
  async getCreationFee(): Promise<bigint> {
    return await this.contract.getCreationFee();
  }

  /**
   * Gets the contract's HBAR balance
   * @returns {Promise<bigint>} The balance in tinybars
   */
  async getBalance(): Promise<bigint> {
    return await this.contract.getBalance();
  }

  // ============ WRITE FUNCTIONS ============

  /**
   * Creates a new vault for the caller
   * Each user can only have one vault
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (must be >= creation fee, in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async createVault(
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.createVault(options || {});
  }

  /**
   * Updates the vault creation fee (only owner)
   * @param {bigint} newFee - The new creation fee in tinybars
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async setCreationFee(
    newFee: bigint,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.setCreationFee(newFee, options || {});
  }

  /**
   * Withdraws accumulated fees (only owner)
   * @param {string} to - Address to send fees to
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async withdrawFees(
    to: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.withdrawFees(to, options || {});
  }

  /**
   * Removes a vault (only owner, emergency use only)
   * @param {string} user - The user whose vault should be removed
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async removeVault(
    user: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.removeVault(user, options || {});
  }

  /**
   * Get the underlying contract instance for advanced usage
   * @returns {Contract} The ethers Contract instance
   */
  getContract(): Contract {
    return this.contract;
  }
}

/**
 * VolatilityIndex Service
 * Handles all interactions with the VolatilityIndex contract
 * Contract to track and store volatility data for token pairs using Pyth price feeds on Hedera
 */
export class VolatilityIndexService {
  private contract: Contract;
  private signer: Signer;

  constructor(
    address: string,
    abi: ContractABI,
    signer: Signer
  ) {
    this.contract = new Contract(address, abi, signer);
    this.signer = signer;
  }

  // ============ VIEW FUNCTIONS ============

  /**
   * Gets the Pyth contract address
   * @returns {Promise<string>} The Pyth contract address
   */
  async pyth(): Promise<string> {
    return await this.contract.pyth();
  }

  /**
   * Gets the volatility data for a price feed
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<Object>} Volatility data object
   * @returns {Promise<bigint>} volatilityBps - Volatility in basis points
   * @returns {Promise<bigint>} price - Current price (int64 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} confidence - Pyth confidence interval (uint64 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} expo - Price exponent (int32 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} timestamp - When this volatility was calculated
   */
  async volatilityData(priceFeedId: string): Promise<{
    volatilityBps: bigint;
    price: bigint;
    confidence: bigint;
    expo: bigint;
    timestamp: bigint;
  }> {
    return await this.contract.volatilityData(priceFeedId);
  }

  /**
   * Gets a supported price feed ID by index
   * @param {bigint} index - The index in the supportedFeeds array
   * @returns {Promise<string>} The price feed ID (bytes32 in Solidity, hex string in JS)
   */
  async supportedFeeds(index: bigint): Promise<string> {
    return await this.contract.supportedFeeds(index);
  }

  /**
   * Checks if a price feed is supported
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<boolean>} True if the feed is supported
   */
  async isFeedSupported(priceFeedId: string): Promise<boolean> {
    return await this.contract.isFeedSupported(priceFeedId);
  }

  /**
   * Checks if an address is authorized to update volatility
   * @param {string} updater - The address to check
   * @returns {Promise<boolean>} True if the address is authorized
   */
  async isAuthorizedUpdater(updater: string): Promise<boolean> {
    return await this.contract.isAuthorizedUpdater(updater);
  }

  /**
   * Gets the maximum allowed volatility constant
   * @returns {Promise<bigint>} Maximum volatility in basis points (1,000,000 = 10000%)
   */
  async MAX_VOLATILITY_BPS(): Promise<bigint> {
    return await this.contract.MAX_VOLATILITY_BPS();
  }

  /**
   * Gets the maximum price staleness threshold
   * @returns {Promise<bigint>} Maximum staleness in seconds
   */
  async maxPriceStaleness(): Promise<bigint> {
    return await this.contract.maxPriceStaleness();
  }

  /**
   * Gets the current volatility data for a price feed
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<Object>} Volatility data object
   * @returns {Promise<bigint>} volatilityBps - Volatility in basis points
   * @returns {Promise<bigint>} price - Current price (int64 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} confidence - Pyth confidence interval (uint64 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} expo - Price exponent (int32 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} timestamp - When this volatility was calculated
   */
  async getVolatilityData(priceFeedId: string): Promise<{
    volatilityBps: bigint;
    price: bigint;
    confidence: bigint;
    expo: bigint;
    timestamp: bigint;
  }> {
    return await this.contract.getVolatilityData(priceFeedId);
  }

  /**
   * Gets the current volatility in basis points
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<bigint>} The volatility in basis points
   */
  async getVolatility(priceFeedId: string): Promise<bigint> {
    return await this.contract.getVolatility(priceFeedId);
  }

  /**
   * Gets the current price for a price feed with full precision
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<Array>} Tuple containing [price, expo, confidence]
   * @returns {Promise<bigint>} price - The current price (int64 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} expo - The price exponent (int32 in Solidity, bigint in JS)
   * @returns {Promise<bigint>} confidence - The confidence interval (uint64 in Solidity, bigint in JS)
   */
  async getCurrentPrice(priceFeedId: string): Promise<[bigint, bigint, bigint]> {
    return await this.contract.getCurrentPrice(priceFeedId);
  }

  /**
   * Gets the normalized price (price * 10^18 / 10^expo)
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<bigint>} The normalized price with 18 decimals
   */
  async getNormalizedPrice(priceFeedId: string): Promise<bigint> {
    return await this.contract.getNormalizedPrice(priceFeedId);
  }

  /**
   * Gets the last update timestamp for a price feed
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<bigint>} The last update timestamp in seconds
   */
  async getLastUpdate(priceFeedId: string): Promise<bigint> {
    return await this.contract.getLastUpdate(priceFeedId);
  }

  /**
   * Checks if volatility data is stale
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @param {bigint} stalenessThreshold - Maximum age in seconds
   * @returns {Promise<boolean>} True if data is older than threshold
   */
  async isVolatilityStale(priceFeedId: string, stalenessThreshold: bigint): Promise<boolean> {
    return await this.contract.isVolatilityStale(priceFeedId, stalenessThreshold);
  }

  /**
   * Gets all supported price feed IDs
   * @returns {Promise<string[]>} Array of supported price feed IDs (bytes32[] in Solidity, hex strings in JS)
   */
  async getSupportedFeeds(): Promise<string[]> {
    return await this.contract.getSupportedFeeds();
  }

  /**
   * Gets the number of supported feeds
   * @returns {Promise<bigint>} The number of supported feeds
   */
  async getSupportedFeedCount(): Promise<bigint> {
    return await this.contract.getSupportedFeedCount();
  }

  /**
   * Checks if a price feed is supported
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<boolean>} True if the feed is supported
   */
  async isSupported(priceFeedId: string): Promise<boolean> {
    return await this.contract.isSupported(priceFeedId);
  }

  /**
   * Gets the contract's HBAR balance
   * @returns {Promise<bigint>} The balance in tinybars
   */
  async getHBARBalance(): Promise<bigint> {
    return await this.contract.getHBARBalance();
  }

  // ============ WRITE FUNCTIONS ============

  /**
   * Updates volatility data for a specific price feed
   * @param {string[]} priceUpdate - The encoded price update data from Pyth Hermes (bytes[] in Solidity, hex strings in JS)
   * @param {string} priceFeedId - The price feed ID (bytes32 in Solidity, hex string in JS)
   * @param {bigint} volatilityBps - The calculated volatility in basis points
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (must be >= Pyth update fee, in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async updateVolatility(
    priceUpdate: string[], // bytes[] in Solidity, represented as hex strings
    priceFeedId: string, // bytes32 in Solidity, represented as hex string
    volatilityBps: bigint,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.updateVolatility(priceUpdate, priceFeedId, volatilityBps, options || {});
  }

  /**
   * Batch update volatility for multiple price feeds
   * @param {string[]} priceUpdate - The encoded price update data from Pyth Hermes (bytes[] in Solidity, hex strings in JS)
   * @param {string[]} priceFeedIds - Array of price feed IDs (bytes32[] in Solidity, hex strings in JS)
   * @param {bigint[]} volatilitiesBps - Array of calculated volatilities in basis points
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (must be >= Pyth update fee, in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async updateVolatilityBatch(
    priceUpdate: string[], // bytes[] in Solidity, represented as hex strings
    priceFeedIds: string[], // bytes32[] in Solidity, represented as hex strings
    volatilitiesBps: bigint[],
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.updateVolatilityBatch(priceUpdate, priceFeedIds, volatilitiesBps, options || {});
  }

  /**
   * Authorizes an address to update volatility (only owner)
   * @param {string} updater - The address to authorize
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async authorizeUpdater(
    updater: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.authorizeUpdater(updater, options || {});
  }

  /**
   * Revokes authorization for an address (only owner)
   * @param {string} updater - The address to revoke
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async revokeUpdater(
    updater: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.revokeUpdater(updater, options || {});
  }

  /**
   * Updates the maximum price staleness (only owner)
   * @param {bigint} newStaleness - New staleness threshold in seconds
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async setMaxPriceStaleness(
    newStaleness: bigint,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.setMaxPriceStaleness(newStaleness, options || {});
  }

  /**
   * Updates the Pyth contract address (only owner, emergency use)
   * @param {string} newPyth - The new Pyth contract address
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async updatePythContract(
    newPyth: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.updatePythContract(newPyth, options || {});
  }

  /**
   * Removes a price feed from supported feeds (only owner)
   * @param {string} priceFeedId - The price feed ID to remove (bytes32 in Solidity, hex string in JS)
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async removeFeed(
    priceFeedId: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.removeFeed(priceFeedId, options || {});
  }

  /**
   * Withdraws HBAR from the contract (only owner)
   * @param {string} to - Address to send HBAR to
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async withdrawHBAR(
    to: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.withdrawHBAR(to, options || {});
  }

  /**
   * Get the underlying contract instance for advanced usage
   * @returns {Contract} The ethers Contract instance
   */
  getContract(): Contract {
    return this.contract;
  }
}

/**
 * Main service factory
 * Creates service instances for all contracts using private key signing
 */
export class RevaultronServices {
  public userVault?: UserVaultService;
  public vaultFactory: VaultFactoryService;
  public volatilityIndex: VolatilityIndexService;

  /**
   * Creates a new RevaultronServices instance with private key signing
   * @param {ContractAddresses} addresses - Contract addresses
   * @param {Object} abis - Contract ABIs
   * @param {string} abis.userVault - UserVault contract ABI (optional)
   * @param {ContractABI} abis.vaultFactory - VaultFactory contract ABI
   * @param {ContractABI} abis.volatilityIndex - VolatilityIndex contract ABI
   * @param {string} providerUrl - RPC provider URL
   * @param {string} privateKey - Private key for signing transactions
   * @returns {RevaultronServices} Service instance with signing capability
   */
  constructor(
    addresses: ContractAddresses,
    abis: {
      userVault?: ContractABI;
      vaultFactory: ContractABI;
      volatilityIndex: ContractABI;
    },
    providerUrl: string,
    privateKey: string
  ) {
    const provider = new JsonRpcProvider(providerUrl);
    const signer = new Wallet(privateKey, provider);

    if (addresses.userVault && abis.userVault) {
      this.userVault = new UserVaultService(addresses.userVault, abis.userVault, signer);
    }

    this.vaultFactory = new VaultFactoryService(
      addresses.vaultFactory,
      abis.vaultFactory,
      signer
    );

    this.volatilityIndex = new VolatilityIndexService(
      addresses.volatilityIndex,
      abis.volatilityIndex,
      signer
    );
  }

  /**
   * Create a service instance with private key signing (primary method)
   * @param {ContractAddresses} addresses - Contract addresses
   * @param {Object} abis - Contract ABIs
   * @param {string} abis.userVault - UserVault contract ABI (optional)
   * @param {ContractABI} abis.vaultFactory - VaultFactory contract ABI
   * @param {ContractABI} abis.volatilityIndex - VolatilityIndex contract ABI
   * @param {string} providerUrl - RPC provider URL
   * @param {string} privateKey - Private key for signing transactions
   * @returns {RevaultronServices} Service instance with signing capability
   */
  static createWithPrivateKey(
    addresses: ContractAddresses,
    abis: {
      userVault?: ContractABI;
      vaultFactory: ContractABI;
      volatilityIndex: ContractABI;
    },
    providerUrl: string,
    privateKey: string
  ): RevaultronServices {
    return new RevaultronServices(addresses, abis, providerUrl, privateKey);
  }

  /**
   * Create a service instance with a provider (read-only, no signing)
   * Note: Write operations will fail without a real signer
   * @param {ContractAddresses} addresses - Contract addresses
   * @param {Object} abis - Contract ABIs
   * @param {string} abis.userVault - UserVault contract ABI (optional)
   * @param {ContractABI} abis.vaultFactory - VaultFactory contract ABI
   * @param {ContractABI} abis.volatilityIndex - VolatilityIndex contract ABI
   * @param {string} providerUrl - RPC provider URL
   * @returns {RevaultronServices} Service instance (read-only)
   */
  static createWithProvider(
    addresses: ContractAddresses,
    abis: {
      userVault?: ContractABI;
      vaultFactory: ContractABI;
      volatilityIndex: ContractABI;
    },
    providerUrl: string
  ): RevaultronServices {
    const provider = new JsonRpcProvider(providerUrl);
    
    // Create a dummy signer for read-only operations
    // Note: Write operations will fail without a real signer
    const dummySigner = new Wallet('0x0000000000000000000000000000000000000000000000000000000000000001', provider);

    // Create services object manually
    const services = {
      userVault: undefined as UserVaultService | undefined,
      vaultFactory: {} as VaultFactoryService,
      volatilityIndex: {} as VolatilityIndexService
    } as RevaultronServices;
    
    if (addresses.userVault && abis.userVault) {
      services.userVault = new UserVaultService(addresses.userVault, abis.userVault, dummySigner);
    }
    services.vaultFactory = new VaultFactoryService(addresses.vaultFactory, abis.vaultFactory, dummySigner);
    services.volatilityIndex = new VolatilityIndexService(addresses.volatilityIndex, abis.volatilityIndex, dummySigner);
    
    return services;
  }

  /**
   * Create a service instance with browser provider (for web3 wallets)
   * @param {ContractAddresses} addresses - Contract addresses
   * @param {Object} abis - Contract ABIs
   * @param {string} abis.userVault - UserVault contract ABI (optional)
   * @param {ContractABI} abis.vaultFactory - VaultFactory contract ABI
   * @param {ContractABI} abis.volatilityIndex - VolatilityIndex contract ABI
   * @param {any} ethereum - window.ethereum object (optional, will use window.ethereum if available)
   * @returns {Promise<RevaultronServices>} Service instance with browser wallet signing
   */
  static async createWithBrowserProvider(
    addresses: ContractAddresses,
    abis: {
      userVault?: ContractABI;
      vaultFactory: ContractABI;
      volatilityIndex: ContractABI;
    },
    ethereum?: any // window.ethereum object
  ): Promise<RevaultronServices> {
    if (typeof window === 'undefined' && !ethereum) {
      throw new Error('Browser provider not available');
    }

    const ethereumProvider = ethereum || (typeof window !== 'undefined' ? (window as any).ethereum : null);
    if (!ethereumProvider) {
      throw new Error('Ethereum provider not found');
    }

    const provider = new BrowserProvider(ethereumProvider);
    const signer = await provider.getSigner();

    // Create services with browser signer
    const services = {
      userVault: undefined as UserVaultService | undefined,
      vaultFactory: {} as VaultFactoryService,
      volatilityIndex: {} as VolatilityIndexService
    } as RevaultronServices;

    if (addresses.userVault && abis.userVault) {
      services.userVault = new UserVaultService(addresses.userVault, abis.userVault, signer);
    }

    services.vaultFactory = new VaultFactoryService(
      addresses.vaultFactory,
      abis.vaultFactory,
      signer
    );

    services.volatilityIndex = new VolatilityIndexService(
      addresses.volatilityIndex,
      abis.volatilityIndex,
      signer
    );

    return services;
  }
}

// Export all services
export default RevaultronServices;
