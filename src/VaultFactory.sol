// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./UserVault.sol";
import "./interfaces/IHederaTokenService.sol";

/**
 * @title VaultFactory
 * @dev Factory contract for creating user-specific vaults on Hedera
 * @notice Each user can have only one vault, optimized for Hedera's account model
 */
contract VaultFactory is Ownable {
    // Mapping from user address to their vault address
    mapping(address => address) public userVaults;

    // Array of all created vaults
    address[] public allVaults;
    address public usdcTokenAddress;

    // Mapping to check if an address is a valid vault
    mapping(address => bool) public isVault;

    // Vault creation fee (in tinybars) - optional, set to 0 for free
    uint256 public vaultCreationFee;

    // Events
    event VaultCreated(
        address indexed user,
        address indexed vault,
        uint256 timestamp
    );
    event VaultRemoved(
        address indexed user,
        address indexed vault,
        uint256 timestamp
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee, uint256 timestamp);
    event FeesWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

    /**
     * @dev Constructor sets the owner and optional creation fee
     * @param _creationFee Optional fee in tinybars (1 HBAR = 100,000,000 tinybars)
     */
    constructor(uint256 _creationFee, address usdc) Ownable(msg.sender) {
        vaultCreationFee = _creationFee;
    }

    /**
     * @dev Creates a new vault for the caller
     * @notice Each user can only have one vault
     * @return vaultAddress The address of the newly created vault
     */
    function createVault() external payable returns (address) {
        require(
            userVaults[msg.sender] == address(0),
            "VaultFactory: User already has a vault"
        );
        require(
            msg.value >= vaultCreationFee,
            "VaultFactory: Insufficient creation fee"
        );

        // Deploy new UserVault contract
        UserVault newVault = new UserVault(msg.sender, address(this));
        address vaultAddress = address(newVault);

        // Store the vault address for the user
        userVaults[msg.sender] = vaultAddress;
        allVaults.push(vaultAddress);
        isVault[vaultAddress] = true;

        emit VaultCreated(msg.sender, vaultAddress, block.timestamp);

        // Refund excess payment
        if (msg.value > vaultCreationFee) {
            payable(msg.sender).transfer(msg.value - vaultCreationFee);
        }

        return vaultAddress;
    }

    /**
     * @dev Gets the vault address for a specific user
     * @param user The user's address
     * @return vaultAddress The address of the user's vault, or address(0) if none exists
     */
    function getVault(
        address user
    ) external view returns (address vaultAddress) {
        return userVaults[user];
    }

    /**
     * @dev Checks if a user has a vault
     * @param user The user's address
     * @return hasVault True if the user has a vault, false otherwise
     */
    function hasVault(address user) external view returns (bool) {
        return userVaults[user] != address(0);
    }

    /**
     * @dev Checks if an address is a valid vault created by this factory
     * @param vault The address to check
     * @return valid True if the address is a valid vault
     */
    function isValidVault(address vault) external view returns (bool valid) {
        return isVault[vault];
    }

    /**
     * @dev Gets the total number of vaults created
     * @return count The number of vaults
     */
    function getVaultCount() external view returns (uint256 count) {
        return allVaults.length;
    }

    /**
     * @dev Gets all vault addresses (paginated for gas efficiency)
     * @param offset Starting index
     * @param limit Maximum number of vaults to return
     * @return vaults Array of vault addresses
     */
    function getVaults(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory vaults) {
        require(
            offset < allVaults.length,
            "VaultFactory: Offset out of bounds"
        );

        uint256 end = offset + limit;
        if (end > allVaults.length) {
            end = allVaults.length;
        }

        uint256 resultLength = end - offset;
        address[] memory result = new address[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = allVaults[offset + i];
        }

        return result;
    }

    /**
     * @dev Gets all vault addresses (for admin purposes, use with caution for large arrays)
     * @return vaults Array of all vault addresses
     */
    function getAllVaults()
        external
        view
        onlyOwner
        returns (address[] memory vaults)
    {
        return allVaults;
    }

    /**
     * @dev Gets the current vault creation fee
     * @return fee The creation fee in tinybars
     */
    function getCreationFee() external view returns (uint256 fee) {
        return vaultCreationFee;
    }

    /**
     * @dev Updates the vault creation fee (only owner)
     * @param newFee The new creation fee in tinybars
     */
    function setCreationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = vaultCreationFee;
        vaultCreationFee = newFee;

        emit CreationFeeUpdated(oldFee, newFee, block.timestamp);
    }

    /**
     * @dev Withdraws accumulated fees (only owner)
     * @param to Address to send fees to
     */
    function withdrawFees(address payable to) external onlyOwner {
        require(to != address(0), "VaultFactory: Invalid recipient");

        uint256 balance = address(this).balance;
        require(balance > 0, "VaultFactory: No fees to withdraw");

        (bool success, ) = to.call{value: balance}("");
        require(success, "VaultFactory: Withdrawal failed");

        emit FeesWithdrawn(to, balance, block.timestamp);
    }

    /**
     * @dev Gets the contract's HBAR balance
     * @return balance The balance in tinybars
     */
    function getBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @dev Removes a vault (only owner, emergency use only)
     * @param user The user whose vault should be removed
     */
    function removeVault(address user) external onlyOwner {
        address vaultAddress = userVaults[user];
        require(
            vaultAddress != address(0),
            "VaultFactory: No vault exists for this user"
        );

        // Remove from mapping
        delete userVaults[user];
        isVault[vaultAddress] = false;

        // Remove from array (find and swap with last element)
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (allVaults[i] == vaultAddress) {
                allVaults[i] = allVaults[allVaults.length - 1];
                allVaults.pop();
                break;
            }
        }

        emit VaultRemoved(user, vaultAddress, block.timestamp);
    }

    /**
     * @dev Allows the contract to receive HBAR
     */
    receive() external payable {
        // Contract can receive HBAR for fees
    }
}
