// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPendleOracle.sol";

/**
 * @title MockPendleOracle
 * @notice Mock Pendle Oracle for testing PT token pricing
 */
contract MockPendleOracle is IPendleOracle {
    // Market => PT to Asset rate
    mapping(address => uint256) private ptToAssetRates;

    // Market => PT to SY rate
    mapping(address => uint256) private ptToSyRates;

    /**
     * @notice Get PT to Asset exchange rate
     * @param market Pendle market address
     * @param duration TWAP duration (ignored in mock)
     * @return rate Exchange rate with 18 decimals
     */
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256 rate) {
        uint256 storedRate = ptToAssetRates[market];
        return storedRate > 0 ? storedRate : 1e18; // Default 1:1 if not set
    }

    /**
     * @notice Get PT to SY exchange rate
     * @param market Pendle market address
     * @param duration TWAP duration (ignored in mock)
     * @return rate Exchange rate with 18 decimals
     */
    function getPtToSyRate(address market, uint32 duration) external view returns (uint256 rate) {
        uint256 storedRate = ptToSyRates[market];
        return storedRate > 0 ? storedRate : 1e18; // Default 1:1 if not set
    }

    // Test helper functions

    /**
     * @notice Set PT to Asset rate for a market
     * @param market Market address
     * @param rate Exchange rate (18 decimals)
     */
    function setPtToAssetRate(address market, uint256 rate) external {
        ptToAssetRates[market] = rate;
    }

    /**
     * @notice Set PT to SY rate for a market
     * @param market Market address
     * @param rate Exchange rate (18 decimals)
     */
    function setPtToSyRate(address market, uint256 rate) external {
        ptToSyRates[market] = rate;
    }
}
