// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LeveragedStrategy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AaveLeveragedStrategy
 * @notice Leveraged strategy implementation for Aave V3 lending protocol
 * @dev Implements protocol-specific methods for:
 *      - Supply/withdraw collateral via Aave Pool
 *      - Borrow/repay debt with variable interest rate
 *      - Query collateral and debt positions via PoolDataProvider
 *
 * Key Features:
 * - Single collateral asset (e.g., PT tokens)
 * - Single debt asset (e.g., USDC)
 * - Variable interest rate mode (interestRateMode = 2)
 * - Atomic operations via inherited command execution
 *
 * Related ADRs:
 * - ADR-0008: LeveragedStrategy Architecture
 */
contract AaveLeveragedStrategy is LeveragedStrategy {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Aave interest rate mode: 2 = variable rate
    uint256 private constant INTEREST_RATE_MODE = 2;

    /// @notice Aave referral code (0 = no referral)
    uint16 private constant REFERRAL_CODE = 0;

    // ============ Immutable State ============

    /// @notice Aave V3 Pool contract
    IPool public immutable pool;

    /// @notice Collateral asset address (e.g., PT token)
    address public immutable collateralAsset;

    /// @notice Debt asset address (e.g., USDC)
    address public immutable debtAsset;

    // ============ Errors ============

    error InvalidProtocol();

    // ============ Constructor ============

    /**
     * @notice Initialize Aave strategy
     * @param _parent Parent vault address
     * @param _baseAsset Base asset address (e.g., USDC)
     * @param _priceOracle Price oracle address
     * @param _pool Aave V3 Pool address
     * @param _collateralAsset Collateral asset address
     * @param _debtAsset Debt asset address
     */
    constructor(
        address _parent,
        address _baseAsset,
        address _priceOracle,
        address _pool,
        address _collateralAsset,
        address _debtAsset
    ) LeveragedStrategy(_parent, _baseAsset, _priceOracle) {
        if (_pool == address(0)) revert InvalidProtocol();
        if (_collateralAsset == address(0)) revert InvalidToken();
        if (_debtAsset == address(0)) revert InvalidToken();

        pool = IPool(_pool);
        collateralAsset = _collateralAsset;
        debtAsset = _debtAsset;

        // Note: We don't pre-approve tokens. Approvals are done on-demand via _approveIfNeeded
    }

    // ============ Protocol-Specific Implementation ============

    /**
     * @notice Supply collateral to Aave
     * @inheritdoc LeveragedStrategy
     */
    function _supply(address asset, uint256 amount) internal override {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        _approveIfNeeded(asset, address(pool), amount);
        pool.supply(asset, amount, address(this), REFERRAL_CODE);
    }

    /**
     * @notice Withdraw collateral from Aave
     * @inheritdoc LeveragedStrategy
     */
    function _withdraw(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualWithdrawn)
    {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        actualWithdrawn = pool.withdraw(asset, amount, address(this));
    }

    /**
     * @notice Borrow from Aave
     * @inheritdoc LeveragedStrategy
     */
    function _borrow(address asset, uint256 amount) internal override {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        pool.borrow(
            asset,
            amount,
            INTEREST_RATE_MODE,
            REFERRAL_CODE,
            address(this)
        );
    }

    /**
     * @notice Repay debt to Aave
     * @inheritdoc LeveragedStrategy
     */
    function _repay(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualRepaid)
    {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        _approveIfNeeded(asset, address(pool), amount);
        actualRepaid = pool.repay(
            asset,
            amount,
            INTEREST_RATE_MODE,
            address(this)
        );
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
     * @notice Get position amounts from Aave (collateral and debt)
     * @inheritdoc LeveragedStrategy
     * @dev Makes two external calls to PoolDataProvider - one for each asset.
     *      This is more gas-efficient than the alternative of calling getUserAccountData
     *      which returns aggregated data in base currency that would need conversion.
     */
    function _getPositionAmounts() internal view override returns (uint256 collateralAmount, uint256 debtAmount) {
        IPoolDataProvider dataProvider = _getDataProvider();

        // Get collateral (aToken balance) from collateralAsset reserve
        (collateralAmount, , , , , , , , ) = dataProvider
            .getUserReserveData(collateralAsset, address(this));

        // Get debt from debtAsset reserve (separate call needed if different assets)
        (, , debtAmount, , , , , , ) = dataProvider
            .getUserReserveData(debtAsset, address(this));
    }

    /**
     * @notice Calculate safe withdrawal amounts for Aave considering health factor
     * @inheritdoc LeveragedStrategy
     * @dev Aave-specific implementation that matches TypeScript logic:
     *      - Debt: (totalDebt * (percentage + 1)) / DENOMINATOR
     *      - Collateral: (totalCollateral * percentage) / DENOMINATOR
     *
     *      The +1 on debt means we repay slightly more (1/DENOMINATOR = 1/1e18 extra)
     *      to ensure the position remains safe after withdrawal.
     */
    function _calculateSafeWithdrawAmounts(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 percentage
    ) internal view override returns (uint256 repayAmount, uint256 withdrawAmount) {
        // Collateral: simple proportional withdrawal
        // Matches: totalCollateral * floor(collateralShare * multiplier) / multiplier
        withdrawAmount = (collateralAmount * percentage) / PERCENTAGE_DENOMINATOR;

        // Debt: add +1 to percentage before division to repay slightly more
        // Matches: totalDebt * floor(debtShare * multiplier + 1) / multiplier
        // This adds 1/PERCENTAGE_DENOMINATOR (1/1e18) extra to the debt repayment
        repayAmount = (debtAmount * (percentage + 1)) / PERCENTAGE_DENOMINATOR;
    }

    // ============ Internal Helpers ============

    /**
     * @notice Get PoolDataProvider from Pool's AddressesProvider
     * @dev Reads dynamically from the pool's addresses provider
     */
    function _getDataProvider() internal view returns (IPoolDataProvider) {
        IPoolAddressesProvider addressesProvider = pool.ADDRESSES_PROVIDER();
        address dataProviderAddress = addressesProvider.getPoolDataProvider();
        return IPoolDataProvider(dataProviderAddress);
    }

    /**
     * @notice Approve token if current allowance is insufficient
     * @dev Saves gas by only approving when needed
     * @param token Token to approve
     * @param spender Spender to approve
     * @param amount Minimum required allowance
     */
    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
        if (currentAllowance < amount) {
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }
}
