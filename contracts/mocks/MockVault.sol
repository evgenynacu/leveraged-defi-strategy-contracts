// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../BaseVault.sol";
import "./MockERC20.sol";

/**
 * @title MockVault
 * @dev Simple implementation of BaseVault for testing purposes
 * This vault simply holds assets without any complex strategy
 */
contract MockVault is BaseVault {
    // Mock capacity limit for testing
    uint256 public maxCapacity;

    // Events for testing strategy hooks
    event MockDeploy(uint256 assets, bytes data);
    event MockWithdraw(uint256 shares, uint256 assets, bytes data);

    /**
     * @notice Initialize the mock vault
     */
    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _performanceFee,
        address _feeRecipient,
        uint256 _maxCapacity
    ) external initializer {
        __BaseVault_init(_asset, _name, _symbol, _performanceFee, _feeRecipient);
        maxCapacity = _maxCapacity;
    }

    /**
     * @notice Get total assets managed by the vault
     * @return Total asset value
     */
    function totalAssets() public view override returns (uint256) {
        // Simply return the actual balance of the contract
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Get available capacity for new deposits
     * @return Available capacity
     */
    function availableCapacity() external view override returns (uint256) {
        uint256 currentAssets = totalAssets();
        if (currentAssets >= maxCapacity) {
            return 0;
        }
        return maxCapacity - currentAssets;
    }

    /**
     * @notice Deploy assets (mock implementation)
     * @param assets Amount of assets to deploy
     * @param data Additional data
     */
    function _deploy(uint256 assets, bytes calldata data) internal override {
        // Simple mock: assets are already in the contract, just emit event
        emit MockDeploy(assets, data);
    }

    /**
     * @notice Withdraw assets (mock implementation)
     * @param shares Amount of shares being withdrawn
     * @param data Additional data
     * @return assets Amount of assets withdrawn
     */
    function _withdrawUnderlying(uint256 shares, bytes calldata data) internal override returns (uint256 assets) {
        // Calculate proportional withdrawal based on shares
        uint256 totalSupply_ = totalSupply(); // Use current total supply (shares not burned yet)
        if (totalSupply_ == 0) {
            return 0;
        }

        uint256 totalAssets_ = totalAssets();
        assets = (shares * totalAssets_) / totalSupply_;

        emit MockWithdraw(shares, assets, data);
    }

    // ============ Test Helper Functions ============

    /**
     * @notice Set max capacity for testing
     */
    function setMaxCapacity(uint256 _maxCapacity) external onlyManager {
        maxCapacity = _maxCapacity;
    }

    /**
     * @notice Simulate asset removal from vault (strategy losses)
     * @param amount Amount of tokens to remove from vault
     */
    function removeAssets(uint256 amount) external {
        uint256 currentBalance = asset.balanceOf(address(this));
        if (amount > currentBalance) {
            amount = currentBalance;
        }
        if (amount > 0) {
            MockERC20(address(asset)).burn(address(this), amount);
        }
    }

    /**
     * @notice Add assets to vault (strategy gains)
     * @param amount Amount of tokens to add to vault
     */
    function addAssets(uint256 amount) external {
        MockERC20(address(asset)).mint(address(this), amount);
    }
}
