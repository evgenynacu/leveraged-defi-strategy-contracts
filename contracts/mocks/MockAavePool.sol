// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockAavePool
 * @notice Mock implementation of Aave V3 Pool for testing
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    // User collateral balances (aToken)
    mapping(address => mapping(address => uint256)) public aTokenBalance;

    // User debt balances
    mapping(address => mapping(address => uint256)) public debtBalance;

    address public immutable addressesProvider;

    constructor(address _addressesProvider) {
        addressesProvider = _addressesProvider;
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /*referralCode*/
    ) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        aTokenBalance[onBehalfOf][asset] += amount;
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(aTokenBalance[msg.sender][asset] >= amount, "Insufficient collateral");
        aTokenBalance[msg.sender][asset] -= amount;
        IERC20(asset).safeTransfer(to, amount);
        return amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 /*interestRateMode*/,
        uint16 /*referralCode*/,
        address onBehalfOf
    ) external {
        debtBalance[onBehalfOf][asset] += amount;
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 /*interestRateMode*/,
        address onBehalfOf
    ) external returns (uint256) {
        uint256 debt = debtBalance[onBehalfOf][asset];
        uint256 repayAmount = amount > debt ? debt : amount;

        debtBalance[onBehalfOf][asset] -= repayAmount;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);

        return repayAmount;
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return addressesProvider;
    }

    // Helper functions for testing
    function getATokenBalance(address user, address asset) external view returns (uint256) {
        return aTokenBalance[user][asset];
    }

    function getDebtBalance(address user, address asset) external view returns (uint256) {
        return debtBalance[user][asset];
    }
}
