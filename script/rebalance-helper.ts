/**
 * RebalanceExecutor Helper - TypeScript Interface
 * 
 * This file provides a clean interface to interact with the RebalanceExecutor contract
 * from TypeScript/JavaScript using ethers.js
 * 
 * Prerequisites:
 * - npm install ethers @pythnetwork/pyth-evm-js
 * - Set PRIVATE_KEY in environment variables
 * - Set RPC_URL for Hedera testnet
 */

import { ethers } from 'ethers';
import { EvmPriceServiceConnection } from '@pythnetwork/pyth-evm-js';

// ============================================================================
// CONFIGURATION
// ============================================================================

/**
 * Network Configuration
 */
const CONFIG = {
  // Hedera Testnet JSON-RPC Relay
  rpcUrl: process.env.RPC_URL || 'https://testnet.hashio.io/api',
  
  // Your private key (DO NOT commit this to git!)
  privateKey: process.env.PRIVATE_KEY || '',
  
  // Pyth Network Configuration
  pythOracleAddress: '0xA2aa501b19aff244D90cc15a4Cf739D2725B5729', // Hedera Testnet
  pythHermes: 'https://hermes.pyth.network',
  
  // Pyth Price Feed IDs
  priceFeeds: {
    hbarUsd: '0x3728e591097635310e6341af53db8b7ee42da9b3a8d918f9463ce9cca886dfbd'
  },
  
  // Contract Addresses (Update after deployment)
  contracts: {
    volatilityIndex: '0x...', // VolatilityIndex contract
    rebalanceExecutor: '0x...', // RebalanceExecutor contract
    manualSwapper: '0x...', // ManualSwapper contract
    usdc: '0x...', // MockUSDC contract
    userVault: '0x...' // Your UserVault address
  },
  
  // Rebalancing Parameters
  rebalancing: {
    // Target allocations in basis points (10000 = 100%)
    targetAllocationHBAR: 0, // 0% HBAR
    targetAllocationUSDC: 10000, // 100% USDC
    
    // Minimum volatility to trigger rebalancing (in basis points)
    volatilityThreshold: 1, // 0.01%
    
    // Address(0) represents HBAR in the system
    HBAR_ADDRESS: ethers.ZeroAddress
  }
};

// ============================================================================
// CONTRACT ABIs
// ============================================================================

/**
 * RebalanceExecutor ABI - Essential functions only
 */
const REBALANCE_EXECUTOR_ABI = [
  // View Functions
  {
    "name": "needsRebalancing",
    "type": "function",
    "stateMutability": "view",
    "inputs": [
      { "name": "vault", "type": "address" },
      { "name": "token0", "type": "address" },
      { "name": "token1", "type": "address" },
      { "name": "targetAllocation0", "type": "uint256" },
      { "name": "targetAllocation1", "type": "uint256" },
      { "name": "volatilityThreshold", "type": "uint256" },
      { "name": "priceFeedId", "type": "bytes32" }
    ],
    "outputs": [
      { "name": "needed", "type": "bool" },
      { "name": "currentDrift", "type": "uint256" }
    ]
  },
  {
    "name": "getRebalanceHistory",
    "type": "function",
    "stateMutability": "view",
    "inputs": [
      { "name": "vault", "type": "address" }
    ],
    "outputs": [
      {
        "name": "records",
        "type": "tuple[]",
        "components": [
          { "name": "vault", "type": "address" },
          { "name": "tokenSold", "type": "address" },
          { "name": "tokenBought", "type": "address" },
          { "name": "amountSold", "type": "int64" },
          { "name": "amountBought", "type": "int64" },
          { "name": "volatility", "type": "uint256" },
          { "name": "timestamp", "type": "uint256" }
        ]
      }
    ]
  },
  {
    "name": "getRebalanceCount",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }]
  },
  {
    "name": "maxDriftBps",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }]
  },
  {
    "name": "isAuthorizedAgent",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{ "name": "agent", "type": "address" }],
    "outputs": [{ "name": "", "type": "bool" }]
  },
  
  // State-Changing Functions
  {
    "name": "executeRebalance",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [
      { "name": "vault", "type": "address" },
      { "name": "tokenToSell", "type": "address" },
      { "name": "tokenToBuy", "type": "address" },
      { "name": "targetAllocationSell", "type": "uint256" },
      { "name": "targetAllocationBuy", "type": "uint256" },
      { "name": "volatilityThreshold", "type": "uint256" },
      { "name": "priceFeedId", "type": "bytes32" }
    ],
    "outputs": []
  },
  {
    "name": "authorizeAgent",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{ "name": "agent", "type": "address" }],
    "outputs": []
  },
  {
    "name": "setMaxDrift",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{ "name": "newMaxDrift", "type": "uint256" }],
    "outputs": []
  },
  
  // Events
  {
    "name": "RebalanceExecuted",
    "type": "event",
    "anonymous": false,
    "inputs": [
      { "indexed": true, "name": "vault", "type": "address" },
      { "indexed": true, "name": "tokenSold", "type": "address" },
      { "indexed": true, "name": "tokenBought", "type": "address" },
      { "indexed": false, "name": "amountSold", "type": "int64" },
      { "indexed": false, "name": "amountBought", "type": "int64" },
      { "indexed": false, "name": "volatility", "type": "uint256" },
      { "indexed": false, "name": "timestamp", "type": "uint256" }
    ]
  }
];

