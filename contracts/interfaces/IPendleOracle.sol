// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPendleOracle
 * @notice Interface for Pendle Oracle to get PT token pricing
 */
interface IPendleOracle {
    /**
     * @notice Get PT to Asset exchange rate
     * @param market Pendle market address
     * @param duration TWAP duration (0 for spot price)
     * @return rate Exchange rate with 18 decimals
     */
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256 rate);

    /**
     * @notice Get PT to SY exchange rate
     * @param market Pendle market address
     * @param duration TWAP duration (0 for spot price)
     * @return rate Exchange rate with 18 decimals
     */
    function getPtToSyRate(address market, uint32 duration) external view returns (uint256 rate);
}
