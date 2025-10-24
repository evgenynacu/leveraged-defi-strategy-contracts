// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockAavePoolAddressesProvider
 * @notice Mock implementation of Aave V3 PoolAddressesProvider for testing
 */
contract MockAavePoolAddressesProvider {
    address public poolDataProvider;

    constructor(address _poolDataProvider) {
        poolDataProvider = _poolDataProvider;
    }

    function getPoolDataProvider() external view returns (address) {
        return poolDataProvider;
    }

    function setPoolDataProvider(address _poolDataProvider) external {
        poolDataProvider = _poolDataProvider;
    }
}
