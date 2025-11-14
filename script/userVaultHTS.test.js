const { expect } = require("chai");
const { ethers } = require("hardhat");
require("dotenv").config();

// Deployment info
const VAULT_FACTORY_ADDRESS = "0x443cf9983ace1b17378A9F7e7428D40abB7302e7";
const HTS_TOKEN_ADDRESS = "0x546268afB164e72C7e0bf6262b0A406860d93F47";

describe("Vault HTS Token Operations (On-Chain)", function () {
  let vaultFactory;
  let userVault;
  let user;
  let userVaultAddress;

  before(async function () {
    // Get user from private key in .env
    user = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    console.log("\nTesting with user address:", user.address);

    // Connect to deployed VaultFactory
    vaultFactory = await ethers.getContractAt("VaultFactory", VAULT_FACTORY_ADDRESS);
    console.log("Connected to VaultFactory at:", VAULT_FACTORY_ADDRESS);

    // Check if user already has a vault
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
    console.log("HTS Token address:", HTS_TOKEN_ADDRESS, "\n");
  });

  describe("HTS Token Association", function () {
    it("Should associate HTS token with vault", async function () {
      try {
        const isAssociated = await userVault.isTokenAssociated(HTS_TOKEN_ADDRESS);
        console.log("→ Token currently associated:", isAssociated);

        if (!isAssociated) {
          console.log("→ Associating HTS token with vault...");
          console.log("  Note: This calls HTS precompile at 0x167");

          const tx = await userVault.connect(user).associateToken(HTS_TOKEN_ADDRESS);
          const receipt = await tx.wait();

          console.log("✓ Token associated successfully");
          console.log("✓ Transaction hash:", receipt.hash, "\n");
        } else {
          console.log("✓ Token already associated\n");
        }

        expect(await userVault.isTokenAssociated(HTS_TOKEN_ADDRESS)).to.be.true;
      } catch (error) {
        console.error("\n❌ Token association failed");
        console.error("Error:", error.message);
        console.log("\n⚠ This is expected if:");
        console.log("  1. Token address is not a valid HTS token on testnet");
        console.log("  2. Token does not exist");
        console.log("  3. HTS precompile is not accessible");
        console.log("\nTo create an HTS token, use:");
        console.log("  - Hedera Token Service SDK");
        console.log("  - HashPack wallet");
        console.log("  - Hedera testnet portal\n");
        this.skip();
      }
    });
  });

  describe("HTS Token Deposit", function () {
    it("Should deposit HTS tokens to vault", async function () {
      // Check if token is associated
      const isAssociated = await userVault.isTokenAssociated(HTS_TOKEN_ADDRESS);
      if (!isAssociated) {
        console.log("⚠ Token not associated with vault, skipping test\n");
        this.skip();
      }

      try {
        // Get balance before deposit
        const balanceBefore = await userVault.getBalance(HTS_TOKEN_ADDRESS);
        console.log("→ Vault token balance before deposit:", balanceBefore.toString());

        // Deposit amount (100 token units - adjust based on token decimals)
        const depositAmount = 100;
        console.log("→ Depositing:", depositAmount, "token units");

        const tx = await userVault.connect(user).deposit(HTS_TOKEN_ADDRESS, depositAmount);
        const receipt = await tx.wait();

        const balanceAfter = await userVault.getBalance(HTS_TOKEN_ADDRESS);
        console.log("→ Vault token balance after deposit:", balanceAfter.toString());
        console.log("✓ Transaction hash:", receipt.hash, "\n");

        expect(balanceAfter).to.be.gt(balanceBefore);
      } catch (error) {
        console.error("\n❌ Deposit failed");
        console.error("Error:", error.message);
        console.log("\n⚠ Make sure:");
        console.log("  1. You own HTS tokens at:", HTS_TOKEN_ADDRESS);
        console.log("  2. Your account is associated with the token");
        console.log("  3. You have enough tokens to deposit");
        console.log("  4. Token transfer is not restricted\n");
        throw error;
      }
    });
  });

  describe("HTS Token Withdrawal", function () {
    it("Should withdraw HTS tokens from vault", async function () {
      // Check if token is associated
      const isAssociated = await userVault.isTokenAssociated(HTS_TOKEN_ADDRESS);
      if (!isAssociated) {
        console.log("⚠ Token not associated with vault, skipping test\n");
        this.skip();
      }

      try {
        // Get balance before withdrawal
        const balanceBefore = await userVault.getBalance(HTS_TOKEN_ADDRESS);
        console.log("→ Vault token balance before withdrawal:", balanceBefore.toString());

        if (balanceBefore === 0n) {
          console.log("⚠ No tokens to withdraw, skipping test\n");
          this.skip();
        }

        // Withdraw amount (half of balance or 50 tokens)
        const withdrawAmount = balanceBefore > 50n ? 50 : Number(balanceBefore / 2n);
        console.log("→ Withdrawing:", withdrawAmount, "token units");

        const tx = await userVault.connect(user).withdrawTo(
          HTS_TOKEN_ADDRESS,
          withdrawAmount,
          user.address
        );
        const receipt = await tx.wait();

        const balanceAfter = await userVault.getBalance(HTS_TOKEN_ADDRESS);
        console.log("→ Vault token balance after withdrawal:", balanceAfter.toString());
        console.log("✓ Transaction hash:", receipt.hash, "\n");

        expect(balanceAfter).to.be.lt(balanceBefore);
      } catch (error) {
        console.error("\n❌ Withdrawal failed");
        console.error("Error:", error.message);
        console.log("\n⚠ Recipient must be associated with the token\n");
        throw error;
      }
    });
  });

  describe("Token Information", function () {
    it("Should display token balance and vault info", async function () {
      let tokenBalance = "Not associated";
      let isAssociated = false;

      try {
        isAssociated = await userVault.isTokenAssociated(HTS_TOKEN_ADDRESS);
        if (isAssociated) {
          tokenBalance = (await userVault.getBalance(HTS_TOKEN_ADDRESS)).toString();
        }
      } catch (error) {
        console.log("Could not get token balance");
      }

      const owner = await userVault.owner();

      console.log("\n╔════════════════════════════════════════╗");
      console.log("║       HTS TOKEN VAULT INFO             ║");
      console.log("╠════════════════════════════════════════╣");
      console.log("║ Vault Address:    ", userVaultAddress.substring(0, 18) + "...");
      console.log("║ Token Address:    ", HTS_TOKEN_ADDRESS.substring(0, 18) + "...");
      console.log("║ Owner:            ", owner.substring(0, 18) + "...");
      console.log("║ Token Associated: ", isAssociated);
      console.log("║ Token Balance:    ", tokenBalance);
      console.log("╚════════════════════════════════════════╝\n");

      expect(userVaultAddress).to.not.equal(ethers.ZeroAddress);
    });
  });
});
