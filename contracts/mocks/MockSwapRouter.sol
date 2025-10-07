// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockSwapRouter
 * @notice Mock DEX router for testing swap functionality
 * @dev Simulates token swaps with configurable slippage
 */
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    /// @notice Slippage applied to swaps (in basis points, e.g., 30 = 0.3%)
    uint256 public slippageBps;

    /// @notice Whether to simulate a reentrancy attack
    bool public shouldReenter;

    /// @notice Target contract for reentrancy
    address public reentrancyTarget;

    /// @notice Reentrancy call data
    bytes public reentrancyCalldata;

    event SwapExecuted(address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    constructor() {
        slippageBps = 0; // No slippage by default
    }

    /**
     * @notice Set slippage for simulated swaps
     * @param _slippageBps Slippage in basis points
     */
    function setSlippage(uint256 _slippageBps) external {
        slippageBps = _slippageBps;
    }

    /**
     * @notice Configure reentrancy attack
     * @param _target Target contract to reenter
     * @param _calldata Calldata for reentrancy call
     */
    function setReentrancy(address _target, bytes calldata _calldata) external {
        shouldReenter = true;
        reentrancyTarget = _target;
        reentrancyCalldata = _calldata;
    }

    /**
     * @notice Disable reentrancy attack
     */
    function disableReentrancy() external {
        shouldReenter = false;
    }

    /**
     * @notice Simulate a token swap via fallback
     * @dev Expects calldata: abi.encode(tokenIn, amountIn, tokenOut, expectedOut)
     */
    fallback() external {
        // Decode swap parameters
        (address tokenIn, uint256 amountIn, address tokenOut, uint256 expectedOut) =
            abi.decode(msg.data, (address, uint256, address, uint256));

        // Transfer tokens from caller
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Attempt reentrancy if configured
        if (shouldReenter) {
            (bool success, ) = reentrancyTarget.call(reentrancyCalldata);
            require(success, "Reentrancy failed");
        }

        // Calculate output with slippage
        uint256 amountOut = (expectedOut * (10000 - slippageBps)) / 10000;

        // Transfer output tokens to caller
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit SwapExecuted(tokenIn, amountIn, tokenOut, amountOut);
    }

    /**
     * @notice Fund router with tokens for testing
     */
    function fundRouter(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
