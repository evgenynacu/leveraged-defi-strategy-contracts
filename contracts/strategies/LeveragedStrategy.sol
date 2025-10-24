// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SwapHelper.sol";
import "../interfaces/IChildStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LeveragedStrategy
 * @notice Abstract base contract for leveraged yield strategies across lending protocols
 * @dev Provides:
 *      - Command execution framework for multi-step operations
 *      - Swap orchestration via inherited SwapHelper
 *      - Multi-token support for deposits/withdrawals/rebalancing
 *      - Protocol-agnostic leverage mechanics
 *
 * Child implementations must provide protocol-specific methods for:
 * - Supply/withdraw collateral
 * - Borrow/repay debt
 * - Query collateral and debt values
 *
 * IMPORTANT: Reentrancy Protection
 * This contract does NOT include reentrancy guards. Parent vault MUST have
 * nonReentrant modifier on deposit/withdraw/rebalance entry points (see ADR-0007).
 *
 * Related ADRs:
 * - ADR-0008: LeveragedStrategy Architecture
 * - ADR-0006: Child Strategy Interface
 * - ADR-0002: Command-Based Execution
 * - ADR-0007: Reentrancy Protection Strategy
 */
abstract contract LeveragedStrategy is SwapHelper, IChildStrategy {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Percentage denominator (100% = 1e18)
    uint256 internal constant PERCENTAGE_DENOMINATOR = 1e18;

    // ============ Errors ============

    error UnknownCommand(uint8 cmdType);
    error InvalidKeeperCommand(uint8 cmdType);

    // ============ Enums ============

    /**
     * @notice Command types for strategy operations
     * @dev SUPPLY: Supply collateral to lending protocol
     *      WITHDRAW: Withdraw collateral from lending protocol
     *      BORROW: Borrow asset from lending protocol
     *      REPAY: Repay debt to lending protocol
     *      SWAP: Swap tokens via SwapHelper
     */
    enum CommandType {
        SUPPLY,
        WITHDRAW,
        BORROW,
        REPAY,
        SWAP
    }

    /**
     * @notice Command structure for atomic execution
     * @param cmdType Type of command to execute
     * @param data ABI-encoded parameters specific to command type
     */
    struct Command {
        CommandType cmdType;
        bytes data;
    }

    // ============ Immutable State ============

    /// @notice Parent vault address (only caller allowed)
    address public immutable override parent;

    /// @notice Base asset for the strategy (e.g., USDC)
    address public immutable baseAsset;

    // ============ Modifiers ============

    /**
     * @notice Restrict access to parent vault only
     */
    modifier onlyParent() {
        if (msg.sender != parent) revert Unauthorized();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize strategy with parent vault and oracle
     * @param _parent Parent vault address
     * @param _baseAsset Base asset address (e.g., USDC)
     * @param _priceOracle Price oracle address
     */
    constructor(
        address _parent,
        address _baseAsset,
        address _priceOracle
    ) SwapHelper(_priceOracle) {
        if (_parent == address(0)) revert InvalidToken();
        if (_baseAsset == address(0)) revert InvalidToken();

        parent = _parent;
        baseAsset = _baseAsset;
    }

    // ============ IChildStrategy Implementation ============

    /**
     * @notice Deploy assets into leveraged strategy
     * @inheritdoc IChildStrategy
     * @dev No protection needed - all tokens stay in strategy, only swap slippage protected by oracle
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external override onlyParent {
        if (flashLoanToken != address(0)) {
            address[] memory trackedTokens = _trackedTokens();
            if (!_isTokenTracked(trackedTokens, flashLoanToken)) {
                revert InvalidToken();
            }
        }

        // Decode and execute commands
        Command[] memory commands = abi.decode(data, (Command[]));
        _executeCommands(commands);

        // Approve expected tokens for parent collection
        if (flashLoanToken != address(0) && expectedAmount > 0) {
            IERC20(flashLoanToken).forceApprove(parent, expectedAmount);
        }

        emit Deposited(
            depositToken,
            depositAmount,
            flashLoanToken,
            providedAmount,
            expectedAmount
        );
    }

    /**
     * @notice Withdraw from strategy by percentage
     * @inheritdoc IChildStrategy
     * @dev Strategy calculates proportional amounts to withdraw/repay based on percentage
     *      and current protocol state. Keeper only provides liquidity and swap execution,
     *      but cannot manipulate withdrawal amounts.
     */
    function withdraw(
        uint256 percentage,
        address outputToken,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external override onlyParent returns (uint256 actualWithdrawn) {
        if (percentage == 0 || percentage > PERCENTAGE_DENOMINATOR) {
            revert InvalidPercentage();
        }
        if (outputToken == address(0)) {
            revert InvalidToken();
        }

        // Calculate and execute proportional withdrawal
        actualWithdrawn = _executeProportionalWithdraw(
            percentage,
            outputToken,
            flashLoanToken,
            providedAmount,
            expectedAmount,
            data
        );

        // Approve parent to collect withdrawn assets and flash loan repayment
        if (outputToken == flashLoanToken) {
            // Same token: approve sum of both amounts to avoid overwriting
            uint256 totalAmount = actualWithdrawn + expectedAmount;
            if (totalAmount > 0) {
                IERC20(outputToken).forceApprove(parent, totalAmount);
            }
        } else {
            // Different tokens: approve separately
            if (actualWithdrawn > 0) {
                IERC20(outputToken).forceApprove(parent, actualWithdrawn);
            }
            if (flashLoanToken != address(0) && expectedAmount > 0) {
                IERC20(flashLoanToken).forceApprove(parent, expectedAmount);
            }
        }

        emit Withdrawn(
            percentage,
            outputToken,
            actualWithdrawn,
            flashLoanToken,
            providedAmount,
            expectedAmount
        );

        return actualWithdrawn;
    }

    /**
     * @notice Rebalance strategy internally
     * @inheritdoc IChildStrategy
     */
    function rebalance(
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external override onlyParent {
        // Decode and execute commands
        Command[] memory commands = abi.decode(data, (Command[]));
        _executeCommands(commands);

        // Approve flash loan repayment if parent expects something back
        if (flashLoanToken != address(0) && expectedAmount > 0) {
            IERC20(flashLoanToken).forceApprove(parent, expectedAmount);
        }

        emit Rebalanced(
            flashLoanToken,
            providedAmount,
            expectedAmount
        );
    }

    /**
     * @notice Update price oracle address
     * @dev Only callable by parent vault. Use when PriceOracle is upgraded to new version.
     * @param newOracle New price oracle address
     */
    function setOracle(address newOracle) external override onlyParent {
        _setPriceOracle(newOracle);
    }

    /**
     * @notice Get strategy's net asset value in base asset terms
     * @inheritdoc IChildStrategy
     * @dev Calculates total value from:
     *      1. Protocol positions (collateral - debt)
     *      2. Idle tokens on contract balance
     *
     *      Important: Idle balances are tracked separately from protocol positions.
     *      If collateral/debt assets are in tracked tokens list, they represent
     *      PROTOCOL holdings (not idle). Idle = actual balance on this contract.
     */
    function totalAssets() external view override returns (uint256) {
        address collateralAsset = _getCollateralAsset();
        address debtAsset = _getDebtAsset();

        // Calculate total value in USD
        uint256 totalValueUsd;

        // 1. Add idle token balances (tokens sitting on this contract)
        address[] memory tokens = _trackedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                totalValueUsd += priceOracle.getUsdValue(tokens[i], balance);
            }
        }

        // 2. Add protocol collateral and subtract debt (single external call)
        (uint256 collateralAmount, uint256 debtAmount) = _getPositionAmounts();

        if (collateralAmount > 0) {
            totalValueUsd += priceOracle.getUsdValue(collateralAsset, collateralAmount);
        }

        if (debtAmount > 0) {
            uint256 debtUsd = priceOracle.getUsdValue(debtAsset, debtAmount);
            if (totalValueUsd <= debtUsd) {
                return 0;
            }
            totalValueUsd -= debtUsd;
        }

        // Convert USD value to base asset amount
        uint256 baseAssetDecimals = 10 ** IERC20Metadata(baseAsset).decimals();
        uint256 baseAssetPriceUsd = priceOracle.getUsdValue(baseAsset, baseAssetDecimals);
        require(baseAssetPriceUsd > 0, "Base price zero");

        return (totalValueUsd * baseAssetDecimals) / baseAssetPriceUsd;
    }

    // ============ Command Execution ============

    /**
     * @notice Execute sequence of commands atomically
     * @dev All commands must succeed or entire transaction reverts
     * @param commands Array of commands to execute
     */
    function _executeCommands(Command[] memory commands) internal {
        for (uint256 i = 0; i < commands.length; i++) {
            Command memory cmd = commands[i];

            if (cmd.cmdType == CommandType.SUPPLY) {
                (address asset, uint256 amount) = abi.decode(cmd.data, (address, uint256));
                _supply(asset, amount);

            } else if (cmd.cmdType == CommandType.WITHDRAW) {
                (address asset, uint256 amount) = abi.decode(cmd.data, (address, uint256));
                _withdraw(asset, amount);

            } else if (cmd.cmdType == CommandType.BORROW) {
                (address asset, uint256 amount) = abi.decode(cmd.data, (address, uint256));
                _borrow(asset, amount);

            } else if (cmd.cmdType == CommandType.REPAY) {
                (address asset, uint256 amount) = abi.decode(cmd.data, (address, uint256));
                _repay(asset, amount);

            } else if (cmd.cmdType == CommandType.SWAP) {
                (
                    SwapRouter router,
                    address tokenIn,
                    uint256 amountIn,
                    address tokenOut,
                    uint256 minAmountOut,
                    uint256 maxOracleSlippageBps,
                    bytes memory swapData
                ) = abi.decode(
                    cmd.data,
                    (SwapRouter, address, uint256, address, uint256, uint256, bytes)
                );

                // Execute swap
                _swap(
                    router,
                    tokenIn,
                    amountIn,
                    tokenOut,
                    minAmountOut,
                    maxOracleSlippageBps,
                    swapData
                );
            } else {
                // Revert on unknown command type to prevent configuration errors
                revert UnknownCommand(uint8(cmd.cmdType));
            }
        }
    }

    // ============ Internal Helpers ============

    /**
     * @notice Execute proportional withdrawal from protocol
     * @param percentage Percentage to withdraw (1e18 = 100%)
     * @param outputToken Desired output token
     * @param flashLoanToken Flash loan token (if any)
     * @param providedAmount Amount provided by parent
     * @param expectedAmount Amount parent expects back
     * @param data Keeper data containing swap commands (must not contain protocol commands)
     * @return actualWithdrawn Amount actually withdrawn in outputToken
     */
    function _executeProportionalWithdraw(
        uint256 percentage,
        address outputToken,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) private returns (uint256 actualWithdrawn) {
        // Take snapshots of idle balances to protect them
        // NOTE: This snapshot does not include flashLoanToken if parent already transferred it
        IdleSnapshot memory idlesBefore = _snapshotIdleBalances(flashLoanToken, providedAmount);
        _verifyTokenTracked(outputToken, idlesBefore);
        _verifyTokenTracked(flashLoanToken, idlesBefore);

        // Execute protocol operations (repay debt, withdraw collateral)
        _executeProtocolWithdraw(percentage);

        // Execute keeper's swap commands
        if (data.length > 0) {
            Command[] memory keeperCommands = abi.decode(data, (Command[]));
            _validateKeeperCommands(keeperCommands, idlesBefore.tokens, flashLoanToken, outputToken);
            _executeCommands(keeperCommands);
        }

        // Validate proportional withdrawal of idle tokens
        // Account for flash loan (providedAmount/expectedAmount)
        actualWithdrawn = _validateIdleBalances(idlesBefore, percentage, flashLoanToken, expectedAmount, outputToken);
    }

    function _verifyTokenTracked(address token, IdleSnapshot memory snapshot) pure internal {
        bool tracked = token == address(0)
            ? true
            : _isTokenTracked(snapshot.tokens, token);

        if (!tracked) revert InvalidToken();
    }

    /**
     * @notice Struct to hold idle balance snapshots
     */
    struct IdleSnapshot {
        address[] tokens;
        uint256[] balances;
    }

    /**
     * @notice Snapshot current idle token balances for all tracked tokens. This does not included provided flash loan
     */
    function _snapshotIdleBalances(address flashLoanToken, uint256 providedAmount) private view returns (IdleSnapshot memory snapshot) {
        address[] memory tokens = _trackedTokens();
        uint256 length = tokens.length;
        uint256[] memory balances = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
            if (flashLoanToken == tokens[i]) {
                balances[i] -= providedAmount;
            }
        }

        return IdleSnapshot(tokens, balances);
    }

    /**
     * @notice Execute protocol-level withdraw operations
     * @dev Calculates safe withdrawal amounts considering health factor and LTV.
     *      Strategy may need to repay more debt than proportional to safely withdraw collateral.
     */
    function _executeProtocolWithdraw(uint256 percentage) private {
        address collateralAsset = _getCollateralAsset();
        address debtAsset = _getDebtAsset();

        // Get both amounts in a single external call
        (uint256 collateralAmount, uint256 debtAmount) = _getPositionAmounts();

        // Calculate safe withdrawal amounts (may adjust debt repayment upward)
        (uint256 repayAmount, uint256 withdrawAmount) = _calculateSafeWithdrawAmounts(
            collateralAmount,
            debtAmount,
            percentage
        );

        if (repayAmount > 0) {
            _repay(debtAsset, repayAmount);
        }

        if (withdrawAmount > 0) {
            _withdraw(collateralAsset, withdrawAmount);
        }
    }

    /**
     * @notice Validate that idle balances remain proportional after withdrawal
     * @dev Accounts for flash loan tokens
     *
     * Logic:
     * - Snapshot doesn't include flashLoanToken (if parent transferred it already)
     * - We need to ensure (100-X)% of "real" idle tokens remain
     * - "Real" idle = snapshot - provided + expected
     *
     * Formula:
     * MinRemaining = (SnapshotBalance - ProvidedAmount) * (100-X)% + ExpectedAmount
     *
     * @param snapshot Idle balances snapshot (doesn't include flash loan if already transferred)
     * @param percentage Withdrawal percentage
     * @param flashLoanToken Flash loan token (address(0) if none)
     * @param expectedAmount Amount parent expects back
     */
    function _validateIdleBalances(
        IdleSnapshot memory snapshot,
        uint256 percentage,
        address flashLoanToken,
        uint256 expectedAmount,
        address outputToken
    ) private view returns (uint256 actualWithdrawn) {
        actualWithdrawn = 0;
        uint256 remainingPercentage = PERCENTAGE_DENOMINATOR - percentage;

        (uint256 flashIndex, bool hasFlash) = _findTokenIndex(snapshot.tokens, flashLoanToken);

        for (uint256 i = 0; i < snapshot.tokens.length; i++) {
            address token = snapshot.tokens[i];
            uint256 balanceBefore = snapshot.balances[i];

            uint256 expectedAdj = 0;

            if (hasFlash && i == flashIndex) {
                expectedAdj = expectedAmount;
            }

            uint256 minBalance = (balanceBefore * remainingPercentage) / PERCENTAGE_DENOMINATOR;
            minBalance += expectedAdj;

            uint256 currentBalance = IERC20(token).balanceOf(address(this));
            if (currentBalance < minBalance) {
                revert InvalidAmount();
            }
            if (outputToken == token) {
                // actualWithdrawn = withdrawn from protocol + swaps - expected to return
                // currentBalance includes: balanceBefore + withdrawn + swaps
                // We need to subtract: balanceBefore (original idle) + expectedAdj (what parent expects back)
                if (currentBalance >= balanceBefore + expectedAdj) {
                    actualWithdrawn = currentBalance - balanceBefore - expectedAdj;
                } else {
                    actualWithdrawn = 0;
                }
            }
        }
    }

    /**
     * @notice Validate keeper's commands to ensure no protocol operations
     * @dev Keeper can only provide SWAP commands during withdrawal
     *      SUPPLY, WITHDRAW, BORROW, REPAY are executed by strategy itself
     * @param commands Commands to validate
     */
    function _validateKeeperCommands(
        Command[] memory commands,
        address[] memory trackedTokens,
        address flashLoanToken,
        address outputToken
    ) private pure {
        for (uint256 i = 0; i < commands.length; i++) {
            Command memory command = commands[i];

            if (
                command.cmdType == CommandType.SUPPLY ||
                command.cmdType == CommandType.WITHDRAW ||
                command.cmdType == CommandType.BORROW ||
                command.cmdType == CommandType.REPAY
            ) {
                revert InvalidKeeperCommand(uint8(command.cmdType));
            }

            if (command.cmdType == CommandType.SWAP) {
                (, address tokenIn,, address tokenOut,,,) = abi.decode(command.data, (SwapRouter, address, uint256, address, uint256, uint256, bytes));

                if (!_isTokenTracked(trackedTokens, tokenIn) && tokenIn != flashLoanToken && tokenIn != outputToken) {
                    revert InvalidToken();
                }

                if (!_isTokenTracked(trackedTokens, tokenOut) && tokenOut != flashLoanToken && tokenOut != outputToken) {
                    revert InvalidToken();
                }
            }
        }
    }

    /**
     * @notice Validate idle balances after rebalance operations
     * @dev Rebalance should not decrease idle balances (except when returning flash loan).
     *      This prevents keeper from stealing idle tokens during rebalance.
     *
     * Logic:
     * - For non-flash-loan tokens: balance must not decrease
     * - For flash loan token: RealBefore = SnapshotBefore - providedAmount
     *   - Must have: CurrentBalance >= RealBefore + expectedAmount
     *   - This ensures: we kept our original idle + have enough to return flash loan
     *
     * @param before Idle balances before rebalance
     * @param flashLoanToken Flash loan token (if any)
     * @param providedAmount Amount provided by parent
     * @param expectedAmount Amount parent expects back
     */
    /**
     * @notice Helper to find token index in tracked list
     */
    function _findTokenIndex(address[] memory tokens, address token)
        private
        pure
        returns (uint256 index, bool found)
    {
        if (token == address(0)) {
            return (0, false);
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return (i, true);
            }
        }
        return (0, false);
    }

    function _isTokenTracked(address[] memory tokens, address token) private pure returns (bool) {
        if (token == address(0)) return false;
        (, bool found) = _findTokenIndex(tokens, token);
        return found;
    }

    /**
     * @notice List of tokens that must remain proportional during operations
     * @dev Default implementation tracks base asset, collateral asset, and debt asset.
     *      Child strategies can override to extend the set (e.g., reward tokens).
     */
    function _trackedTokens() internal view virtual returns (address[] memory tokens) {
        address c = _getCollateralAsset();
        address d = _getDebtAsset();

        // All three are the same token
        if (baseAsset == c && baseAsset == d) {
            tokens = new address[](1);
            tokens[0] = baseAsset;
            return tokens;
        }

        // Two tokens are the same (any combination)
        if (baseAsset == c || baseAsset == d || c == d) {
            tokens = new address[](2);
            tokens[0] = baseAsset;
            tokens[1] = (baseAsset == c) ? d : c;
            return tokens;
        }

        // All three are different
        tokens = new address[](3);
        tokens[0] = baseAsset;
        tokens[1] = c;
        tokens[2] = d;
    }


    // ============ Abstract Methods (Protocol-Specific) ============

    /**
     * @notice Supply collateral to lending protocol
     * @param asset Asset address to supply
     * @param amount Amount to supply
     */
    function _supply(address asset, uint256 amount) internal virtual;

    /**
     * @notice Withdraw collateral from lending protocol
     * @param asset Asset address to withdraw
     * @param amount Amount to withdraw (type(uint256).max for full amount)
     * @return actualWithdrawn Actual amount withdrawn
     */
    function _withdraw(address asset, uint256 amount)
        internal
        virtual
        returns (uint256 actualWithdrawn);

    /**
     * @notice Borrow asset from lending protocol
     * @param asset Asset address to borrow
     * @param amount Amount to borrow
     */
    function _borrow(address asset, uint256 amount) internal virtual;

    /**
     * @notice Repay debt to lending protocol
     * @param asset Asset address to repay
     * @param amount Amount to repay (type(uint256).max for full debt)
     * @return actualRepaid Actual amount repaid
     */
    function _repay(address asset, uint256 amount)
        internal
        virtual
        returns (uint256 actualRepaid);

    /**
     * @notice Get collateral asset address
     * @dev Returns the single collateral asset used in the strategy
     * @return Collateral asset address
     */
    function _getCollateralAsset() internal view virtual returns (address);

    /**
     * @notice Get debt asset address
     * @dev Returns the single debt asset used in the strategy
     * @return Debt asset address
     */
    function _getDebtAsset() internal view virtual returns (address);

    /**
     * @notice Get position amounts from lending protocol (collateral and debt)
     * @dev Returns amounts in native token decimals (NOT converted to base asset).
     *      This method should make a single external call to fetch both values
     *      to save gas compared to calling _getCollateralAmount() and _getDebtAmount() separately.
     * @return collateralAmount Amount of collateral in native token decimals
     * @return debtAmount Amount of debt in native token decimals
     */
    function _getPositionAmounts() internal view virtual returns (uint256 collateralAmount, uint256 debtAmount);

    /**
     * @notice Calculate safe withdrawal amounts considering protocol constraints
     * @dev Default implementation adds small buffer to debt repayment:
     *      - Debt: (totalDebt * (percentage + 1)) / DENOMINATOR
     *      - Collateral: (totalCollateral * percentage) / DENOMINATOR
     *
     *      The +1 adds 1/1e18 extra to debt repayment to maintain safe health factor.
     *      Child strategies can override for protocol-specific logic.
     *
     * @param collateralAmount Total collateral in protocol
     * @param debtAmount Total debt in protocol
     * @param percentage Percentage to withdraw (1e18 = 100%)
     * @return repayAmount Amount of debt to repay (slightly > proportional for safety)
     * @return withdrawAmount Amount of collateral to withdraw
     */
    function _calculateSafeWithdrawAmounts(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 percentage
    ) internal view virtual returns (uint256 repayAmount, uint256 withdrawAmount) {
        // Collateral: simple proportional withdrawal
        withdrawAmount = (collateralAmount * percentage) / PERCENTAGE_DENOMINATOR;

        // Debt: add +1 to percentage to repay slightly more (1/1e18 extra)
        // This ensures health factor remains safe after withdrawal
        repayAmount = (debtAmount * (percentage + 1)) / PERCENTAGE_DENOMINATOR;
    }
}
