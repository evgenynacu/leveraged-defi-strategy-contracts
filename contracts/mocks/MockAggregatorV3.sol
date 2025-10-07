// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockAggregatorV3
 * @notice Mock Chainlink price feed for testing
 */
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(uint8 decimals_, int256 initialPrice) {
        _decimals = decimals_;
        _price = initialPrice;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Aggregator V3";
    }

    function version() external pure returns (uint256) {
        return 3;
    }

    function getRoundData(uint80 _roundId_)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId_, _price, _updatedAt, _updatedAt, _roundId_);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    // Test helper functions
    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }
}