/**
 * VolatilityIndex ABI - Essential functions only
 */
const VOLATILITY_INDEX_ABI = [
  {
    "name": "updateVolatility",
    "type": "function",
    "stateMutability": "payable",
    "inputs": [
      { "name": "priceUpdate", "type": "bytes[]" },
      { "name": "priceFeedId", "type": "bytes32" },
      { "name": "volatilityBps", "type": "uint256" }
    ],
    "outputs": []
  },
  {
    "name": "getVolatility",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{ "name": "priceFeedId", "type": "bytes32" }],
    "outputs": [{ "name": "", "type": "uint256" }]
  },
  {
    "name": "getVolatilityData",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{ "name": "priceFeedId", "type": "bytes32" }],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "components": [
          { "name": "price", "type": "int64" },
          { "name": "volatilityBps", "type": "uint256" },
          { "name": "lastUpdate", "type": "uint256" }
        ]
      }
    ]
  }
];

/**
 * ManualSwapper ABI
 */
const MANUAL_SWAPPER_ABI = [
  {
    "name": "setPrice",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{ "name": "newPrice", "type": "uint256" }],
    "outputs": []
  },
  {
    "name": "getAmountOut",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{ "name": "hbarAmount", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "uint256" }]
  },
  {
    "name": "currentPrice",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }]
  }
];

/**
 * UserVault ABI
 */
const USER_VAULT_ABI = [
  {
    "name": "getHBARBalance",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{ "name": "balance", "type": "uint256" }]
  },
  {
    "name": "getERC20Balance",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{ "name": "token", "type": "address" }],
    "outputs": [{ "name": "balance", "type": "uint256" }]
  }
];

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Initialize provider and wallet
 */
function initializeProvider() {
  const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  const wallet = new ethers.Wallet(CONFIG.privateKey, provider);
  return { provider, wallet };
}

/**
 * Get contract instances
 */
function getContracts(wallet: ethers.Wallet) {
  return {
    rebalanceExecutor: new ethers.Contract(
      CONFIG.contracts.rebalanceExecutor,
      REBALANCE_EXECUTOR_ABI,
      wallet
    ),
    volatilityIndex: new ethers.Contract(
      CONFIG.contracts.volatilityIndex,
      VOLATILITY_INDEX_ABI,
      wallet
    ),
    manualSwapper: new ethers.Contract(
      CONFIG.contracts.manualSwapper,
      MANUAL_SWAPPER_ABI,
      wallet
    ),
    userVault: new ethers.Contract(
      CONFIG.contracts.userVault,
      USER_VAULT_ABI,
      wallet
    )
  };
}

