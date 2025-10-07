// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle that provides USD valuations for various tokens
 * @dev Supports both standard ERC20 tokens via Chainlink and PT tokens via Pendle Oracle
 */
interface IPriceOracle {
    /**
     * @notice Get USD value of token amount
     * @param token Token address to price
     * @param amount Amount of tokens (in token's native decimals)
     * @return usdValue Value in USD with 8 decimal places
     */
    function getUsdValue(address token, uint256 amount) external view returns (uint256 usdValue);

    /**
     * @notice Add or update Chainlink price feed for a token
     * @param token Token address
     * @param priceFeed Chainlink price feed address
     */
    function addPriceFeed(address token, address priceFeed) external;

    /**
     * @notice Add PT token configuration
     * @param ptToken PT token address
     * @param market Pendle market address
     * @param useSy Whether to use SY rate (true) or Asset rate (false)
     * @param underlyingToken Underlying asset token address
     */
    function addPTToken(
        address ptToken,
        address market,
        bool useSy,
        address underlyingToken
    ) external;

    /**
     * @notice Get price feed address for a token
     * @param token Token address
     * @return priceFeed Address of the Chainlink price feed
     */
    function getPriceFeed(address token) external view returns (address priceFeed);

    /**
     * @notice Get PT token market address
     * @param ptToken PT token address
     * @return market Pendle market address
     */
    function getPTMarket(address ptToken) external view returns (address market);

    /**
     * @notice Check if token is a registered PT token
     * @param token Token address to check
     * @return isPT True if token is a registered PT token
     */
    function isPTToken(address token) external view returns (bool isPT);

    // Events
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event PTTokenAdded(address indexed ptToken, address indexed market, address indexed underlying);
}
