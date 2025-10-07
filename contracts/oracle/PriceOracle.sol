// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IPendleOracle.sol";

/**
 * @title PriceOracle
 * @notice Price oracle for token valuation using Chainlink and Pendle Oracle
 * @dev Non-upgradeable contract - can be replaced entirely if needed
 *
 * Key features:
 * - Supports standard ERC20 tokens via Chainlink price feeds
 * - Supports PT tokens via Pendle Oracle integration
 * - Returns USD values with 8 decimal precision
 * - Uses period=0 for PT tokens (spot pricing) per ADR-0004
 * - Stateless pricing logic - safe to replace without impacting vaults
 *
 * Design rationale:
 * - No upgradeability needed: oracle doesn't hold funds or critical state
 * - Vaults/strategies can update oracle address via admin function
 * - Simpler deployment and auditing without proxy complexity
 *
 * Related Requirements:
 * - TR-002.2: Oracle Integration
 * - SR-005: Oracle Security
 * - ADR-0004: NAV Calculation Method
 */
contract PriceOracle is Ownable, IPriceOracle {

    // ============ Constants ============

    /// @notice USD value decimals (Chainlink standard)
    uint8 public constant DECIMALS = 8;

    /// @notice WAD scale for fixed-point math (1e18)
    uint256 private constant WAD = 1e18;

    /// @notice Maximum age for price data (24 hours)
    uint256 private constant MAX_PRICE_AGE = 24 hours;

    // ============ Structs ============

    /**
     * @notice PT token configuration
     * @param useSy Whether to use SY rate (true) or Asset rate (false)
     * @param token Underlying asset or SY token address
     */
    struct PTInfo {
        bool useSy;
        address token;
    }

    // ============ State Variables ============

    /// @notice Pendle Oracle address (Ethereum Mainnet)
    address public pendleOracle;

    /// @notice Chainlink price feeds for tokens
    mapping(address => address) public priceFeeds;

    /// @notice PT token to Pendle market mapping
    mapping(address => address) public ptToMarket;

    /// @notice PT token to underlying asset info
    mapping(address => PTInfo) public ptToUnderlying;

    // ============ Events ============

    event PendleOracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ============ Errors ============

    error InvalidToken();
    error InvalidAmount();
    error InvalidPriceFeed();
    error InvalidMarket();
    error InvalidUnderlying();
    error PTUnderlyingNotFound();
    error PriceFeedNotFound();
    error InvalidPrice();
    error PriceDataTooOld();
    error UnderlyingMissingPriceFeed();
    error DecimalsMismatch(uint8 ptDecimals, uint8 underlyingDecimals);

    // ============ Constructor ============

    /**
     * @notice Deploy the oracle contract
     * @param _pendleOracle Pendle Oracle address
     */
    constructor(address _pendleOracle) Ownable(msg.sender) {
        if (_pendleOracle == address(0)) revert InvalidToken();
        pendleOracle = _pendleOracle;
    }

    // ============ External Functions ============

    /**
     * @notice Get USD value of token amount
     * @dev Implements IPriceOracle.getUsdValue
     * @param token Token address
     * @param amount Amount of tokens (in wei)
     * @return usdValue Value in USD with 8 decimal places
     */
    function getUsdValue(address token, uint256 amount) external view returns (uint256 usdValue) {
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) {
            return 0;
        }

        // Check if token is a PT token
        address market = ptToMarket[token];
        if (market != address(0)) {
            return _getPTTokenUsdValue(token, amount, market);
        }

        return _getChainlinkUsdValue(token, amount);
    }

    /**
     * @notice Add or update Chainlink price feed for a token
     * @param token Token address
     * @param priceFeed ChainliCalculate USD value with proper decimal handlingnk price feed address
     */
    function addPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        if (priceFeed == address(0)) revert InvalidPriceFeed();

        priceFeeds[token] = priceFeed;

        emit PriceFeedUpdated(token, priceFeed);
    }

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
    ) external onlyOwner {
        if (ptToken == address(0)) revert InvalidToken();
        if (market == address(0)) revert InvalidMarket();
        if (underlyingToken == address(0)) revert InvalidUnderlying();
        if (priceFeeds[underlyingToken] == address(0)) revert UnderlyingMissingPriceFeed();

        ptToMarket[ptToken] = market;
        ptToUnderlying[ptToken] = PTInfo(useSy, underlyingToken);

        emit PTTokenAdded(ptToken, market, underlyingToken);
    }

    /**
     * @notice Update Pendle Oracle address
     * @param _pendleOracle New Pendle Oracle address
     */
    function setPendleOracle(address _pendleOracle) external onlyOwner {
        if (_pendleOracle == address(0)) revert InvalidToken();

        address oldOracle = pendleOracle;
        pendleOracle = _pendleOracle;

        emit PendleOracleUpdated(oldOracle, _pendleOracle);
    }

    // ============ View Functions ============

    /**
     * @notice Get price feed address for a token
     * @param token Token address
     * @return priceFeed Address of the Chainlink price feed
     */
    function getPriceFeed(address token) external view returns (address priceFeed) {
        return priceFeeds[token];
    }

    /**
     * @notice Get PT token market address
     * @param ptToken PT token address
     * @return market Pendle market address
     */
    function getPTMarket(address ptToken) external view returns (address market) {
        return ptToMarket[ptToken];
    }

    /**
     * @notice Check if token is a registered PT token
     * @param token Token address to check
     * @return isPT True if token is a registered PT token
     */
    function isPTToken(address token) external view returns (bool isPT) {
        return ptToMarket[token] != address(0);
    }

    // ============ Internal Functions ============

    /**
     * @notice Get USD value of PT token using Pendle Oracle
     * @dev Uses period=0 for spot pricing per ADR-0004
     * @param ptToken PT token address
     * @param amount Amount of PT tokens
     * @param market Pendle market address
     * @return usdValue Value in USD with 8 decimals
     */
    function _getPTTokenUsdValue(
        address ptToken,
        uint256 amount,
        address market
    ) private view returns (uint256 usdValue) {
        PTInfo memory underlying = ptToUnderlying[ptToken];
        if (underlying.token == address(0)) revert PTUnderlyingNotFound();

        // Get PT rate from Pendle Oracle with period=0 (spot price)
        uint256 ptRate;
        if (underlying.useSy) {
            ptRate = IPendleOracle(pendleOracle).getPtToSyRate(market, 0);
        } else {
            ptRate = IPendleOracle(pendleOracle).getPtToAssetRate(market, 0);
        }

        // Calculate PT token value in underlying asset
        // ptRate is in 1e18, amount is in PT token decimals
        // Result will be in PT token decimals (should match underlying decimals)
        uint256 ptValueInUnderlying = (amount * ptRate) / WAD;

        // Verify PT and underlying have same decimals (required for correct calculation)
        // This is standard for Pendle PT tokens - they match their underlying asset decimals
        uint8 ptDecimals = IERC20Metadata(ptToken).decimals();
        uint8 underlyingDecimals = IERC20Metadata(underlying.token).decimals();
        if (ptDecimals != underlyingDecimals) {
            revert DecimalsMismatch(ptDecimals, underlyingDecimals);
        }

        // Get USD value of underlying asset
        return _getChainlinkUsdValue(underlying.token, ptValueInUnderlying);
    }

    /**
     * @notice Get USD value via Chainlink price feed
     * @param token Token address
     * @param amount Token amount
     * @return usdValue Value in USD with 8 decimals
     */
    function _getChainlinkUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256 usdValue) {
        address feedAddress = priceFeeds[token];
        if (feedAddress == address(0)) revert PriceFeedNotFound();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddress);

        // Get latest price data
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        // Validate price data (SR-005.2: Price Validation)
        if (price <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > MAX_PRICE_AGE) revert PriceDataTooOld();

        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        uint8 feedDecimals = priceFeed.decimals();

        // Calculate USD value with proper decimal handling
        // Step 1: Normalize amount to 18 decimals for consistent calculation
        uint256 normalizedAmount = _normalizeAmount(amount, tokenDecimals, 18);

        // Step 2: Multiply by price and normalize to DECIMALS (8)
        // Formula: (normalizedAmount * price) / 10^(18 + feedDecimals - DECIMALS)
        // Example: (1000 * 1e18) * (1.00 * 1e8) / 1e18 = 1000 * 1e8
        usdValue = (normalizedAmount * uint256(price)) / (10 ** (18 + feedDecimals - DECIMALS));

        return usdValue;
    }

    /**
     * @notice Normalize token amount between different decimal scales
     * @param amount Amount to normalize
     * @param fromDecimals Source decimals
     * @param toDecimals Target decimals
     * @return Normalized amount
     */
    function _normalizeAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) private pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }
}
