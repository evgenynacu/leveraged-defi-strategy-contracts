// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LeveragedStrategy.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MorphoLeveragedStrategy
 * @notice Leveraged strategy implementation for Morpho Blue lending protocol
 * @dev Implements protocol-specific methods for:
 *      - Supply/withdraw collateral via Morpho Blue
 *      - Borrow/repay debt with share-based accounting
 *      - Query collateral and debt positions via Morpho position tracking
 *
 * Key Features:
 * - Single collateral asset (e.g., PT tokens)
 * - Single debt asset (e.g., USDC)
 * - Share-based debt accounting (similar to Aave V3)
 * - Market identified by unique Id (derived from MarketParams)
 * - Atomic operations via inherited command execution
 * - Upgradeable via UUPS proxy pattern
 *
 * Morpho Blue Specifics:
 * - Uses MarketParams struct to identify markets
 * - Collateral is tracked separately from supply (we only use collateral)
 * - Borrow positions use share-based accounting for precision
 * - Need to convert between shares and assets for debt calculations
 *
 * IMPORTANT: Upgradeability
 * This contract is designed to be deployed behind a UUPS upgradeable proxy.
 * - Uses initializer pattern instead of constructor for state setup
 * - All state variables are stored in storage (not immutable)
 * - For production: uncomment _disableInitializers() in constructor
 *
 * Related ADRs:
 * - ADR-0008: LeveragedStrategy Architecture
 * - ADR-0001: Upgradeable Contract Architecture
 */
