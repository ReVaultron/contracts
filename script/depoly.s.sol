// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {UserVault} from "../src/UserVault.sol";

/// @notice Deployment script that deploys VaultFactory and a sample UserVault
contract DeployScript is Script {
    function run() external returns (address, address) {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        address deployerAddress = vm.addr(deployerPrivateKey);

        // Deploy VaultFactory (set creation fee to 0 by default)
        VaultFactory factory = new VaultFactory(0);
        console.log("VaultFactory deployed to:", address(factory));

        // Optionally deploy a UserVault directly (usually created via factory)
        UserVault sampleVault = new UserVault(deployerAddress, address(factory));
        console.log("Sample UserVault deployed to:", address(sampleVault));

        vm.stopBroadcast();

        return (address(factory), address(sampleVault));
    }
}