/**
 * Fetch Pyth price update data
 * 
 * @param priceFeedId - Pyth price feed ID (e.g., HBAR/USD)
 * @returns Price update data (bytes[]) and update fee
 */
async function fetchPythPriceUpdate(priceFeedId: string) {
  const connection = new EvmPriceServiceConnection(CONFIG.pythHermes);
  
  // Get latest price update
  const priceUpdate = await connection.getPriceFeedsUpdateData([priceFeedId]);
  
  console.log('📡 Fetched Pyth price update');
  console.log(`   Feed ID: ${priceFeedId}`);
  console.log(`   Update data: ${priceUpdate.length} bytes`);
  
  return {
    priceUpdate,
    updateFee: ethers.parseEther('0.01') // Small fee for Pyth update
  };
}

/**
 * Format basis points to percentage
 */
function bpsToPercent(bps: bigint): string {
  return `${(Number(bps) / 100).toFixed(2)}%`;
}

/**
 * Format tinybars to HBAR
 */
function tinybarsToHBAR(tinybars: bigint): string {
  return ethers.formatUnits(tinybars, 8);
}

/**
 * Format USDC units to readable amount
 */
function formatUSDC(units: bigint): string {
  return ethers.formatUnits(units, 6);
}

// ============================================================================
// MAIN FUNCTIONS
// ============================================================================

/**
 * 1. Update Volatility
 * 
 * Sets the current market volatility for rebalancing decisions
 * 
 * @param volatilityBps - Volatility in basis points (e.g., 150 = 1.5%)
 * @param priceFeedId - Pyth price feed ID (default: HBAR/USD)
 * 
 * Example:
 *   await updateVolatility(150); // Set volatility to 1.5%
 */
async function updateVolatility(
  volatilityBps: number,
  priceFeedId: string = CONFIG.priceFeeds.hbarUsd
) {
  console.log('\n🔄 Updating Volatility...');
  console.log(`   Volatility: ${bpsToPercent(BigInt(volatilityBps))}`);
  
  const { wallet } = initializeProvider();
  const { volatilityIndex } = getContracts(wallet);
  
  // Fetch Pyth price update
  const { priceUpdate, updateFee } = await fetchPythPriceUpdate(priceFeedId);
  
  // Call updateVolatility
  const tx = await volatilityIndex.updateVolatility(
    priceUpdate,
    priceFeedId,
    volatilityBps,
    { value: updateFee }
  );
  
  console.log(`   Transaction: ${tx.hash}`);
  await tx.wait();
  
  console.log('✅ Volatility updated successfully');
  
  // Fetch and display updated data
  const volData = await volatilityIndex.getVolatilityData(priceFeedId);
  console.log(`   Current Price: $${ethers.formatUnits(volData.price, 8)}`);
  console.log(`   Volatility: ${bpsToPercent(volData.volatilityBps)}`);
}

/**
 * 2. Check if Rebalancing is Needed
 * 
 * View function to check if portfolio requires rebalancing
 * 
 * @param vaultAddress - UserVault contract address
 * @param priceFeedId - Pyth price feed ID (default: HBAR/USD)
 * @returns Object with rebalancing status and drift
 * 
 * Example:
 *   const { needed, drift } = await checkRebalancingNeed('0x...');
 *   if (needed) {
 *     console.log(`Rebalancing needed! Drift: ${drift} bps`);
 *   }
 */
