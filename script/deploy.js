const { ethers } = require("hardhat");
const axios = require("axios");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("\n========================================");
    console.log("🚀 DEPLOYING REVAULTRON SYSTEM");
    console.log("========================================");
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "HBAR\n");

    // Constants
    const PYTH_CONTRACT = "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729";
    const HBAR_PRICE_FEED_ID = "0x3728e591097635310e6341af53db8b7ee42da9b3a8d918f9463ce9cca886dfbd";
    
    // HEDERA UNIT CONVERSION:
    // 1 HBAR = 100,000,000 tinybars (10^8)
    // In EVM: tinybars × 10^10 = wei-bar
    // So: 10 HBAR = 1,000,000,000 tinybars = 10^10 wei-bar (10 gwei per tinybar)
    const HBAR_TO_DEPOSIT_TINYBARS = 10 * 100_000_000; // 10 HBAR in tinybars
    const HBAR_AMOUNT_TO_DEPOSIT = BigInt(HBAR_TO_DEPOSIT_TINYBARS) * BigInt(10 ** 10); // Convert to wei-bar
    
    const USDC_PRICE_PER_HBAR = 50_000; // 0.05 USDC per HBAR (6 decimals)
    const USDC_LIQUIDITY = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    console.log("HBAR to deposit: 10 HBAR =", HBAR_TO_DEPOSIT_TINYBARS, "tinybars");
    console.log("HBAR deposit amount (wei-bar):", HBAR_AMOUNT_TO_DEPOSIT.toString());

    // ========================================
    // 1. DEPLOY MOCK USDC
    // ========================================
    console.log("📦 1. Deploying Mock USDC...");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();
    console.log("   ✅ Mock USDC:", await usdc.getAddress());

    // ========================================
    // 2. DEPLOY MANUAL SWAPPER
    // ========================================
    console.log("\n📦 2. Deploying ManualSwapper...");
    const ManualSwapper = await ethers.getContractFactory("ManualSwapper");
    const swapper = await ManualSwapper.deploy(await usdc.getAddress(), USDC_PRICE_PER_HBAR);
    await swapper.waitForDeployment();
    console.log("   ✅ ManualSwapper:", await swapper.getAddress());
    console.log("   💰 Price: 1 HBAR =", USDC_PRICE_PER_HBAR / 1_000_000, "USDC");

    // ========================================
    // 3. FUND SWAPPER WITH USDC
    // ========================================
    console.log("\n💰 3. Funding Swapper with USDC...");
    await (await usdc.approve(await swapper.getAddress(), USDC_LIQUIDITY)).wait();
    await (await swapper.depositUSDC(USDC_LIQUIDITY)).wait();
    console.log("   ✅ Deposited:", ethers.formatUnits(USDC_LIQUIDITY, 6), "USDC");

    // ========================================
    // 4. DEPLOY VOLATILITY INDEX
    // ========================================
    console.log("\n📦 4. Deploying VolatilityIndex...");
    const VolatilityIndex = await ethers.getContractFactory("VolatilityIndex");
    const volatilityIndex = await VolatilityIndex.deploy(PYTH_CONTRACT);
    await volatilityIndex.waitForDeployment();
    console.log("   ✅ VolatilityIndex:", await volatilityIndex.getAddress());

    // ========================================
    // 5. DEPLOY REBALANCE EXECUTOR
    // ========================================
    console.log("\n📦 5. Deploying RebalanceExecutor...");
    const RebalanceExecutor = await ethers.getContractFactory("RebalanceExecutor");
    const rebalancer = await RebalanceExecutor.deploy(
        await volatilityIndex.getAddress(),
        await swapper.getAddress()
    );
    await rebalancer.waitForDeployment();
    console.log("   ✅ RebalanceExecutor:", await rebalancer.getAddress());
    console.log("   📊 Max Drift:", await rebalancer.maxDriftBps(), "bps (very low for testing)");

    // ========================================
    // 6. DEPLOY VAULT FACTORY
    // ========================================
    console.log("\n📦 6. Deploying VaultFactory...");
    const VaultFactory = await ethers.getContractFactory("VaultFactory");
    const vaultFactory = await VaultFactory.deploy(0, await usdc.getAddress()); // No creation fee, pass USDC address
    await vaultFactory.waitForDeployment();
    console.log("   ✅ VaultFactory:", await vaultFactory.getAddress());

    // ========================================
    // 7. CREATE USER VAULT
    // ========================================
    console.log("\n🏦 7. Creating User Vault...");
    const createVaultTx = await vaultFactory.createVault({ value: 0 });
    await createVaultTx.wait();
    const vaultAddress = await vaultFactory.getVault(deployer.address);
    console.log("   ✅ User Vault:", vaultAddress);

    const userVault = await ethers.getContractAt("UserVault", vaultAddress);

    // ========================================
    // 8. DEPOSIT HBAR TO VAULT
    // ========================================
    console.log("\n💵 8. Depositing HBAR to Vault...");
    console.log("   📤 Sending:", ethers.formatEther(HBAR_AMOUNT_TO_DEPOSIT), "HBAR");
    
    // Check deployer balance before
    const deployerBalanceBefore = await ethers.provider.getBalance(deployer.address);
    console.log("   💼 Deployer balance (raw):", deployerBalanceBefore.toString());
    
    const depositTx = await deployer.sendTransaction({
        to: vaultAddress,
        value: HBAR_AMOUNT_TO_DEPOSIT,
        gasLimit: 1000000
    });
    const depositReceipt = await depositTx.wait();
    console.log("   📋 TX Hash:", depositReceipt.hash);
    console.log("   ⛽ Gas used:", depositReceipt.gasUsed.toString());
    
    // Check vault contract balance directly from provider
    const vaultContractBalance = await ethers.provider.getBalance(vaultAddress);
    console.log("   🔍 Vault balance from provider (raw):", vaultContractBalance.toString());
    
    const vaultHBARBalance = await userVault.getHBARBalance();
    console.log("   ✅ Vault getHBARBalance() (raw):", vaultHBARBalance.toString());
    console.log("   📊 Formatted:", ethers.formatEther(vaultHBARBalance), "HBAR");

    // ========================================
    // 9. UPDATE VOLATILITY INDEX
    // ========================================
    console.log("\n📊 9. Updating Volatility Index...");
    try {
        // Fetch price data from Pyth
        const url = `https://hermes.pyth.network/v2/updates/price/latest?ids[]=${HBAR_PRICE_FEED_ID.slice(2)}&encoding=hex`;
        const { data } = await axios.get(url);
        
        if (!data?.parsed || data.parsed.length === 0) {
            console.log("   ⚠️  No price data available, skipping volatility update");
        } else {
            const priceUpdateBytes = [`0x${data.binary.data[0]}`];
            const pythContract = await ethers.getContractAt(
                ["function getUpdateFee(bytes[] calldata updateData) external view returns (uint)"],
                PYTH_CONTRACT
            );
            const pythFee = await pythContract.getUpdateFee(priceUpdateBytes);
            const fee = pythFee > ethers.parseUnits("10", "gwei") ? pythFee : ethers.parseUnits("10", "gwei");
            
            // ========================================
            // 🔍 WHERE VOLATILITY COMES FROM:
            // ========================================
            // CURRENT: We manually set it to 1 bps for testing (line 147)
            // FUTURE: Calculate from historical price data:
            //   1. Fetch prices from last N hours/days
            //   2. Calculate standard deviation
            //   3. volatilityBps = (stdDev / avgPrice) × 10000
            // 
            // For now, we're using a FIXED value for testing
            // ========================================
            const VOLATILITY_BPS = 1; // 1 bps = 0.01% (manually set for testing)
            
            const updateTx = await volatilityIndex.updateVolatility(
                priceUpdateBytes,
                HBAR_PRICE_FEED_ID,
                VOLATILITY_BPS,  // ← THIS is where volatility is set!
                { value: fee }
            );
            await updateTx.wait();
            
            const volatilityData = await volatilityIndex.getVolatilityData(HBAR_PRICE_FEED_ID);
            console.log("   ✅ Volatility:", volatilityData.volatilityBps.toString(), "bps (set on line 159)");
            console.log("   💲 HBAR Price:", volatilityData.price.toString(), "(raw, 8 decimals)");
            const hbarPriceUSD = Number(volatilityData.price) / 1e8;
            console.log("   💲 HBAR Price:", hbarPriceUSD.toFixed(8), "USD per HBAR");
            
            // Update ManualSwapper price to match Pyth price
            // Convert USD price to USDC units (6 decimals)
            // Example: $0.15 per HBAR → 0.15 * 10^6 = 150,000 USDC units
            const newSwapperPrice = Math.floor(hbarPriceUSD * 1e6);
            console.log("\n   🔄 Updating ManualSwapper price...");
            console.log("   💱 New price:", newSwapperPrice, "USDC units per HBAR");
            console.log("   💱 Equivalent:", (newSwapperPrice / 1e6).toFixed(6), "USDC per HBAR");
            await (await swapper.setPrice(newSwapperPrice)).wait();
            console.log("   ✅ ManualSwapper price updated to match Pyth price");
        }
    } catch (error) {
        console.log("   ⚠️  Error updating volatility:", error.message);
        console.log("   ℹ️  Continuing with deployment...");
    }

    // ========================================
    // 10. SKIP OWNERSHIP TRANSFER (vault methods are now public)
    // ========================================
    console.log("\n🔑 10. Vault Setup...");
    console.log("   ℹ️  Vault owner remains:", deployer.address);
    console.log("   ℹ️  RebalanceExecutor can withdraw HBAR and deposit USDC (public methods)");

    // ========================================
    // 11. CHECK IF REBALANCING IS NEEDED
    // ========================================
    console.log("\n🔍 11. Checking Rebalancing Status...");
    
    // For testing: we'll use address(0) as HBAR and USDC address
    const HBAR_ADDRESS = ethers.ZeroAddress;
    const USDC_ADDRESS = await usdc.getAddress();
    
    // ========================================
    // 📋 CONFIGURATION SUMMARY
    // ========================================
    console.log("\n   📋 REBALANCING CONFIGURATION:");
    console.log("   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    // Target allocation: When volatility is HIGH, move EVERYTHING to USDC (safe haven)
    // 0% HBAR, 100% USDC = flee to safety!
    const targetAllocationHBAR = 0;      // 0% HBAR (all out!)
    const targetAllocationUSDC = 10000;  // 100% USDC (all in stable!)
    const volatilityThreshold = 1; // Very low threshold (1 bps) for testing
    
    console.log("   🎯 Target Allocations (set in deploy.js lines 201-202):");
    console.log("      targetAllocationHBAR =", targetAllocationHBAR, "bps (", (targetAllocationHBAR/100).toFixed(0), "%)");
    console.log("      targetAllocationUSDC =", targetAllocationUSDC, "bps (", (targetAllocationUSDC/100).toFixed(0), "%)");
    console.log("      → Goal: 0% HBAR, 100% USDC (flee to stablecoin!)");
    
    console.log("\n   📊 Volatility Threshold (set in deploy.js line 203):");
    console.log("      volatilityThreshold =", volatilityThreshold, "bps (", (volatilityThreshold/100).toFixed(2), "%)");
    console.log("      → Min volatility needed to trigger rebalancing check");
    
    const maxDriftBps = await rebalancer.maxDriftBps();
    console.log("\n   🎚️  Max Drift Allowed (set in RebalanceExecutor.sol line 28):");
    console.log("      maxDriftBps =", maxDriftBps.toString(), "bps (", (Number(maxDriftBps)/100).toFixed(2), "%)");
    console.log("      → Max drift before rebalancing triggers");
    
    console.log("\n   🔧 Where These Are Used:");
    console.log("      1. needsRebalancing() gets called with these parameters");
    console.log("      2. Contract checks: (volatility >= threshold) AND (drift >= maxDriftBps)");
    console.log("      3. If BOTH true → executeRebalance() swaps to target allocation");
    console.log("   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    // Check if deployer is authorized
    const isAuth = await rebalancer.isAuthorizedAgent(deployer.address);
    console.log("   🔑 Deployer authorized:", isAuth);
    
    // Get current balances
    const hbarBalance = await userVault.getHBARBalance();
    const usdcBalance = await usdc.balanceOf(vaultAddress);
    console.log("\n   📊 Current Balances:");
    console.log("      HBAR:", ethers.formatEther(hbarBalance), "HBAR (wei-bar)");
    console.log("      HBAR:", (hbarBalance / BigInt(10**10)).toString(), "tinybars (8 decimals)");
    console.log("      USDC:", ethers.formatUnits(usdcBalance, 6), "USDC");
    console.log("      USDC:", usdcBalance.toString(), "units (6 decimals)");
    
    // Get Pyth price for USD calculations
    const volData = await volatilityIndex.getVolatilityData(HBAR_PRICE_FEED_ID);
    const pythPrice = Number(volData.price) / 1e8; // Convert to USD
    console.log("\n   💲 Pyth Price:", pythPrice.toFixed(8), "USD per HBAR");
    
    // Calculate USD values
    const hbarTinybars = hbarBalance / BigInt(10**10);
    const hbarValueUSD = (Number(hbarTinybars) / 1e8) * pythPrice; // tinybars to HBAR, then to USD
    const usdcValueUSD = Number(usdcBalance) / 1e6; // USDC units to USD
    const totalValueUSD = hbarValueUSD + usdcValueUSD;
    
    console.log("\n   💵 USD Values:");
    console.log("      HBAR:", hbarValueUSD.toFixed(6), "USD");
    console.log("      USDC:", usdcValueUSD.toFixed(6), "USD");
    console.log("      Total:", totalValueUSD.toFixed(6), "USD");
    
    // Calculate allocations based on USD value
    const currentAllocHBAR = totalValueUSD > 0 ? (hbarValueUSD / totalValueUSD) * 10000 : 0;
    const currentAllocUSDC = totalValueUSD > 0 ? (usdcValueUSD / totalValueUSD) * 10000 : 0;
    console.log("\n   📈 Current Allocations (USD-based):");
    console.log("      HBAR:", currentAllocHBAR.toFixed(2), "bps (", (currentAllocHBAR/100).toFixed(2), "%)");
    console.log("      USDC:", currentAllocUSDC.toFixed(2), "bps (", (currentAllocUSDC/100).toFixed(2), "%)");
    console.log("   🎯 Target Allocations (HIGH VOLATILITY = FLEE TO USDC!):");
    console.log("      HBAR:", targetAllocationHBAR, "bps (0% - GET OUT!)");
    console.log("      USDC:", targetAllocationUSDC, "bps (100% - SAFE HAVEN!)");
    console.log("   💡 Strategy: When volatility is high → Swap ALL to USDC for safety");
    
    // ========================================
    // DETAILED REBALANCING LOGIC EXPLANATION
    // ========================================
    console.log("\n   🔬 REBALANCING DECISION LOGIC:");
    console.log("   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    // Step 1: Get current volatility
    const currentVolatility = await volatilityIndex.getVolatility(HBAR_PRICE_FEED_ID);
    console.log("\n   📊 STEP 1: Check Volatility");
    console.log("      Current Volatility:", currentVolatility.toString(), "bps (", (Number(currentVolatility)/100).toFixed(2), "%)");
    console.log("      Volatility Threshold:", volatilityThreshold, "bps (", (volatilityThreshold/100).toFixed(2), "%)");
    console.log("      Volatility Check:", currentVolatility >= volatilityThreshold ? "✅ PASS (High enough)" : "❌ FAIL (Too low)");
    console.log("      Logic: if (volatility >= threshold) → continue to check drift");
    
    // Step 2: Calculate drift
    const driftHBAR = Math.abs(currentAllocHBAR - targetAllocationHBAR);
    const driftUSDC = Math.abs(currentAllocUSDC - targetAllocationUSDC);
    const maxDrift = Math.max(driftHBAR, driftUSDC);
    
    console.log("\n   📐 STEP 2: Calculate Drift");
    console.log("      HBAR Drift: |", currentAllocHBAR.toFixed(2), "-", targetAllocationHBAR, "| =", driftHBAR.toFixed(2), "bps (", (driftHBAR/100).toFixed(2), "%)");
    console.log("      USDC Drift: |", currentAllocUSDC.toFixed(2), "-", targetAllocationUSDC, "| =", driftUSDC.toFixed(2), "bps (", (driftUSDC/100).toFixed(2), "%)");
    console.log("      Maximum Drift:", maxDrift.toFixed(2), "bps (", (maxDrift/100).toFixed(2), "%)");
    console.log("      Formula: drift = |current_allocation - target_allocation|");
    
    // Step 3: Use maxDriftBps from earlier
    console.log("\n   🎚️  STEP 3: Check Drift Threshold");
    console.log("      Maximum Allowed Drift (maxDriftBps):", maxDriftBps.toString(), "bps (", (Number(maxDriftBps)/100).toFixed(2), "%)");
    console.log("      Current Drift:", maxDrift.toFixed(2), "bps (", (maxDrift/100).toFixed(2), "%)");
    console.log("      Drift Check:", maxDrift >= Number(maxDriftBps) ? "✅ PASS (Exceeds limit)" : "❌ FAIL (Within limit)");
    console.log("      Logic: if (drift >= maxDriftBps) → REBALANCE!");
    
    console.log("\n   🧮 STEP 4: Final Decision");
    const volatilityPass = currentVolatility >= volatilityThreshold;
    const driftPass = maxDrift >= Number(maxDriftBps);
    const shouldRebalance = volatilityPass && driftPass;
    console.log("      Volatility Check:", volatilityPass ? "✅ PASS" : "❌ FAIL");
    console.log("      Drift Check:", driftPass ? "✅ PASS" : "❌ FAIL");
    console.log("      Final Decision:", shouldRebalance ? "✅ REBALANCE NEEDED!" : "❌ No rebalancing needed");
    console.log("      Logic: needed = (volatility >= threshold) AND (drift >= maxDriftBps)");
    console.log("   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    try {
        const [needed, drift] = await rebalancer.needsRebalancing(
            vaultAddress,
            HBAR_ADDRESS,
            USDC_ADDRESS,
            targetAllocationHBAR,
            targetAllocationUSDC,
            volatilityThreshold,
            HBAR_PRICE_FEED_ID
        );
        console.log("\n   🤖 Contract Response:");
        console.log("      Rebalancing needed:", needed);
        console.log("      Reported drift:", drift.toString(), "bps (", (Number(drift)/100).toFixed(2), "%)");
    } catch (error) {
        console.log("   ⚠️  Error checking rebalancing:", error.message);
    }

    // ========================================
    // 12. EXECUTE REBALANCING
    // ========================================
    console.log("\n⚡ 12. Executing Rebalancing...");
    try {
        const rebalanceTx = await rebalancer.executeRebalance(
            vaultAddress,
            HBAR_ADDRESS,
            USDC_ADDRESS,
            targetAllocationHBAR,
            targetAllocationUSDC,
            volatilityThreshold,
            HBAR_PRICE_FEED_ID,
            { gasLimit: 5000000 } // Increase gas limit
        );
        const receipt = await rebalanceTx.wait();
        console.log("   ✅ Rebalance executed!");
        console.log("   🔗 TX Hash:", receipt.hash);
        console.log("   ⛽ Gas used:", receipt.gasUsed.toString());
        
        // Check final balances
        console.log("\n   💰 Final Balances:");
        const finalHBAR = await userVault.getHBARBalance();
        const finalUSDC = await usdc.balanceOf(vaultAddress);
        const finalHBARAmount = Number(finalHBAR / BigInt(10**10)) / 1e8;
        const finalUSDCAmount = Number(finalUSDC) / 1e6;
        console.log("      HBAR:", ethers.formatEther(finalHBAR), "HBAR");
        console.log("      USDC:", ethers.formatUnits(finalUSDC, 6), "USDC");
        
        // Calculate final USD values
        const finalVolData = await volatilityIndex.getVolatilityData(HBAR_PRICE_FEED_ID);
        const finalPythPrice = Number(finalVolData.price) / 1e8;
        const finalHBARValueUSD = finalHBARAmount * finalPythPrice;
        const finalUSDCValueUSD = finalUSDCAmount;
        const finalTotalUSD = finalHBARValueUSD + finalUSDCValueUSD;
        
        console.log("\n   💵 Final USD Values:");
        console.log("      HBAR:", finalHBARValueUSD.toFixed(6), "USD (", ((finalHBARValueUSD/finalTotalUSD)*100).toFixed(2), "% )");
        console.log("      USDC:", finalUSDCValueUSD.toFixed(6), "USD (", ((finalUSDCValueUSD/finalTotalUSD)*100).toFixed(2), "% )");
        console.log("      Total:", finalTotalUSD.toFixed(6), "USD");
        
        // ========================================
        // 13. WITHDRAW USDC TO USER (SAFE HAVEN!)
        // ========================================
        console.log("\n💸 13. Withdrawing USDC to User Account...");
        const usdcInVault = await usdc.balanceOf(vaultAddress);
        if (usdcInVault > 0) {
            console.log("   💰 USDC in vault:", ethers.formatUnits(usdcInVault, 6), "USDC");
            console.log("   📤 Withdrawing to:", deployer.address);
            
            const withdrawTx = await userVault.withdrawToken(
                USDC_ADDRESS,
                usdcInVault,
                deployer.address
            );
            await withdrawTx.wait();
            
            const userUSDCBalance = await usdc.balanceOf(deployer.address);
            console.log("   ✅ Withdrawn successfully!");
            console.log("   💼 User USDC balance:", ethers.formatUnits(userUSDCBalance, 6), "USDC");
            console.log("   🎉 Funds are SAFE in stablecoin!");
        } else {
            console.log("   ℹ️  No USDC in vault to withdraw");
        }
    } catch (error) {
        console.log("   ⚠️  Rebalancing failed:", error.message);
        console.log("   📋 Error details:");
        if (error.data) console.log("      Data:", error.data);
        if (error.reason) console.log("      Reason:", error.reason);
        
        // Try to decode the error
        try {
            const iface = rebalancer.interface;
            if (error.data) {
                const decodedError = iface.parseError(error.data);
                console.log("      Decoded:", decodedError);
            }
        } catch (e) {
            console.log("      Could not decode error");
        }
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log("\n========================================");
    console.log("✨ DEPLOYMENT COMPLETE");
    console.log("========================================");
    console.log("Mock USDC:          ", await usdc.getAddress());
    console.log("ManualSwapper:      ", await swapper.getAddress());
    console.log("VolatilityIndex:    ", await volatilityIndex.getAddress());
    console.log("RebalanceExecutor:  ", await rebalancer.getAddress());
    console.log("VaultFactory:       ", await vaultFactory.getAddress());
    console.log("User Vault:         ", vaultAddress);
    console.log("========================================\n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});