import {
  Contract,
  Signer,
  type Abi,
  type ContractTransactionResponse
} from 'ethers';

/**
 * RebalanceExecutor Service
 * Handles all interactions with the RebalanceExecutor contract
 * Executes portfolio rebalancing for ReVaultron vaults
 */

// Type definition for RebalanceRecord struct
export interface RebalanceRecord {
  vault: string;
  tokenSold: string;
  tokenBought: string;
  amountSold: bigint; // int64 in Solidity, bigint in JS
  amountBought: bigint; // int64 in Solidity, bigint in JS
  volatility: bigint;
  timestamp: bigint;
}

export class RebalanceExecutorService {
  private contract: Contract;
  private signer: Signer;

  constructor(
    address: string,
    abi: Abi,
    signer: Signer
  ) {
    this.contract = new Contract(address, abi, signer);
    this.signer = signer;
  }

  // ============ VIEW FUNCTIONS ============

  /**
   * Gets the VolatilityIndex contract address
   * @returns {Promise<string>} The VolatilityIndex contract address
   */
  async volatilityIndex(): Promise<string> {
    return await this.contract.volatilityIndex();
  }

  /**
   * Gets the SaucerSwapper contract address
   * @returns {Promise<string>} The SaucerSwapper contract address
   */
  async swapper(): Promise<string> {
    return await this.contract.swapper();
  }

  /**
   * Gets the maximum drift threshold in basis points
   * @returns {Promise<bigint>} Maximum drift in basis points (default: 500 = 5%)
   */
  async maxDriftBps(): Promise<bigint> {
    return await this.contract.maxDriftBps();
  }

  /**
   * Gets the BASIS_POINTS constant
   * @returns {Promise<bigint>} Basis points constant (10000)
   */
  async BASIS_POINTS(): Promise<bigint> {
    return await this.contract.BASIS_POINTS();
  }

  /**
   * Checks if an address is an authorized agent
   * @param {string} agent - The address to check
   * @returns {Promise<boolean>} True if the address is authorized
   */
  async isAuthorizedAgent(agent: string): Promise<boolean> {
    return await this.contract.isAuthorizedAgent(agent);
  }

  /**
   * Gets a rebalance record by index
   * @param {bigint} index - The index in the rebalanceHistory array
   * @returns {Promise<RebalanceRecord>} The rebalance record
   */
  async rebalanceHistory(index: bigint): Promise<RebalanceRecord> {
    return await this.contract.rebalanceHistory(index);
  }

  /**
   * Checks if a vault needs rebalancing
   * @param {string} vault - The vault address
   * @param {string} token0 - First token address
   * @param {string} token1 - Second token address
   * @param {bigint} targetAllocation0 - Target allocation for token0 (in basis points)
   * @param {bigint} targetAllocation1 - Target allocation for token1 (in basis points)
   * @param {bigint} volatilityThreshold - Minimum volatility to trigger rebalance (in bps)
   * @param {string} priceFeedId - Pyth price feed ID (bytes32 in Solidity, hex string in JS)
   * @returns {Promise<[boolean, bigint]>} Tuple containing [needed, currentDrift]
   */
  async needsRebalancing(
    vault: string,
    token0: string,
    token1: string,
    targetAllocation0: bigint,
    targetAllocation1: bigint,
    volatilityThreshold: bigint,
    priceFeedId: string
  ): Promise<[boolean, bigint]> {
    return await this.contract.needsRebalancing(
      vault,
      token0,
      token1,
      targetAllocation0,
      targetAllocation1,
      volatilityThreshold,
      priceFeedId
    );
  }

  /**
   * Gets rebalancing history for a specific vault
   * @param {string} vault - The vault address
   * @returns {Promise<RebalanceRecord[]>} Array of rebalance records for the vault
   */
  async getRebalanceHistory(vault: string): Promise<RebalanceRecord[]> {
    return await this.contract.getRebalanceHistory(vault);
  }

  /**
   * Gets the total number of rebalance operations
   * @returns {Promise<bigint>} The total rebalance count
   */
  async getRebalanceCount(): Promise<bigint> {
    return await this.contract.getRebalanceCount();
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
   * Executes rebalancing for a vault
   * @param {string} vault - UserVault address
   * @param {string} tokenToSell - Token to sell
   * @param {string} tokenToBuy - Token to buy
   * @param {bigint} targetAllocationSell - Target allocation for tokenToSell (in basis points)
   * @param {bigint} targetAllocationBuy - Target allocation for tokenToBuy (in basis points)
   * @param {bigint} volatilityThreshold - Minimum volatility to trigger rebalance (in bps)
   * @param {string} priceFeedId - Pyth price feed ID (bytes32 in Solidity, hex string in JS)
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async executeRebalance(
    vault: string,
    tokenToSell: string,
    tokenToBuy: string,
    targetAllocationSell: bigint,
    targetAllocationBuy: bigint,
    volatilityThreshold: bigint,
    priceFeedId: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.executeRebalance(
      vault,
      tokenToSell,
      tokenToBuy,
      targetAllocationSell,
      targetAllocationBuy,
      volatilityThreshold,
      priceFeedId,
      options || {}
    );
  }

  /**
   * Authorizes an agent to trigger rebalancing (only owner)
   * @param {string} agent - The agent address to authorize
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async authorizeAgent(
    agent: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.authorizeAgent(agent, options || {});
  }

  /**
   * Revokes agent authorization (only owner)
   * @param {string} agent - The agent address to revoke
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async revokeAgent(
    agent: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.revokeAgent(agent, options || {});
  }

  /**
   * Updates the maximum drift threshold (only owner)
   * @param {bigint} newMaxDrift - New max drift in basis points (max: 2000 = 20%)
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async setMaxDrift(
    newMaxDrift: bigint,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.setMaxDrift(newMaxDrift, options || {});
  }

  /**
   * Updates the VolatilityIndex contract address (only owner)
   * @param {string} newVolatilityIndex - The new VolatilityIndex contract address
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async updateVolatilityIndex(
    newVolatilityIndex: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.updateVolatilityIndex(newVolatilityIndex, options || {});
  }

  /**
   * Updates the SaucerSwapper contract address (only owner)
   * @param {string} newSwapper - The new SaucerSwapper contract address
   * @param {Object} options - Optional transaction parameters
   * @param {bigint} options.gasLimit - Gas limit for the transaction
   * @param {bigint} options.value - Value to send with transaction (in tinybars)
   * @returns {Promise<ContractTransactionResponse>} Transaction response object
   */
  async updateSwapper(
    newSwapper: string,
    options?: { gasLimit?: bigint; value?: bigint }
  ): Promise<ContractTransactionResponse> {
    return await this.contract.updateSwapper(newSwapper, options || {});
  }

  /**
   * Get the underlying contract instance for advanced usage
   * @returns {Contract} The ethers Contract instance
   */
  getContract(): Contract {
    return this.contract;
  }
}

