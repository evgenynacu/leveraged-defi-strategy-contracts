// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IOracleConsumer.sol";

/**
 * @title SwapHelper
 * @notice Base contract providing secure token swap functionality for child strategies
 * @dev Implements best practices for swap security:
 *      - Precise approvals (exact amount needed, not max)
 *      - Approval cleanup after swap
 *      - Oracle-based slippage protection
 *      - Comprehensive event logging for audit trail
 *
 * IMPORTANT: Reentrancy Protection
 * This contract does NOT include reentrancy guards. Callers MUST ensure reentrancy
 * protection at the entry point level (see ADR-0007). All external functions that
 * call _swap must be protected with nonReentrant modifier.
 *
 * Security features:
 * - SR-002.3: Command validation with slippage limits (reentrancy guard at caller level)
 * - SR-009.1: Event logging for audit trail (USD values for all flows)
 * - SR-010.2: Slippage protection for all DEX operations
 * - SR-010.4: MEV and front-running protection via oracle-based slippage checks
 *
 * Related ADRs:
 * - ADR-0006: Child Strategy Interface
 * - ADR-0007: Reentrancy Protection Strategy
 */
abstract contract SwapHelper is IOracleConsumer {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Basis points denominator (100% = 10000)
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    // ============ Enums ============

    /**
     * @notice Supported swap routers
     * @dev Add new routers here as they are integrated
     */
    enum SwapRouter {
        KyberSwap,
        Odos,
        Pendle
    }

    // ============ State Variables ============

    /// @notice Price oracle for slippage validation
    IPriceOracle public priceOracle;

    /// @notice Swap router addresses
    mapping(SwapRouter => address) public swapRouters;

    // ============ Events ============

    /**
     * @notice Emitted when a token swap is executed
     * @param router Swap router used
     * @param tokenIn Input token address
     * @param amountIn Amount of input token
     * @param tokenOut Output token address
     * @param amountOut Actual amount of output token received
     * @param minAmountOut Minimum expected output amount (from keeper)
     * @param usdValueIn USD value of input tokens (for audit trail)
     * @param usdValueOut USD value of output tokens (for audit trail)
     */
    event SwapExecuted(
        SwapRouter indexed router,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        uint256 minAmountOut,
        uint256 usdValueIn,
        uint256 usdValueOut
    );

    /**
     * @notice Emitted when swap router address is updated
     * @param router Router enum identifier
     * @param oldAddress Previous router address
     * @param newAddress New router address
     */
    event SwapRouterUpdated(
        SwapRouter indexed router,
        address indexed oldAddress,
        address indexed newAddress
    );

    // Note: OracleUpdated event is inherited from IOracleConsumer

    // ============ Errors ============

    error InvalidRouter();
    error InvalidToken();
    error InvalidAmount();
    error ZeroAddress();
    error SlippageTooHigh(uint256 actual, uint256 minimum);
    error OracleSlippageCheckFailed(uint256 actual, uint256 expected, uint256 maxSlippageBps);
    error SwapFailed(address router, string reason);
    error ApprovalFailed(address token, address spender);

    // ============ Constructor ============

    /**
     * @notice Initialize SwapHelper with price oracle
     * @param _priceOracle Price oracle address
     */
    constructor(address _priceOracle) {
        if (_priceOracle == address(0)) revert ZeroAddress();
        priceOracle = IPriceOracle(_priceOracle);
    }

    // ============ Internal Functions ============

    /**
     * @notice Execute a token swap with comprehensive security checks
     * @dev Implements:
     *      1. Calculate USD value of input tokens (before swap)
     *      2. Precise approval (exact amount, not max)
     *      3. Swap execution via external call
     *      4. Calculate USD value of output tokens (after swap)
     *      5. Validate slippage: USD_out >= USD_in * (1 - maxOracleSlippageBps)
     *      6. Validate keeper's minAmountOut
     *      7. Approval cleanup
     *      8. Event logging with both USD values
     *
     * SECURITY: This function performs external calls with active token approvals.
     * Caller MUST have reentrancy protection (nonReentrant modifier).
     *
     * @param router Swap router to use
     * @param tokenIn Input token address
     * @param amountIn Amount of input token to swap
     * @param tokenOut Output token address
     * @param minAmountOut Minimum acceptable output amount (from keeper)
     * @param maxOracleSlippageBps Maximum acceptable slippage in oracle valuation (basis points)
     * @param swapData Router-specific swap calldata
     * @return amountOut Actual amount of output token received
     */
    function _swap(
        SwapRouter router,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxOracleSlippageBps,
        bytes memory swapData
    ) internal returns (uint256 amountOut) {
        // Input validation
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidToken();
        if (amountIn == 0 || minAmountOut == 0) revert InvalidAmount();
        if (maxOracleSlippageBps > BPS_DENOMINATOR) revert InvalidAmount();

        address routerAddress = swapRouters[router];
        if (routerAddress == address(0)) revert InvalidRouter();

        // Calculate USD value of input tokens BEFORE swap
        uint256 usdValueIn = priceOracle.getUsdValue(tokenIn, amountIn);

        // Execute the swap and get output amount
        amountOut = _executeSwap(
            tokenIn,
            amountIn,
            tokenOut,
            routerAddress,
            swapData
        );

        // Validate output against keeper's minimum
        if (amountOut < minAmountOut) {
            revert SlippageTooHigh(amountOut, minAmountOut);
        }

        // Calculate USD value of output tokens and validate oracle slippage
        uint256 usdValueOut = priceOracle.getUsdValue(tokenOut, amountOut);
        uint256 minAcceptableUsdValue = (usdValueIn * (BPS_DENOMINATOR - maxOracleSlippageBps)) / BPS_DENOMINATOR;

        if (usdValueOut < minAcceptableUsdValue) {
            revert OracleSlippageCheckFailed(usdValueOut, minAcceptableUsdValue, maxOracleSlippageBps);
        }

        // Clean up approval (security best practice)
        _cleanupApproval(tokenIn, routerAddress);

        // Emit event for audit trail
        emit SwapExecuted(
            router,
            tokenIn,
            amountIn,
            tokenOut,
            amountOut,
            minAmountOut,
            usdValueIn,
            usdValueOut
        );

        return amountOut;
    }

    /**
     * @notice Execute the actual swap
     * @dev Separated to avoid stack too deep error
     */
    function _executeSwap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        address routerAddress,
        bytes memory swapData
    ) private returns (uint256 amountOut) {
        // Get balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // Approve exact amount needed (not max) for security
        IERC20(tokenIn).safeIncreaseAllowance(routerAddress, amountIn);

        // Execute swap
        (bool success, bytes memory returnData) = routerAddress.call(swapData);
        if (!success) {
            string memory reason = _getRevertMsg(returnData);
            revert SwapFailed(routerAddress, reason);
        }

        // Calculate actual output
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;

        return amountOut;
    }

    /**
     * @notice Clean up token approvals
     * @dev Separated to avoid stack too deep error
     */
    function _cleanupApproval(address token, address spender) private {
        uint256 remainingAllowance = IERC20(token).allowance(address(this), spender);
        if (remainingAllowance > 0) {
            IERC20(token).safeDecreaseAllowance(spender, remainingAllowance);
        }
    }

    /**
     * @notice Set swap router address
     * @dev Should be called in constructor or by owner
     * @param router Router enum identifier
     * @param routerAddress Router contract address
     */
    function _setSwapRouter(SwapRouter router, address routerAddress) internal {
        if (routerAddress == address(0)) revert ZeroAddress();

        address oldAddress = swapRouters[router];
        swapRouters[router] = routerAddress;

        emit SwapRouterUpdated(router, oldAddress, routerAddress);
    }

    /**
     * @notice Get current price oracle address
     * @return oracle Address of the current price oracle
     */
    function oracle() external view override returns (IPriceOracle) {
        return priceOracle;
    }

    /**
     * @notice Update the price oracle address
     * @dev Must be implemented by child contracts with proper access control
     * @param newOracle New price oracle address
     */
    function setOracle(address newOracle) external virtual override;

    /**
     * @notice Set price oracle address (internal helper)
     * @dev Called by child contracts to update oracle when new version is deployed
     * @param newOracle New price oracle address
     */
    function _setPriceOracle(address newOracle) internal {
        if (newOracle == address(0)) revert ZeroAddress();

        address oldOracle = address(priceOracle);
        priceOracle = IPriceOracle(newOracle);

        emit OracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Extract revert reason from failed call
     * @param returnData Return data from failed call
     * @return Revert reason string
     */
    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        // If the returnData length is less than 68, then the transaction failed silently
        if (returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash (first 4 bytes)
            returnData := add(returnData, 0x04)
        }

        return abi.decode(returnData, (string)); // All that remains is the revert string
    }
}