async function checkRebalancingNeed(
  vaultAddress: string = CONFIG.contracts.userVault,
  priceFeedId: string = CONFIG.priceFeeds.hbarUsd
) {
  console.log('\n🔍 Checking Rebalancing Need...');
  
  const { wallet } = initializeProvider();
  const { rebalanceExecutor, userVault } = getContracts(wallet);
  
  // Get vault balances
  const hbarBalance = await userVault.getHBARBalance();
  const usdcBalance = await userVault.getERC20Balance(CONFIG.contracts.usdc);
  
  console.log('\n📊 Current Portfolio:');
  console.log(`   HBAR: ${ethers.formatEther(hbarBalance)} HBAR (wei-bar)`);
  console.log(`   USDC: ${formatUSDC(usdcBalance)} USDC`);
  
  // Call needsRebalancing
  const [needed, currentDrift] = await rebalanceExecutor.needsRebalancing(
    vaultAddress,
    CONFIG.rebalancing.HBAR_ADDRESS, // token0 = HBAR
    CONFIG.contracts.usdc, // token1 = USDC
    CONFIG.rebalancing.targetAllocationHBAR, // 0%
    CONFIG.rebalancing.targetAllocationUSDC, // 100%
    CONFIG.rebalancing.volatilityThreshold, // 1 bps
    priceFeedId
  );
  
  console.log('\n📈 Rebalancing Analysis:');
  console.log(`   Target: ${bpsToPercent(BigInt(CONFIG.rebalancing.targetAllocationHBAR))} HBAR, ${bpsToPercent(BigInt(CONFIG.rebalancing.targetAllocationUSDC))} USDC`);
  console.log(`   Current Drift: ${bpsToPercent(currentDrift)}`);
  console.log(`   Max Allowed Drift: ${bpsToPercent(await rebalanceExecutor.maxDriftBps())}`);
  console.log(`   Rebalancing Needed: ${needed ? '✅ YES' : '❌ NO'}`);
  
  return { needed, drift: currentDrift };
}

/**
 * 3. Execute Rebalancing
 * 
 * Executes portfolio rebalancing to reach target allocation
 * 
 * @param vaultAddress - UserVault contract address
 * @param priceFeedId - Pyth price feed ID (default: HBAR/USD)
 * 
 * Example:
 *   await executeRebalancing('0x...');
 * 
 * Prerequisites:
 * - Caller must be authorized agent (call authorizeAgent first)
 * - Volatility must be >= threshold
 * - Drift must be >= maxDriftBps
 */
async function executeRebalancing(
  vaultAddress: string = CONFIG.contracts.userVault,
  priceFeedId: string = CONFIG.priceFeeds.hbarUsd
) {
  console.log('\n⚡ Executing Rebalancing...');
  
  const { wallet } = initializeProvider();
  const { rebalanceExecutor } = getContracts(wallet);
  
  // Check authorization
  const isAuthorized = await rebalanceExecutor.isAuthorizedAgent(wallet.address);
  if (!isAuthorized) {
    console.error('❌ Error: Caller is not authorized agent');
    console.log('   Call authorizeAgent() first');
    return;
  }
  
  console.log('   Authorized: ✅');
  console.log(`   Vault: ${vaultAddress}`);
  console.log(`   Selling: HBAR (${CONFIG.rebalancing.HBAR_ADDRESS})`);
  console.log(`   Buying: USDC (${CONFIG.contracts.usdc})`);
  console.log(`   Target: ${bpsToPercent(BigInt(CONFIG.rebalancing.targetAllocationHBAR))} HBAR, ${bpsToPercent(BigInt(CONFIG.rebalancing.targetAllocationUSDC))} USDC`);
  
  // Execute rebalancing
  const tx = await rebalanceExecutor.executeRebalance(
    vaultAddress,
    CONFIG.rebalancing.HBAR_ADDRESS, // tokenToSell = HBAR
    CONFIG.contracts.usdc, // tokenToBuy = USDC
    CONFIG.rebalancing.targetAllocationHBAR, // 0%
    CONFIG.rebalancing.targetAllocationUSDC, // 100%
    CONFIG.rebalancing.volatilityThreshold, // 1 bps
    priceFeedId
  );
  
  console.log(`   Transaction: ${tx.hash}`);
  const receipt = await tx.wait();
  
  console.log('✅ Rebalancing executed successfully');
  console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
  
  // Parse events
  for (const log of receipt.logs) {
    try {
      const event = rebalanceExecutor.interface.parseLog(log);
      if (event && event.name === 'RebalanceExecuted') {
        console.log('\n📋 Rebalancing Details:');
        console.log(`   HBAR Sold: ${tinybarsToHBAR(event.args.amountSold)} HBAR`);
        console.log(`   USDC Bought: ${formatUSDC(event.args.amountBought)} USDC`);
        console.log(`   Volatility: ${bpsToPercent(event.args.volatility)}`);
      }
    } catch (e) {
      // Ignore parsing errors for non-RebalanceExecutor events
    }
  }
}

