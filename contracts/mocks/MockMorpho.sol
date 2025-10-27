// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IMorpho, MarketParams, Id, Position, Market} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockMorpho
 * @notice Mock implementation of Morpho Blue for testing
 * @dev Simplified implementation that tracks positions and converts between shares/assets
 */
contract MockMorpho {
    using SafeERC20 for IERC20;

    // Market ID => Market parameters
    mapping(Id => MarketParams) public markets;

    // Market ID => Market state
    mapping(Id => Market) public marketState;

    // Market ID => User => Position
    mapping(Id => mapping(address => Position)) public positions;

    // Events
    event SupplyCollateral(Id indexed marketId, address indexed user, uint256 amount);
    event WithdrawCollateral(Id indexed marketId, address indexed user, uint256 amount);
    event Borrow(Id indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event Repay(Id indexed marketId, address indexed user, uint256 assets, uint256 shares);

    /**
     * @notice Create a market
     * @param params Market parameters
     */
    function createMarket(MarketParams memory params) external {
        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        markets[marketId] = params;

        // Initialize market state with some liquidity for testing
        marketState[marketId] = Market({
            totalSupplyAssets: 1000000e6, // 1M initial supply
            totalSupplyShares: 1000000e6,
            totalBorrowAssets: 0,
            totalBorrowShares: 0,
            lastUpdate: uint128(block.timestamp),
            fee: 0
        });
    }

    /**
     * @notice Supply collateral to a market
     * @param params Market parameters
     * @param assets Amount of collateral to supply
     * @param onBehalfOf Address to credit the collateral to
     */
    function supplyCollateral(
        MarketParams memory params,
        uint256 assets,
        address onBehalfOf,
        bytes memory /*data*/
    ) external {
        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        require(markets[marketId].loanToken != address(0), "Market does not exist");

        IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        Position storage pos = positions[marketId][onBehalfOf];
        pos.collateral = uint128(uint256(pos.collateral) + assets);

        emit SupplyCollateral(marketId, onBehalfOf, assets);
    }

    /**
     * @notice Withdraw collateral from a market
     * @param params Market parameters
     * @param assets Amount of collateral to withdraw
     * @param onBehalfOf Address to withdraw collateral from
     * @param receiver Address to send collateral to
     */
    function withdrawCollateral(
        MarketParams memory params,
        uint256 assets,
        address onBehalfOf,
        address receiver
    ) external {
        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        require(markets[marketId].loanToken != address(0), "Market does not exist");

        Position storage pos = positions[marketId][onBehalfOf];
        require(uint256(pos.collateral) >= assets, "Insufficient collateral");

        pos.collateral = uint128(uint256(pos.collateral) - assets);
        IERC20(params.collateralToken).safeTransfer(receiver, assets);

        emit WithdrawCollateral(marketId, onBehalfOf, assets);
    }

    /**
     * @notice Borrow from a market
     * @param params Market parameters
     * @param assets Amount to borrow (if shares == 0)
     * @param shares Amount of shares to mint (if assets == 0)
     * @param onBehalfOf Address to borrow on behalf of
     * @param receiver Address to send borrowed assets to
     */
    function borrow(
        MarketParams memory params,
        uint256 assets,
        uint256 shares,
        address onBehalfOf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        require(markets[marketId].loanToken != address(0), "Market does not exist");

        Market storage marketData = marketState[marketId];
        Position storage pos = positions[marketId][onBehalfOf];

        // Convert assets to shares or vice versa
        if (shares == 0) {
            // Borrow by assets
            assetsBorrowed = assets;
            if (marketData.totalBorrowShares == 0) {
                sharesBorrowed = assets; // 1:1 for first borrow
            } else {
                sharesBorrowed = (assets * uint256(marketData.totalBorrowShares)) / uint256(marketData.totalBorrowAssets);
            }
        } else {
            // Borrow by shares
            sharesBorrowed = shares;
            if (marketData.totalBorrowShares == 0) {
                assetsBorrowed = shares; // 1:1 for first borrow
            } else {
                assetsBorrowed = (shares * uint256(marketData.totalBorrowAssets)) / uint256(marketData.totalBorrowShares);
            }
        }

        // Update position
        pos.borrowShares = uint128(uint256(pos.borrowShares) + sharesBorrowed);

        // Update market
        marketData.totalBorrowAssets = uint128(uint256(marketData.totalBorrowAssets) + assetsBorrowed);
        marketData.totalBorrowShares = uint128(uint256(marketData.totalBorrowShares) + sharesBorrowed);

        // Transfer borrowed assets
        IERC20(params.loanToken).safeTransfer(receiver, assetsBorrowed);

        emit Borrow(marketId, onBehalfOf, assetsBorrowed, sharesBorrowed);
    }

    /**
     * @notice Repay debt to a market
     * @param params Market parameters
     * @param assets Amount to repay (if shares == 0)
     * @param shares Amount of shares to burn (if assets == 0)
     * @param onBehalfOf Address to repay on behalf of
     */
    function repay(
        MarketParams memory params,
        uint256 assets,
        uint256 shares,
        address onBehalfOf,
        bytes memory /*data*/
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        require(markets[marketId].loanToken != address(0), "Market does not exist");

        Market storage marketData = marketState[marketId];
        Position storage pos = positions[marketId][onBehalfOf];

        // Convert assets to shares or vice versa
        if (shares == 0) {
            // Repay by assets
            assetsRepaid = assets;
            if (marketData.totalBorrowShares == 0) {
                sharesRepaid = 0;
            } else {
                sharesRepaid = (assets * uint256(marketData.totalBorrowShares)) / uint256(marketData.totalBorrowAssets);
            }
        } else {
            // Repay by shares
            sharesRepaid = shares;
            if (marketData.totalBorrowShares == 0) {
                assetsRepaid = 0;
            } else {
                assetsRepaid = (shares * uint256(marketData.totalBorrowAssets)) / uint256(marketData.totalBorrowShares);
            }
        }

        // Cap at current position
        if (sharesRepaid > pos.borrowShares) {
            sharesRepaid = pos.borrowShares;
            assetsRepaid = (sharesRepaid * uint256(marketData.totalBorrowAssets)) / uint256(marketData.totalBorrowShares);
        }

        // Update position
        pos.borrowShares = uint128(uint256(pos.borrowShares) - sharesRepaid);

        // Update market
        marketData.totalBorrowAssets = uint128(uint256(marketData.totalBorrowAssets) - assetsRepaid);
        marketData.totalBorrowShares = uint128(uint256(marketData.totalBorrowShares) - sharesRepaid);

        // Transfer repayment
        IERC20(params.loanToken).safeTransferFrom(msg.sender, address(this), assetsRepaid);

        emit Repay(marketId, onBehalfOf, assetsRepaid, sharesRepaid);
    }

    /**
     * @notice Get position for a user
     * @param id Market ID
     * @param user User address
     */
    function position(Id id, address user) external view returns (Position memory) {
        return positions[id][user];
    }

    /**
     * @notice Get market state
     * @param id Market ID
     */
    function market(Id id) external view returns (Market memory) {
        return marketState[id];
    }

    /**
     * @notice Get market parameters from ID
     * @param id Market ID
     */
    function idToMarketParams(Id id) external view returns (MarketParams memory) {
        return markets[id];
    }

    // ============ Helper Functions for Testing ============

    /**
     * @notice Helper to compute market ID from params
     */
    function computeMarketId(MarketParams memory params) external pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(params)));
    }

    /**
     * @notice Get collateral balance for a user
     */
    function getCollateralBalance(Id marketId, address user) external view returns (uint256) {
        return positions[marketId][user].collateral;
    }

    /**
     * @notice Get borrow shares for a user
     */
    function getBorrowShares(Id marketId, address user) external view returns (uint256) {
        return positions[marketId][user].borrowShares;
    }

    /**
     * @notice Get borrow assets for a user (converted from shares)
     */
    function getBorrowAssets(Id marketId, address user) external view returns (uint256) {
        Position memory pos = positions[marketId][user];
        Market memory marketData = marketState[marketId];

        if (pos.borrowShares == 0 || marketData.totalBorrowShares == 0) {
            return 0;
        }

        return (uint256(pos.borrowShares) * uint256(marketData.totalBorrowAssets)) / uint256(marketData.totalBorrowShares);
    }
}
