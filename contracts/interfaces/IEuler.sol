// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IEVault
 * @notice Interface for Euler V2 Vault
 * @dev Based on Euler V2 documentation and previous integration
 */
interface IEVault {
    // Deposit underlying assets, mint shares to receiver
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    // Withdraw underlying assets to receiver, burning from owner
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    // Borrow underlying assets to receiver; debt is recorded to the EVC "account" context
    function borrow(uint256 assets, address receiver) external returns (uint256 assetsBorrowed);

    // Repay underlying assets on behalf of a specific account (debt owner)
    function repay(uint256 assets, address onBehalfOf) external returns (uint256 sharesRepaid);

    /**
     * @notice Get the balance of vault shares for an account
     * @param account Account address
     * @return Balance of vault shares
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get the debt balance for an account
     * @param account Account address
     * @return Debt balance
     */
    function debtOf(address account) external view returns (uint256);

    /**
     * @notice Get the underlying asset address
     * @return Asset address
     */
    function asset() external view returns (address);

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
}

/**
 * @title IEVC
 * @notice Interface for Euler Verification Controller
 * @dev The EVC manages account authentication and authorization in Euler V2
 */
interface IEVC {
    function enableCollateral(address account, address vault) external;
    function enableController(address account, address vault) external;
}
