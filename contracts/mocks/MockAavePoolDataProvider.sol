// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockAavePoolDataProvider
 * @notice Mock implementation of Aave V3 PoolDataProvider for testing
 */
contract MockAavePoolDataProvider {
    address public immutable pool;

    constructor(address _pool) {
        pool = _pool;
    }

    function getUserReserveData(address asset, address user)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            uint256 principalStableDebt,
            uint256 scaledVariableDebt,
            uint256 stableBorrowRate,
            uint256 liquidityRate,
            uint40 stableRateLastUpdated,
            bool usageAsCollateralEnabled
        )
    {
        // Call the pool to get balances
        currentATokenBalance = IMockAavePool(pool).getATokenBalance(user, asset);
        currentVariableDebt = IMockAavePool(pool).getDebtBalance(user, asset);

        // Other values are not used in our tests
        currentStableDebt = 0;
        principalStableDebt = 0;
        scaledVariableDebt = 0;
        stableBorrowRate = 0;
        liquidityRate = 0;
        stableRateLastUpdated = 0;
        usageAsCollateralEnabled = true;
    }
}

// Interface for IMockAavePool
interface IMockAavePool {
    function getATokenBalance(address user, address asset) external view returns (uint256);
    function getDebtBalance(address user, address asset) external view returns (uint256);
}