/**
 * 4. Get Rebalancing History
 * 
 * Retrieves historical rebalancing records for a vault
 * 
 * @param vaultAddress - UserVault contract address
 * 
 * Example:
 *   const history = await getRebalancingHistory('0x...');
 *   console.log(`Total rebalances: ${history.length}`);
 */
async function getRebalancingHistory(
  vaultAddress: string = CONFIG.contracts.userVault
) {
  console.log('\n📜 Fetching Rebalancing History...');
  
  const { wallet } = initializeProvider();
  const { rebalanceExecutor } = getContracts(wallet);
  
  const records = await rebalanceExecutor.getRebalanceHistory(vaultAddress);
  
  console.log(`   Total Records: ${records.length}`);
  
  if (records.length === 0) {
    console.log('   No rebalancing history found');
    return [];
  }
  
  console.log('\n📊 Rebalancing Records:');
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    const date = new Date(Number(record.timestamp) * 1000);
    
    console.log(`\n   Record ${i + 1}:`);
    console.log(`   Date: ${date.toLocaleString()}`);
    console.log(`   Sold: ${tinybarsToHBAR(record.amountSold)} HBAR`);
    console.log(`   Bought: ${formatUSDC(record.amountBought)} USDC`);
    console.log(`   Volatility: ${bpsToPercent(record.volatility)}`);
  }
  
  return records;
}

/**
 * 5. Authorize Agent
 * 
 * Authorizes an address to execute rebalancing
 * 
 * @param agentAddress - Address to authorize
 * 
 * Example:
 *   await authorizeAgent('0x...'); // Your wallet address
 */
async function authorizeAgent(agentAddress: string) {
  console.log('\n🔐 Authorizing Agent...');
  console.log(`   Agent: ${agentAddress}`);
  
  const { wallet } = initializeProvider();
  const { rebalanceExecutor } = getContracts(wallet);
  
  const tx = await rebalanceExecutor.authorizeAgent(agentAddress);
  console.log(`   Transaction: ${tx.hash}`);
  await tx.wait();
  
  console.log('✅ Agent authorized successfully');
}

/**
 * 6. Set Max Drift
 * 
 * Updates the maximum allowed drift before rebalancing
 * 
 * @param maxDriftBps - Maximum drift in basis points (e.g., 100 = 1%)
 * 
 * Example:
 *   await setMaxDrift(500); // Set max drift to 5%
 */
async function setMaxDrift(maxDriftBps: number) {
  console.log('\n⚙️ Setting Max Drift...');
  console.log(`   New Max Drift: ${bpsToPercent(BigInt(maxDriftBps))}`);
  
  const { wallet } = initializeProvider();
  const { rebalanceExecutor } = getContracts(wallet);
  
  const tx = await rebalanceExecutor.setMaxDrift(maxDriftBps);
  console.log(`   Transaction: ${tx.hash}`);
  await tx.wait();
  
  console.log('✅ Max drift updated successfully');
}

/**
 * 7. Update ManualSwapper Price
 * 
 * Updates the swap price to match current oracle price
 * 
 * @param priceFeedId - Pyth price feed ID (default: HBAR/USD)
 * 
 * Example:
 *   await updateSwapperPrice(); // Sync with Pyth oracle
 */
