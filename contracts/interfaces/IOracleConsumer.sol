// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IPriceOracle.sol";

/**
 * @title IOracleConsumer
 * @notice Interface for contracts that consume price oracle data
 * @dev Used by Parent Vault and Child Strategies to enable oracle updates
 */
interface IOracleConsumer {
    /**
     * @notice Update the price oracle address
     * @dev Only callable by admin/owner
     * @param newOracle New price oracle address
     */
    function setOracle(address newOracle) external;

    /**
     * @notice Get current price oracle address
     * @return oracle Address of the current price oracle
     */
    function oracle() external view returns (IPriceOracle oracle);

    /**
     * @notice Event emitted when oracle is updated
     * @param oldOracle Previous oracle address
     * @param newOracle New oracle address
     */
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
}
