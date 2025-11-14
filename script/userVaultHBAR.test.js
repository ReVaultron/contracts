const { expect } = require("chai");
const { ethers } = require("hardhat");
require("dotenv").config();

// Deployment info
const VAULT_FACTORY_ADDRESS = "0x443cf9983ace1b17378A9F7e7428D40abB7302e7";

describe("Vault HBAR Operations (On-Chain)", function () {
  let vaultFactory;
  let userVault;
  let user;
  let userVaultAddress;

  before(async function () {
    // Get user from private key in .env
    user = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    console.log("\nTesting with user address:", user.address);

    // Get user HBAR balance
    const userBalance = await ethers.provider.getBalance(user.address);
    // On Hedera: 1 HBAR = 10^8 tinybars (not 10^18 wei like Ethereum)
    console.log("User HBAR balance:", ethers.formatUnits(userBalance, 8), "HBAR\n");

    // Connect to deployed VaultFactory
    vaultFactory = await ethers.getContractAt("VaultFactory", VAULT_FACTORY_ADDRESS);
    console.log("Connected to VaultFactory at:", VAULT_FACTORY_ADDRESS);

    // Check if user already has a vault, if not create one
    const hasVault = await vaultFactory.hasVault(user.address);

    if (!hasVault) {
      console.log("Creating vault for user...");
      const tx = await vaultFactory.connect(user).createVault();
      await tx.wait();
      console.log("✓ Vault created successfully\n");
    } else {
      console.log("✓ Vault already exists\n");
    }

    // Get user's vault address
    userVaultAddress = await vaultFactory.userVaults(user.address);
    console.log("User vault address:", userVaultAddress);

    // Connect to UserVault contract
    userVault = await ethers.getContractAt("UserVault", userVaultAddress);

    // Display initial vault balance
    const initialBalance = await userVault.getHBARBalance();
    // Note: On Hedera, balance is in tinybars (1 HBAR = 10^8 tinybars)
    console.log("Initial vault HBAR balance:", ethers.formatUnits(initialBalance, 8), "HBAR\n");
  });

  describe("HBAR Deposit", function () {
    it("Should deposit 1 HBAR to vault", async function () {
      const balanceBefore = await userVault.getHBARBalance();
      console.log("→ Vault balance before deposit:", ethers.formatUnits(balanceBefore, 8), "HBAR");

      // 1 HBAR = 10^8 tinybars (Hedera uses 8 decimals, not 18 like Ethereum)
      const depositAmount = ethers.parseUnits("1", 8);
      console.log("→ Depositing:", ethers.formatUnits(depositAmount, 8), "HBAR");

      const tx = await user.sendTransaction({
        to: userVaultAddress,
        value: depositAmount
      });
      await tx.wait();

      const balanceAfter = await userVault.getHBARBalance();
      console.log("→ Vault balance after deposit:", ethers.formatUnits(balanceAfter, 8), "HBAR");
      console.log("✓ Transaction hash:", tx.hash, "\n");

      expect(balanceAfter).to.equal(balanceBefore + depositAmount);
    });

    it("Should deposit 0.5 HBAR to vault", async function () {
      const balanceBefore = await userVault.getHBARBalance();
      console.log("→ Vault balance before deposit:", ethers.formatUnits(balanceBefore, 8), "HBAR");

      const depositAmount = ethers.parseUnits("0.5", 8);
      console.log("→ Depositing:", ethers.formatUnits(depositAmount, 8), "HBAR");

      const tx = await user.sendTransaction({
        to: userVaultAddress,
        value: depositAmount
      });
      await tx.wait();

      const balanceAfter = await userVault.getHBARBalance();
      console.log("→ Vault balance after deposit:", ethers.formatUnits(balanceAfter, 8), "HBAR");
      console.log("✓ Transaction hash:", tx.hash, "\n");

      expect(balanceAfter).to.equal(balanceBefore + depositAmount);
    });
  });

  describe("HBAR Withdrawal", function () {
    it("Should withdraw 0.5 HBAR from vault", async function () {
      const vaultBalanceBefore = await userVault.getHBARBalance();
      console.log("→ Vault balance before withdrawal:", ethers.formatUnits(vaultBalanceBefore, 8), "HBAR");

      if (vaultBalanceBefore === 0n) {
        console.log("⚠ No HBAR to withdraw, skipping test\n");
        this.skip();
      }

      const userBalanceBefore = await ethers.provider.getBalance(user.address);
      let withdrawAmount = ethers.parseUnits("0.5", 8);

      // Check if vault has enough
      if (vaultBalanceBefore < withdrawAmount) {
        console.log("⚠ Insufficient HBAR in vault, adjusting withdrawal amount");
        withdrawAmount = vaultBalanceBefore;
      }

      console.log("→ Withdrawing:", ethers.formatUnits(withdrawAmount, 8), "HBAR");

      const tx = await userVault.connect(user).withdrawHBAR(withdrawAmount, user.address);
      const receipt = await tx.wait();

      const vaultBalanceAfter = await userVault.getHBARBalance();
      const userBalanceAfter = await ethers.provider.getBalance(user.address);

      console.log("→ Vault balance after withdrawal:", ethers.formatUnits(vaultBalanceAfter, 8), "HBAR");

      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      console.log("→ Gas used:", ethers.formatUnits(gasUsed, 8), "HBAR");
      console.log("✓ Transaction hash:", receipt.hash, "\n");

      // Verify vault balance decreased
      expect(vaultBalanceAfter).to.equal(vaultBalanceBefore - withdrawAmount);

      // Verify user received HBAR (accounting for gas)
      expect(userBalanceAfter).to.be.closeTo(
        userBalanceBefore + withdrawAmount - gasUsed,
        ethers.parseUnits("0.001", 8) // Small tolerance in tinybars
      );
    });

    it("Should withdraw 1 HBAR from vault", async function () {
      const vaultBalanceBefore = await userVault.getHBARBalance();
      console.log("→ Vault balance before withdrawal:", ethers.formatUnits(vaultBalanceBefore, 8), "HBAR");

      if (vaultBalanceBefore === 0n) {
        console.log("⚠ No HBAR to withdraw, skipping test\n");
        this.skip();
      }

      const userBalanceBefore = await ethers.provider.getBalance(user.address);
      let withdrawAmount = ethers.parseUnits("1", 8);

      // Check if vault has enough
      if (vaultBalanceBefore < withdrawAmount) {
        console.log("⚠ Insufficient HBAR in vault, withdrawing all available");
        withdrawAmount = vaultBalanceBefore;
      }

      console.log("→ Withdrawing:", ethers.formatUnits(withdrawAmount, 8), "HBAR");

      const tx = await userVault.connect(user).withdrawHBAR(withdrawAmount, user.address);
      const receipt = await tx.wait();

      const vaultBalanceAfter = await userVault.getHBARBalance();
      const userBalanceAfter = await ethers.provider.getBalance(user.address);

      console.log("→ Vault balance after withdrawal:", ethers.formatUnits(vaultBalanceAfter, 8), "HBAR");

      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      console.log("→ Gas used:", ethers.formatUnits(gasUsed, 8), "HBAR");
      console.log("✓ Transaction hash:", receipt.hash, "\n");

      // Verify vault balance decreased
      expect(vaultBalanceAfter).to.equal(vaultBalanceBefore - withdrawAmount);

      // Verify user received HBAR (accounting for gas)
      expect(userBalanceAfter).to.be.closeTo(
        userBalanceBefore + withdrawAmount - gasUsed,
        ethers.parseUnits("0.001", 8) // Small tolerance in tinybars
      );
    });
  });

  describe("Final Summary", function () {
    it("Should display final vault information", async function () {
      const hbarBalance = await userVault.getHBARBalance();
      const owner = await userVault.owner();
      const userBalance = await ethers.provider.getBalance(user.address);

      console.log("\n╔════════════════════════════════════════╗");
      console.log("║       VAULT SUMMARY                    ║");
      console.log("╠════════════════════════════════════════╣");
      console.log("║ Vault Address:", userVaultAddress.substring(0, 20) + "...");
      console.log("║ Owner:        ", owner.substring(0, 20) + "...");
      console.log("║ HBAR Balance: ", ethers.formatUnits(hbarBalance, 8), "HBAR");
      console.log("║ User Balance: ", ethers.formatUnits(userBalance, 8), "HBAR");
      console.log("╚════════════════════════════════════════╝\n");

      expect(userVaultAddress).to.not.equal(ethers.ZeroAddress);
      expect(owner).to.equal(user.address);
    });
  });
});