async function updateSwapperPrice(
  priceFeedId: string = CONFIG.priceFeeds.hbarUsd
) {
  console.log('\n💱 Updating Swapper Price...');
  
  const { wallet } = initializeProvider();
  const { volatilityIndex, manualSwapper } = getContracts(wallet);
  
  // Get current price from oracle
  const volData = await volatilityIndex.getVolatilityData(priceFeedId);
  const oraclePrice = volData.price;
  
  console.log(`   Oracle Price: $${ethers.formatUnits(oraclePrice, 8)}`);
  
  // Update swapper price
  const tx = await manualSwapper.setPrice(oraclePrice);
  console.log(`   Transaction: ${tx.hash}`);
  await tx.wait();
  
  console.log('✅ Swapper price updated successfully');
}

// ============================================================================
// COMPLETE WORKFLOW
// ============================================================================

/**
 * Complete Rebalancing Workflow
 * 
 * Executes the full rebalancing process:
 * 1. Update volatility from Pyth
 * 2. Update swapper price
 * 3. Check if rebalancing needed
 * 4. Execute rebalancing if needed
 * 5. Show history
 * 
 * @param volatilityBps - Current market volatility (e.g., 150 = 1.5%)
 * 
 * Example:
 *   await completeRebalancingWorkflow(150); // High volatility scenario
 */
async function completeRebalancingWorkflow(volatilityBps: number) {
  console.log('\n🚀 Starting Complete Rebalancing Workflow');
  console.log('='.repeat(60));
  
  try {
    // Step 1: Update volatility
    await updateVolatility(volatilityBps);
    
    // Step 2: Update swapper price
    await updateSwapperPrice();
    
    // Step 3: Check if rebalancing needed
    const { needed } = await checkRebalancingNeed();
    
    if (!needed) {
      console.log('\n✅ Rebalancing not needed - portfolio within target');
      return;
    }
    
    // Step 4: Execute rebalancing
    await executeRebalancing();
    
    // Step 5: Show history
    await getRebalancingHistory();
    
    console.log('\n✅ Workflow completed successfully');
    console.log('='.repeat(60));
    
  } catch (error: any) {
    console.error('\n❌ Error during workflow:');
    console.error(error.message);
    
    if (error.message.includes('RebalanceNotNeeded')) {
      console.log('\n💡 Hint: Volatility too low or drift within threshold');
    } else if (error.message.includes('Unauthorized')) {
      console.log('\n💡 Hint: Call authorizeAgent() first');
    }
  }
}

// ============================================================================
// EXPORTS
// ============================================================================

export {
  // Configuration
  CONFIG,
  
  // Core Functions
  updateVolatility,
  checkRebalancingNeed,
  executeRebalancing,
  getRebalancingHistory,
  
  // Management Functions
  authorizeAgent,
  setMaxDrift,
  updateSwapperPrice,
  
  // Workflows
  completeRebalancingWorkflow,
  
  // Utilities
  initializeProvider,
  getContracts,
  fetchPythPriceUpdate,
  bpsToPercent,
  tinybarsToHBAR,
  formatUSDC
};

// ============================================================================
// USAGE EXAMPLES
// ============================================================================

/*
// Example 1: Simple check
import { checkRebalancingNeed } from './rebalance-helper';
const { needed, drift } = await checkRebalancingNeed();

// Example 2: Manual execution
import { updateVolatility, executeRebalancing } from './rebalance-helper';
await updateVolatility(150); // Set 1.5% volatility
await executeRebalancing();

// Example 3: Complete workflow
import { completeRebalancingWorkflow } from './rebalance-helper';
await completeRebalancingWorkflow(150); // High volatility

// Example 4: Authorization setup
import { authorizeAgent } from './rebalance-helper';
await authorizeAgent('0xYourAgentAddress');

// Example 5: View history
import { getRebalancingHistory } from './rebalance-helper';
const history = await getRebalancingHistory();
console.log(`Total rebalances: ${history.length}`);
*/
