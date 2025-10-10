// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IChildStrategy
 * @notice Interface for child strategy contracts that execute leveraged yield strategies
 * @dev Child strategies are single-owner execution engines controlled by parent vault.
 *      They handle lending protocol operations, token swaps, and leverage management.
 *
 * Key principles:
 * - Single caller: only parent vault can execute operations
 * - No internal shares: parent owns all assets directly
 * - Multi-token support: accept/return any token, not just base asset
 * - Synchronous operations: no user queues or internal epochs
 *
 * Related ADRs:
 * - ADR-0006: Child Strategy Interface
 * - ADR-0008: LeveragedStrategy Architecture
 */
interface IChildStrategy {
    // ============ Events ============

    /**
     * @notice Emitted when assets are deposited into the strategy
     * @param depositToken Token that was deposited
     * @param depositAmount Amount of deposit token
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (flash loan)
     * @param expectedAmount Amount expected back by parent
     */
    event Deposited(
        address indexed depositToken,
        uint256 depositAmount,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount
    );

    /**
     * @notice Emitted when assets are withdrawn from the strategy
     * @param percentage Percentage withdrawn (1e18 = 100%)
     * @param outputToken Token received from withdrawal
     * @param actualWithdrawn Actual amount withdrawn
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (flash loan)
     * @param expectedAmount Amount expected back by parent
     */
    event Withdrawn(
        uint256 percentage,
        address indexed outputToken,
        uint256 actualWithdrawn,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount
    );

    /**
     * @notice Emitted when strategy is rebalanced internally
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (flash loan)
     * @param expectedAmount Amount expected back by parent
     */
    event Rebalanced(
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount
    );

    // ============ Errors ============

    error Unauthorized();
    error InvalidPercentage();
    error InsufficientBalance();

    // Note: InvalidToken and InvalidAmount errors defined in SwapHelper

    // ============ Core Operations ============

    /**
     * @notice Deploy assets into leveraged strategy
     * @dev Parent provides depositToken and optionally flash loan liquidity.
     *      Strategy executes commands to build leveraged position.
     *      If expectedAmount > 0, strategy must approve that amount for parent collection.
     *
     * Flash Loan Pattern:
     * - Parent vault tracks netFlow for flashLoanToken across all child operations
     * - netFlow += providedAmount when child receives flash loan
     * - netFlow -= expectedAmount when child returns tokens
     * - At transaction end: require(netFlow == 0) ensures full repayment
     *
     * Requirements:
     * - flashLoanToken must be in _trackedTokens() if providedAmount or expectedAmount > 0
     *
     * @param depositToken Token being deposited (PT, USDC, ETH, etc.)
     * @param depositAmount Amount of deposit token
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (flash loan for leverage)
     * @param expectedAmount Amount parent expects back (flash loan repayment)
     * @param data Strategy-specific execution data (encoded commands)
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    /**
     * @notice Withdraw from strategy by percentage
     * @dev Withdraws proportional share of collateral and repays proportional debt.
     *      Parent may provide flash loan liquidity for debt repayment.
     *      Strategy returns assets in outputToken and repays flash loan.
     *
     * Flash Loan Pattern (same as deposit):
     * - Parent tracks netFlow for flashLoanToken
     * - netFlow updated by providedAmount and expectedAmount
     * - Transaction end: require(netFlow == 0)
     *
     * Requirements:
     * - percentage must be > 0 and <= 1e18 (100%)
     * - outputToken must NOT be address(0) - strategy must know what token to return
     * - flashLoanToken must be in _trackedTokens() if providedAmount or expectedAmount > 0
     *
     * @param percentage Percentage to withdraw (1e18 = 100%)
     * @param outputToken Desired output token (MUST NOT be address(0))
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (flash loan for debt repayment)
     * @param expectedAmount Amount parent expects back (flash loan repayment + withdrawn assets)
     * @param data Strategy-specific execution data (encoded commands)
     * @return actualWithdrawn Amount actually withdrawn in outputToken
     */
    function withdraw(
        uint256 percentage,
        address outputToken,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external returns (uint256 actualWithdrawn);

    /**
     * @notice Rebalance strategy internally
     * @dev Used for internal optimizations like debt refinancing or leverage adjustment.
     *      Does not change overall position size, only internal structure.
     *
     * Flash Loan Pattern (same as deposit/withdraw):
     * - Parent tracks netFlow for flashLoanToken
     * - Supports multi-child operations (A receives, B returns)
     * - Transaction end: require(netFlow == 0)
     *
     * @param flashLoanToken Token used for flash loan (address(0) if none)
     * @param providedAmount Amount provided by parent (liquidity for refinancing)
     * @param expectedAmount Amount parent expects back
     * @param data Strategy-specific execution data (encoded commands)
     */
    function rebalance(
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    // ============ View Functions ============

    /**
     * @notice Get strategy's net asset value in base asset terms
     * @dev Calculates: collateralValue - debtValue
     *      Returns 0 if debt exceeds collateral (should not happen in healthy strategy)
     * @return Net asset value in base asset (e.g., USDC with 6 decimals)
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Get parent vault address
     * @return Address of parent vault (only caller allowed to execute operations)
     */
    function parent() external view returns (address);
}
