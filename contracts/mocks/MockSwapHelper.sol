// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../strategies/SwapHelper.sol";

/**
 * @title MockSwapHelper
 * @notice Test implementation of SwapHelper that exposes internal functions
 * @dev Used for testing SwapHelper functionality in isolation.
 *      Includes ReentrancyGuard to simulate entry-point protection
 *      as per ADR-0007: Reentrancy Protection Strategy.
 */
contract MockSwapHelper is SwapHelper, ReentrancyGuard {

    /**
     * @notice Constructor
     * @param _priceOracle Price oracle address
     */
    constructor(address _priceOracle) SwapHelper(_priceOracle) {}

    /**
     * @notice Public wrapper for _swap to enable testing
     * @dev Includes nonReentrant to simulate entry-point protection (ADR-0007)
     */
    function swap(
        SwapRouter router,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxOracleSlippageBps,
        bytes calldata swapData
    ) external nonReentrant returns (uint256) {
        return _swap(
            router,
            tokenIn,
            amountIn,
            tokenOut,
            minAmountOut,
            maxOracleSlippageBps,
            swapData
        );
    }

    /**
     * @notice Public wrapper for _setSwapRouter to enable testing
     */
    function setSwapRouter(SwapRouter router, address routerAddress) external {
        _setSwapRouter(router, routerAddress);
    }

    /**
     * @notice Update the price oracle address
     * @dev Public implementation for testing (no access control in mock)
     * @param newOracle New price oracle address
     */
    function setOracle(address newOracle) external override {
        _setPriceOracle(newOracle);
    }

    /**
     * @notice Helper function to receive tokens for testing
     */
    function depositTokens(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}