contract MorphoLeveragedStrategy is LeveragedStrategy {
    using SafeERC20 for IERC20;

    // ============ Storage Variables ============

    /// @notice Morpho Blue contract
    IMorpho public morpho;

    /// @notice Market ID for this strategy
    Id public marketId;

    /// @notice Collateral asset address (e.g., PT token)
    address public collateralAsset;

    /// @notice Debt asset address (e.g., USDC)
    address public debtAsset;

    // ============ Errors ============

    error InvalidProtocol();
    error InvalidMarketId();

    // ============ Constructor & Initializer ============

    /**
     * @notice Constructor - disables initializers for implementation contract
     * @dev This prevents the implementation contract from being initialized.
     *      The proxy contract will call initialize() instead.
     *
     *      NOTE: For production deployments behind a proxy, uncomment _disableInitializers().
     *      For testing without proxy, this is left enabled to allow direct initialization.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Uncomment for production proxy deployment:
        // _disableInitializers();
    }

    /**
     * @notice Initialize Morpho strategy (for upgradeable deployment)
     * @dev This function replaces the constructor for upgradeable contracts.
     *      Must be called immediately after proxy deployment.
     *      Can only be called once due to initializer modifier.
     *
     * @param _parent Parent vault address
     * @param _baseAsset Base asset address (e.g., USDC)
     * @param _priceOracle Price oracle address
     * @param _morpho Morpho Blue contract address
     * @param _marketId Market ID for this strategy
     */
    function initialize(
        address _parent,
        address _baseAsset,
        address _priceOracle,
        address _morpho,
        Id _marketId
    ) external initializer {
        if (_morpho == address(0)) revert InvalidProtocol();
        if (Id.unwrap(_marketId) == bytes32(0)) revert InvalidMarketId();

        // Initialize base contracts
        __LeveragedStrategy_init(_parent, _baseAsset, _priceOracle);

        morpho = IMorpho(_morpho);
        marketId = _marketId;

        // Extract collateral and debt assets from market params
        MarketParams memory params = morpho.idToMarketParams(_marketId);
        if (params.collateralToken == address(0)) revert InvalidToken();
        if (params.loanToken == address(0)) revert InvalidToken();

        collateralAsset = params.collateralToken;
        debtAsset = params.loanToken;

        // Note: We don't pre-approve tokens. Approvals are done on-demand via _approveIfNeeded
    }

    // ============ Protocol-Specific Implementation ============

    /**
     * @notice Supply collateral to Morpho Blue
     * @inheritdoc LeveragedStrategy
     * @dev Uses supplyCollateral() instead of supply() to post collateral without earning interest
     */
    function _supply(address asset, uint256 amount) internal override {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        MarketParams memory params = morpho.idToMarketParams(marketId);
        _approveIfNeeded(asset, address(morpho), amount);
        morpho.supplyCollateral(params, amount, address(this), "");
    }

    /**
     * @notice Withdraw collateral from Morpho Blue
     * @inheritdoc LeveragedStrategy
     */
    function _withdraw(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualWithdrawn)
    {
        if (asset != collateralAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        MarketParams memory params = morpho.idToMarketParams(marketId);
        morpho.withdrawCollateral(params, amount, address(this), address(this));

        // Morpho doesn't return withdrawn amount, assume it matches request
        actualWithdrawn = amount;
    }

    /**
     * @notice Borrow from Morpho Blue
     * @inheritdoc LeveragedStrategy
     * @dev Borrows assets (not shares) - Morpho converts to shares internally
     */
    function _borrow(address asset, uint256 amount) internal override {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        MarketParams memory params = morpho.idToMarketParams(marketId);
        morpho.borrow(
            params,
            amount,      // assets to borrow
            0,           // shares = 0 (use assets instead)
            address(this), // onBehalf
            address(this)  // receiver
        );
    }

    /**
     * @notice Repay debt to Morpho Blue
     * @inheritdoc LeveragedStrategy
     * @dev Repays assets (not shares) - Morpho converts to shares internally
     */
    function _repay(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualRepaid)
    {
        if (asset != debtAsset) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();

        MarketParams memory params = morpho.idToMarketParams(marketId);
        _approveIfNeeded(asset, address(morpho), amount);

        (actualRepaid, ) = morpho.repay(
            params,
            amount,      // assets to repay
            0,           // shares = 0 (use assets instead)
            address(this), // onBehalf
            ""           // data
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
     * @notice Get position amounts from Morpho Blue (collateral and debt)
     * @inheritdoc LeveragedStrategy
     * @dev Makes a single call to position() which returns both collateral and borrowShares.
     *      Then converts borrowShares to assets using market data.
     *
     *      This matches the TypeScript logic in morpho.ts:
     *      - totalDebt = pos.borrowShares * totalBorrowAssets / market.totalBorrowShares
     */
    function _getPositionAmounts() internal view override returns (uint256 collateralAmount, uint256 debtAmount) {
        Position memory pos = morpho.position(marketId, address(this));
        collateralAmount = pos.collateral;

        // Convert borrow shares to assets
        if (pos.borrowShares > 0) {
            Market memory market = morpho.market(marketId);
            if (market.totalBorrowShares > 0) {
                // debtAmount = borrowShares * totalBorrowAssets / totalBorrowShares
                debtAmount = (uint256(pos.borrowShares) * uint256(market.totalBorrowAssets))
                    / uint256(market.totalBorrowShares);
            } else {
                debtAmount = 0;
            }
        } else {
            debtAmount = 0;
        }
    }

    /**
     * @notice Calculate safe withdrawal amounts for Morpho considering health factor
     * @inheritdoc LeveragedStrategy
     * @dev Morpho-specific implementation that matches TypeScript logic from morpho.ts:
     *      - Debt to repay (assets): (totalDebt * (percentage + 1)) / DENOMINATOR
     *      - Debt shares to repay: (borrowShares * percentage) / DENOMINATOR
     *      - Collateral: (totalCollateral * percentage) / DENOMINATOR
     *
     *      The +1 on debt assets means we repay slightly more (1/DENOMINATOR = 1/1e18 extra)
     *      to ensure the position remains safe after withdrawal.
     *
     *      Note: We only return the asset amounts here. The share calculation would be:
     *      debtSharesToRepay = borrowShares * percentage / DENOMINATOR
     *      But since we use assets in _repay(), Morpho handles the conversion internally.
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
}
