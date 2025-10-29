// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LeveragedStrategy.sol";
import {IEVault, IEVC} from "../interfaces/IEuler.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EulerLeveragedStrategy
 * @notice Leveraged strategy implementation for Euler V2 lending protocol
 * @dev Implements protocol-specific methods for:
 *      - Supply/withdraw collateral via Euler V2 Vault
 *      - Borrow/repay debt directly via Euler V2 Vault
 *      - Query collateral and debt positions via vault methods
 *
 * Key Features:
 * - Single collateral vault (e.g., PT tokens)
 * - Single debt vault (e.g., USDC)
 * - Share-based accounting for both collateral and debt
 * - Direct vault operations (no EVC needed for same-account calls)
 * - Atomic operations via inherited command execution
 * - Upgradeable via UUPS proxy pattern
 *
 * Euler V2 Specifics:
 * - EVC (Ethereum Vault Connector) used only for collateral/controller configuration
 * - Collateral and debt are tracked in separate vaults
 * - Both use share-based accounting (convertToAssets/debtToAssets)
 * - Vault operations (supply/withdraw/borrow/repay) are called directly
 *
 * IMPORTANT: Upgradeability
 * This contract is designed to be deployed behind a UUPS upgradeable proxy.
 * - Uses initializer pattern instead of constructor for state setup
 * - All state variables are stored in storage (not immutable)
 * - See constructor for critical security note about _disableInitializers()
 *
 * Related ADRs:
 * - ADR-0008: LeveragedStrategy Architecture
 * - ADR-0001: Upgradeable Contract Architecture
 */
contract EulerLeveragedStrategy is LeveragedStrategy {
    using SafeERC20 for IERC20;

    // ============ Storage Variables ============

    /// @notice Euler Verification Controller
    IEVC public evc;

    /// @notice Collateral vault address (e.g., PT token vault)
    address public collateralVault;

    /// @notice Debt vault address (e.g., USDC vault)
    address public debtVault;

    /// @notice Collateral asset address (extracted from vault)
    address public collateralAsset;

    /// @notice Debt asset address (extracted from vault)
    address public debtAsset;

    // ============ Errors ============

    error InvalidProtocol();
    error InvalidVault();

    // ============ Constructor & Initializer ============

    /**
     * @notice Constructor - disables initializers for implementation contract
     * @dev This prevents the implementation contract from being initialized.
     *      The proxy contract will call initialize() instead.
     *
     * SECURITY NOTE: In production, uncomment _disableInitializers() below!
     * For testing purposes, it's commented to allow direct initialization without proxy.
     * Production deployment MUST use a proxy with _disableInitializers() enabled.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // PRODUCTION: Uncomment the line below when deploying behind a proxy
        // _disableInitializers();
    }

    /**
     * @notice Initialize Euler strategy (for upgradeable deployment)
     * @dev This function replaces the constructor for upgradeable contracts.
     *      Must be called immediately after proxy deployment.
     *      Can only be called once due to initializer modifier.
     *
     * @param _parent Parent vault address
     * @param _baseAsset Base asset address (e.g., USDC)
     * @param _priceOracle Price oracle address
     * @param _evc Euler Verification Controller address
     * @param _collateralVault Collateral vault address
     * @param _debtVault Debt vault address
     */
    function initialize(
        address _parent,
        address _baseAsset,
        address _priceOracle,
        address _evc,
        address _collateralVault,
        address _debtVault
    ) external initializer {
        if (_evc == address(0)) revert InvalidProtocol();
        if (_collateralVault == address(0)) revert InvalidVault();
        if (_debtVault == address(0)) revert InvalidVault();

        // Initialize base contracts
        __LeveragedStrategy_init(_parent, _baseAsset, _priceOracle);

        evc = IEVC(_evc);
        collateralVault = _collateralVault;
        debtVault = _debtVault;

        // Extract asset addresses from vaults
        collateralAsset = IEVault(_collateralVault).asset();
        debtAsset = IEVault(_debtVault).asset();

        if (collateralAsset == address(0)) revert InvalidToken();
        if (debtAsset == address(0)) revert InvalidToken();

        // Enable collateral and controller in EVC
        evc.enableCollateral(address(this), _collateralVault);
        evc.enableController(address(this), _debtVault);

        // Note: We don't pre-approve tokens. Approvals are done on-demand via _approveIfNeeded
    }

    // ============ Protocol-Specific Implementation ============

    /**
     * @notice Supply collateral to Euler V2
     * @inheritdoc LeveragedStrategy
     * @dev Deposits assets into collateral vault, receiving vault shares
     */
    function _supply(address asset, uint256 amount) internal override {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        _approveIfNeeded(asset, collateralVault, amount);
        IEVault(collateralVault).deposit(amount, address(this));
    }

    /**
     * @notice Withdraw collateral from Euler V2
     * @inheritdoc LeveragedStrategy
     * @dev Withdraws assets from collateral vault directly
     */
    function _withdraw(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualWithdrawn)
    {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        // Withdraw directly from vault (EVC not needed for same-account operations)
        IEVault(collateralVault).withdraw(amount, address(this), address(this));

        // Euler withdraw returns actual withdrawn amount (or reverts)
        actualWithdrawn = amount;
    }

    /**
     * @notice Borrow from Euler V2
     * @inheritdoc LeveragedStrategy
     * @dev Borrows assets from debt vault directly
     */
    function _borrow(address asset, uint256 amount) internal override {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        // Borrow directly from vault (EVC not needed for same-account operations)
        IEVault(debtVault).borrow(amount, address(this));
    }

    /**
     * @notice Repay debt to Euler V2
     * @inheritdoc LeveragedStrategy
     * @dev Repays debt to debt vault directly
     */
    function _repay(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualRepaid)
    {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        _approveIfNeeded(asset, debtVault, amount);

        // Repay directly to vault (EVC not needed for same-account operations)
        IEVault(debtVault).repay(amount, address(this));

        // Euler repay returns actual repaid amount (or reverts)
        actualRepaid = amount;
    }

    /**
     * @notice Get collateral asset address
     * @inheritdoc LeveragedStrategy
     */
    function _getCollateralAsset() internal view override returns (address) {
        return collateralAsset;
    }

    /**
     * @notice Get debt asset address
     * @inheritdoc LeveragedStrategy
     */
    function _getDebtAsset() internal view override returns (address) {
        return debtAsset;
    }

    /**
     * @notice Get position amounts from Euler V2 (collateral and debt)
     * @inheritdoc LeveragedStrategy
     * @dev Queries vault shares and converts to assets using vault conversion methods.
     *
     *      For collateral:
     *      - Query shares: balanceOf(address(this))
     *      - Convert to assets: convertToAssets(shares)
     *
     *      For debt:
     *      - Query debt balance: debtOf(address(this))
     *      - Already in asset terms (Euler returns debt in assets)
     */
    function _getPositionAmounts() internal view override returns (uint256 collateralAmount, uint256 debtAmount) {
        // Get collateral vault shares
        uint256 collateralShares = IEVault(collateralVault).balanceOf(address(this));
        if (collateralShares > 0) {
            // Convert shares to assets
            collateralAmount = IEVault(collateralVault).convertToAssets(collateralShares);
        } else {
            collateralAmount = 0;
        }

        // Get debt amount (already in asset terms)
        debtAmount = IEVault(debtVault).debtOf(address(this));
    }
}
