// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IParentStrategy
 * @notice Interface for parent vault that manages multiple child strategies
 * @dev Parent vault coordinates withdrawals across child strategies with validation
 *
 * Key principles:
 * - Offchain (keeper/owner) selects which strategies to withdraw from
 * - Onchain validation ensures withdrawal fairness within tolerance
 * - Enables gas-efficient selective withdrawals instead of proportional from all strategies
 */
interface IParentStrategy {
    // ============ Structs ============

    /**
     * @notice Parameters for withdrawing from a specific child strategy
     * @param strategy Address of child strategy
     * @param percentage Percentage to withdraw from this strategy's NAV (1e18 = 100%)
     * @param outputToken Desired output token
     * @param flashLoanToken Flash loan token (address(0) if none)
     * @param providedAmount Amount provided to strategy (flash loan)
     * @param expectedAmount Amount expected back from strategy
     * @param data Strategy-specific execution data
     */
    struct WithdrawalRequest {
        address strategy;
        uint256 percentage;
        address outputToken;
        address flashLoanToken;
        uint256 providedAmount;
        uint256 expectedAmount;
        bytes data;
    }

    // ============ Events ============

    /**
     * @notice Emitted when withdrawal tolerance is updated
     * @param oldToleranceBps Old tolerance in basis points
     * @param newToleranceBps New tolerance in basis points
     */
    event WithdrawalToleranceUpdated(uint256 oldToleranceBps, uint256 newToleranceBps);

    /**
     * @notice Emitted when user withdraws from vault
     * @param user User address
     * @param shares Shares burned
     * @param assets Assets received
     * @param strategiesCount Number of strategies withdrawn from
     */
    event Withdrawn(
        address indexed user,
        uint256 shares,
        uint256 assets,
        uint256 strategiesCount
    );

    // ============ Errors ============

    error InvalidWithdrawalAmount();
    error InvalidTolerance();
    error NoStrategies();

    // ============ Configuration ============

    /**
     * @notice Get withdrawal tolerance in basis points
     * @dev Used to validate that actual withdrawal matches expected within tolerance
     *      Example: 50 bps = 0.5% tolerance
     * @return Tolerance in basis points (1 bps = 0.01%)
     */
    function withdrawalToleranceBps() external view returns (uint256);

    /**
     * @notice Set withdrawal tolerance
     * @dev Only callable by owner/governance
     * @param newToleranceBps New tolerance in basis points
     */
    function setWithdrawalTolerance(uint256 newToleranceBps) external;

    // ============ Core Operations ============

    /**
     * @notice Withdraw assets by burning shares
     * @dev Validates that total withdrawn amount matches expected percentage of NAV
     *      within configured tolerance. Keeper selects which strategies to withdraw from.
     *
     * Validation Logic:
     * 1. Calculate total NAV across all strategies
     * 2. Calculate expected assets based on shares: expectedAssets = convertToAssets(shares)
     * 3. Calculate expected percentage: expectedPct = (expectedAssets * 1e18) / totalNAV
     * 4. Execute withdrawals from selected strategies
     * 5. Calculate actual percentage: actualPct = (totalWithdrawn * 1e18) / totalNAV
     * 6. Validate: |actualPct - expectedPct| <= tolerance
     *
     * @param shares Amount of shares to burn
     * @param requests Array of withdrawal requests for selected strategies
     * @param receiver Address to receive withdrawn assets
     * @return assets Total assets withdrawn
     */
    function withdraw(
        uint256 shares,
        WithdrawalRequest[] calldata requests,
        address receiver
    ) external returns (uint256 assets);

    /**
     * @notice Get total NAV across all child strategies
     * @return Total net asset value in base asset terms
     */
    function getTotalNAV() external view returns (uint256);

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return Amount of assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256);
}
