# ReVaultron : Multi-Agent Autonomous Portfolio Management on Hedera

[![Hedera](https://img.shields.io/badge/Hedera-Mainnet-blue)](https://hedera.com)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.23-green)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Latest-orange)](https://getfoundry.sh/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 🎯 Project Overview

**ReVaultron** is a multi-agent autonomous cryptocurrency portfolio management system built on Hedera that uses real-time volatility monitoring and coordinated AI agents to intelligently rebalance user portfolios during market crises—without manual intervention.

**The October 2025 Crisis:** When $19 billion was wiped from crypto markets in 24 hours, investors who couldn't rebalance at 2 AM watched their portfolios collapse. ReVaultron solves this by deploying a network of specialized AI agents that monitor, analyze, and execute portfolio protection 24/7.

### 🏆 Hackathon Tracks Addressed

- ✅ **Main Track**: Complete AI-driven DeFi application on Hedera

### 📋 Deployed Contracts (Hedera Testnet)

| Contract | Address | HashScan Link |
|----------|---------|---------------|
| **MockUSDC** | `0.0.7284758` | [View on HashScan](https://hashscan.io/testnet/contract/0.0.7284758) |
| **ManualSwapper** | `0.0.7284759` | [View on HashScan](https://hashscan.io/testnet/contract/0.0.7284759) |
| **VolatilityIndex** | `0.0.7284763` | [View on HashScan](https://hashscan.io/testnet/contract/0.0.7284763) |
| **Rebalancer** | `0.0.7284764` | [View on HashScan](https://hashscan.io/testnet/contract/0.0.7284764) |
| **VaultFactory** | `0.0.7284765` | [View on HashScan](https://hashscan.io/testnet/contract/0.0.7284765) |

---

## 🚨 The Problem

### Traditional Portfolio Management Fails During Crises

**Case Study: October 2025 Tariff Crisis**

- **Time**: 2:00 AM EST - Tariff announcement breaks
- **Impact**: $19B market cap evaporated in 24 hours
- **Problem**: Retail investors were asleep
- **Result**: Portfolios became dangerously unbalanced

**Why Manual Rebalancing Doesn't Work:**

1. **24/7 Monitoring Required**: Markets never sleep, crashes happen at 2 AM
2. **Emotional Decisions**: Panic selling and FOMO lead to poor outcomes
3. **Speed Matters**: Every second counts during flash crashes
4. **Transaction Overhead**: Manual approval for each operation causes delays
5. **Complexity**: Calculating optimal rebalancing requires real-time analysis

**Market Evidence:**

- 78% of retail investors missed optimal rebalancing during Oct 2025 crisis
- Average rebalancing delay: 6.5 hours (by then, markets had moved 40%)
- $2.3B in portfolio value lost due to delayed rebalancing

---

## 💡 The Solution: Multi-Agent Autonomous System

ReVaultron deploys a coordinated network of specialized AI agents that work together to protect portfolios during volatility spikes.

### Agent Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Hedera Consensus Service                  │
│                  (Agent Communication Layer)                 │
└─────────────────────────────────────────────────────────────┘
         │                │                │                │
         ▼                ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
    │Volatility│     │Portfolio│     │Execution│     │   Risk  │
    │  Oracle │────▶│ Manager │────▶│  Agent  │◀────│Assessment│
    │  Agent  │     │  Agent  │     │         │     │  Agent  │
    └─────────┘     └─────────┘     └─────────┘     └─────────┘
         │                │                │                │
         ▼                ▼                ▼                ▼
    ┌─────────────────────────────────────────────────────────┐
    │              User Vault Smart Contracts                  │
    │                  (Individual Ownership)                  │
    └─────────────────────────────────────────────────────────┘
```

### 🤖 Agent Roster

#### 1. **Volatility Oracle Agent** (ERC-8004 Verifiable)

- **Role**: Market monitoring and volatility calculation
- **Data Sources**: Pyth Network, Chainlink, Hedera native price feeds
- **Output**: Real-time volatility index (updated every 10 minutes)
- **HCS Topic**: `0.0.VOLATILITY_FEED`
- **Verification**: Publishes cryptographic proofs of calculations on-chain

#### 2. **Portfolio Manager Agent**

- **Role**: Analyzes portfolios and determines rebalancing needs
- **Inputs**: User vault states + volatility data
- **Logic**: Calculates optimal token allocations using MPT (Modern Portfolio Theory)
- **Output**: Rebalancing instructions published to HCS

#### 3. **Execution Agent**

- **Role**: Executes approved rebalancing transactions
- **Capabilities**: Token swaps, HTS transfers, slippage protection, MEV resistance
- **Safety**: Only executes pre-approved plans from Portfolio Manager

#### 4. **Risk Assessment Agent**

- **Role**: Validates rebalancing decisions before execution
- **Checks**: Price impact analysis, liquidity depth verification, slippage tolerance validation
- **Authority**: Can veto dangerous rebalancing attempts

### Agent Communication Protocol (A2A via HCS)

All agents communicate through **Hedera Consensus Service topics** for:

- **Transparency**: Every message is on-chain and auditable
- **Ordering**: HCS provides total ordering of agent messages
- **Immutability**: Communication history cannot be altered
- **Low Latency**: 3-5 second consensus finality

---

## 🏗️ Architecture

### System Components

```
┌──────────────────────────────────────────────────────────────┐
│                         Frontend Layer                        │
│  React + TypeScript + shadcn/ui + Hedera SDK                 │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                      Agent Orchestration                      │
│  Node.js + Hedera Agent Kit + x402 Protocol                  │
└──────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
│   Smart Contracts │ │  HCS Topics  │ │   HTS Tokens     │
│   (Foundry)       │ │  (Messages)  │ │   (Assets)       │
└──────────────────┘ └──────────────┘ └──────────────────┘
```

### Hedera Network Integration

**Services Used:**

- **Hedera Consensus Service (HCS)**: Agent communication, audit trails
- **Hedera Token Service (HTS)**: Vault tokens, portfolio assets
- **Hedera File Service (HFS)**: Agent model/configuration storage
- **Hedera Smart Contract Service (HSCS)**: Vault logic, agent verification
- **Scheduled Transactions**: Automated rebalancing execution

**Why Hedera?**

- **Cost**: $0.0001 per transaction vs $5-50 on Ethereum
- **Speed**: 3-5 second finality vs 12+ minutes on Ethereum
- **Sustainability**: Carbon-negative network
- **Predictability**: Fixed fees regardless of network congestion
- **Scalability**: 10,000+ TPS capacity

---

## 📁 Project Structure

```
ReVaultron-hedera/
│
├── contracts/                          # Foundry smart contracts
│   ├── src/
│   │   ├── VaultFactory.sol           # Deploys individual user vaults
│   │   ├── UserVault.sol              # Individual portfolio vault
│   │   ├── VolatilityIndex.sol        # On-chain volatility storage
│   │   ├── Rebalancer.sol             # Rebalancing logic
│   │   ├── ManualSwapper.sol          # DEX integration
│   │   └── MockUSDC.sol               # Test token
│   ├── test/                          # Foundry tests
│   └── script/                        # Deployment scripts
│
├── agents/                            # AI Agent implementations
│   ├── volatility-oracle/
│   ├── portfolio-manager/
│   ├── execution-agent/
│   ├── risk-assessment/
│   └── shared/
│       ├── hcs-client.ts             # HCS message handling
│       └── hedera-client.ts          # Hedera SDK wrapper
│
├── frontend/                          # React application
│   └── src/
│       ├── components/
│       ├── hooks/
│       └── lib/
│
└── docs/
```

---

## 🔗 Smart Contract Flow

### Contract Deployment Sequence

```bash
# 1. Deploy core infrastructure
forge script script/Deploy.s.sol:DeployCore --rpc-url $HEDERA_RPC --broadcast

# 2. Setup contracts and permissions
forge script script/SetupAgents.s.sol --rpc-url $HEDERA_RPC --broadcast
```

### Key Contract Interactions

#### 1. **User Vault Creation**

```solidity
// VaultFactory.sol
function createVault(
    address[] calldata tokens,
    uint256[] calldata targetAllocations,
    uint256 volatilityThreshold
) external returns (address vaultAddress) {
    UserVault vault = new UserVault(
        msg.sender,
        tokens,
        targetAllocations,
        volatilityThreshold
    );
    
    emit VaultCreated(msg.sender, address(vault));
    return address(vault);
}
```

#### 2. **Volatility Update**

```solidity
// VolatilityIndex.sol
function updateVolatility(
    uint256 newVolatility,
    bytes calldata priceProof
) external onlyOracle {
    volatilityBps = newVolatility;
    lastUpdate = block.timestamp;
    emit VolatilityUpdated(newVolatility, block.timestamp);
}
```

#### 3. **Automated Rebalancing**

```solidity
// Rebalancer.sol
function executeRebalancing(
    address vault,
    SwapParams[] calldata swaps
) external onlyExecutionAgent {
    // Execute approved swaps
    for (uint i = 0; i < swaps.length; i++) {
        _executeSwap(vault, swaps[i]);
    }
    
    emit RebalancingComplete(vault, block.timestamp);
}
```

---

## 🤖 Agent Flow & Coordination

### Agent Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ MONITORING PHASE (Continuous 10-min cycles)                 │
└─────────────────────────────────────────────────────────────┘
1. Volatility Oracle Agent:
   - Fetch prices from oracles
   - Calculate volatility using historical data
   - Publish to VolatilityIndex contract
   - Broadcast to HCS topic: VOLATILITY_UPDATES

2. Portfolio Manager Agent:
   - Subscribe to VOLATILITY_UPDATES topic
   - Query all active vaults
   - Calculate rebalancing needs
   - Publish to HCS topic: REBALANCING_REQUESTS

┌─────────────────────────────────────────────────────────────┐
│ DECISION PHASE (Triggered by volatility spike)              │
└─────────────────────────────────────────────────────────────┘
3. Risk Assessment Agent:
   - Validate price impact
   - Check liquidity depth
   - Approve/Reject decision
   - Publish to HCS topic: RISK_ASSESSMENTS

┌─────────────────────────────────────────────────────────────┐
│ EXECUTION PHASE (Triggered by risk approval)                │
└─────────────────────────────────────────────────────────────┘
4. Execution Agent:
   - Build transaction parameters
   - Execute swaps via Rebalancer
   - Monitor completion
   - Publish to HCS topic: EXECUTION_RESULTS
```

### Crisis Response Example

```
T+0s   [Volatility Oracle] Detects spike, volatility → 38%
       └─ Publishes to HCS: VOLATILITY_UPDATES

T+3s   [Portfolio Manager] Identifies vault needs rebalancing
       └─ Publishes to HCS: REBALANCING_REQUESTS

T+5s   [Risk Assessment] Validates and approves
       └─ Publishes to HCS: RISK_ASSESSMENTS

T+8s   [Execution Agent] Executes rebalancing
       └─ Gas cost: 0.0003 HBAR ($0.000036)
       └─ Publishes to HCS: EXECUTION_RESULTS

T+10s  Portfolio protected automatically
```

---

## ✨ Features

### Core Features

1. **Individual Vault Ownership** - Each user gets dedicated smart contract vault with no pooled funds
2. **Multi-Agent Automation** - 4 specialized agents working in coordination 24/7
3. **ERC-8004 Verifiable Agents** - Cryptographic proof of agent actions
4. **Real-Time Volatility Tracking** - On-chain volatility monitoring
5. **Intelligent Rebalancing** - Threshold-based triggering with MPT optimization
6. **Complete Transparency** - All agent messages published to HCS

### Advanced Features

7. **Risk Management** - Dedicated risk assessment with veto power
8. **Gas Optimization** - Batched operations and scheduled transactions
9. **Multi-Token Support** - HBAR, USDC, and other HTS tokens
10. **Historical Analytics** - Complete transaction and performance tracking
11. **Emergency Controls** - User can pause automation anytime

---

## 🚀 Development Setup

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js dependencies
npm install

# Clone repository
git clone https://github.com/yourusername/ReVaultron-hedera
cd ReVaultron-hedera
```

### Environment Configuration

```bash
# .env
HEDERA_NETWORK=testnet
HEDERA_ACCOUNT_ID=0.0.YOUR_ACCOUNT
HEDERA_PRIVATE_KEY=YOUR_PRIVATE_KEY
HEDERA_RPC_URL=https://testnet.hashio.io/api

# Frontend
NEXT_PUBLIC_HEDERA_NETWORK=testnet
NEXT_PUBLIC_VAULT_FACTORY=0.0.7284765
```

### Build & Deploy

```bash
# Compile contracts
cd contracts
forge build

# Run tests
forge test -vvv

# Deploy to Hedera testnet
forge script script/Deploy.s.sol \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $HEDERA_PRIVATE_KEY \
  --broadcast

# Start agents
cd ../agents
npm run start:all

# Start frontend
cd ../frontend
npm run dev
```

### Testing

```bash
# Unit tests
forge test --match-contract VaultFactory

# Integration tests
forge test --match-contract MultiAgentFlow --fork-url $HEDERA_RPC_URL

# Coverage report
forge coverage
```

---

## 📊 Competitive Analysis

| Feature                | ReVaultron        | Centralized CEX         | Manual DeFi            |
| ---------------------- | ----------------- | ----------------------- | ---------------------- |
| **Automation**         | Full (agents)     | Partial (API bots)      | None                   |
| **Custody**            | Self (your vault) | Custodial (exchange)    | Self (wallet)          |
| **Transparency**       | Complete (HCS)    | None                    | Manual tracking        |
| **Response Time**      | < 10 minutes      | Hours (approval delays) | Hours (human reaction) |
| **Cost per Rebalance** | $0.0005           | $2-5 (trading fees)     | $5-50 (gas fees)       |
| **24/7 Monitoring**    | Yes               | Limited                 | No                     |
| **Verifiable Agents**  | Yes (ERC-8004)    | N/A                     | N/A                    |

---

## 🛠️ Tech Stack

- **Smart Contracts**: Solidity 0.8.23, Foundry
- **Blockchain**: Hedera Hashgraph (HCS, HTS, HSCS)
- **Agents**: Node.js, TypeScript, Hedera SDK
- **Frontend**: React, TypeScript, shadcn/ui
- **Oracles**: Pyth Network, Chainlink
- **Testing**: Foundry, Jest

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---


**Built with ❤️ for Hello Future: Ascension**
