// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ManualSwapper is Ownable {

    // USDC token (ERC-20)
    IERC20 public usdc;

    // pricePerHBAR = how many USDC units for 1 HBAR (10^8 tinybars)
    // Example: if 1 HBAR = 0.05 USDC (USDC has 6 decimals) → pricePerHBAR = 50_000
    // On Hedera, msg.value is in tinybars, so we need to convert
    uint256 public pricePerHBAR;

    // Tinybars per HBAR constant
    uint256 constant TINYBARS_PER_HBAR = 10 ** 8;

    constructor(address _usdc, uint256 _price) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC token");
        usdc = IERC20(_usdc);
        pricePerHBAR = _price;
    }

    /// @notice Owner can update price anytime
    function setPrice(uint256 newPrice) external onlyOwner {
        pricePerHBAR = newPrice;
    }

    /// @notice Get the amount of USDC for a given HBAR amount
    /// @param hbarAmount Amount of HBAR in wei-bar (EVM standard: 10^18 per HBAR)
    /// @dev Converts wei-bar to tinybars, then applies price
    function getAmountOut(uint256 hbarAmount) public view returns (uint256) {
        // Convert wei-bar to tinybars: wei-bar ÷ 10^10 = tinybars
        uint256 tinybars = hbarAmount / (10 ** 10);
        // Calculate USDC: (tinybars × pricePerHBAR) / TINYBARS_PER_HBAR
        return (tinybars * pricePerHBAR) / TINYBARS_PER_HBAR;
    }

    /// @notice Swap HBAR → USDC using fixed price
    /// @dev msg.value on Hedera is in tinybars
    function swap(address receiver) external payable returns (uint256 amountOut) {
        require(msg.value > 0, "No HBAR sent");
        require(receiver != address(0), "Invalid receiver");

        // On Hedera, msg.value is in tinybars
        // Calculate USDC: (tinybars × pricePerHBAR) / TINYBARS_PER_HBAR
        amountOut = (msg.value * pricePerHBAR) / TINYBARS_PER_HBAR;

        // Check swapper has enough USDC
        require(usdc.balanceOf(address(this)) >= amountOut, "Insufficient USDC liquidity");

        // Send USDC to receiver
        require(usdc.transfer(receiver, amountOut), "USDC transfer failed");
        
        return amountOut;
    }

    /// @notice Owner can withdraw HBAR
    function withdrawHBAR(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    /// @notice Owner can withdraw leftover USDC
    function withdrawUSDC(uint256 amount) external onlyOwner {
        require(usdc.transfer(owner(), amount), "USDC withdraw failed");
    }

    /// @notice Owner can deposit USDC liquidity
    function depositUSDC(uint256 amount) external onlyOwner {
        require(usdc.transferFrom(msg.sender, address(this), amount), "USDC deposit failed");
    }

    /// @notice Get USDC balance of swapper
    function getUSDCBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    receive() external payable {}
}

