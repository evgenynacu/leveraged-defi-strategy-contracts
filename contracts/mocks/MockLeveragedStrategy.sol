// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../strategies/LeveragedStrategy.sol";

/**
 * @title MockLeveragedStrategy
 * @notice Mock implementation of LeveragedStrategy for testing
 * @dev Simulates lending protocol operations with simple storage
 */
contract MockLeveragedStrategy is LeveragedStrategy {
    // Mock lending protocol state
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    address[] public extraTrackedTokens;

    // For testing error cases
    bool public shouldFailSupply;
    bool public shouldFailWithdraw;
    bool public shouldFailBorrow;
    bool public shouldFailRepay;

    constructor(
        address _parent,
        address _baseAsset,
        address _priceOracle
    ) LeveragedStrategy(_parent, _baseAsset, _priceOracle) {}

    // ============ Mock Protocol Operations ============

    function _supply(address asset, uint256 amount) internal override {
        if (shouldFailSupply) revert("Supply failed");

        // Just update internal state - tokens already in strategy
        collateral[asset] += amount;
    }

    // Store token contracts to enable minting on withdraw
    mapping(address => address) public tokenContracts;

    function _withdraw(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualWithdrawn)
    {
        if (shouldFailWithdraw) revert("Withdraw failed");

        if (amount == type(uint256).max) {
            actualWithdrawn = collateral[asset];
        } else {
            actualWithdrawn = amount;
        }

        if (collateral[asset] < actualWithdrawn) {
            revert InsufficientBalance();
        }

        collateral[asset] -= actualWithdrawn;

        // Simulate receiving withdrawn tokens from lending protocol
        // Mint tokens to simulate protocol transferring them back
        address tokenContract = tokenContracts[asset];
        if (tokenContract != address(0) && actualWithdrawn > 0) {
            // Call mint function on MockERC20
            (bool success, ) = tokenContract.call(
                abi.encodeWithSignature("mint(address,uint256)", address(this), actualWithdrawn)
            );
            require(success, "Mint failed");
        }

        return actualWithdrawn;
    }

    function _borrow(address asset, uint256 amount) internal override {
        if (shouldFailBorrow) revert("Borrow failed");

        debt[asset] += amount;

        // Simulate receiving borrowed tokens
        // In real protocol, this would transfer from protocol to strategy
    }

    function _repay(address asset, uint256 amount)
        internal
        override
        returns (uint256 actualRepaid)
    {
        if (shouldFailRepay) revert("Repay failed");

        if (amount == type(uint256).max) {
            actualRepaid = debt[asset];
        } else {
            actualRepaid = amount;
        }

        if (debt[asset] < actualRepaid) {
            actualRepaid = debt[asset];
        }

        debt[asset] -= actualRepaid;
        return actualRepaid;
    }

    function _getCollateralAsset() internal view override returns (address) {
        return baseAsset;
    }

    function _getCollateralAmount() internal view override returns (uint256) {
        return collateral[baseAsset];
    }

    function _getDebtAsset() internal view override returns (address) {
        return baseAsset;
    }

    function _getDebtAmount() internal view override returns (uint256) {
        return debt[baseAsset];
    }

    function _trackedTokens() internal view override returns (address[] memory tokens) {
        address[] memory baseTokens = super._trackedTokens();
        uint256 baseLength = baseTokens.length;
        uint256 extraLength = extraTrackedTokens.length;

        tokens = new address[](baseLength + extraLength);
        uint256 count;

        for (uint256 i = 0; i < baseLength; i++) {
            tokens[count++] = baseTokens[i];
        }

        for (uint256 i = 0; i < extraLength; i++) {
            address candidate = extraTrackedTokens[i];
            if (candidate == address(0)) continue;

            bool exists = false;
            for (uint256 j = 0; j < count; j++) {
                if (tokens[j] == candidate) {
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                tokens[count++] = candidate;
            }
        }

        assembly {
            mstore(tokens, count)
        }
    }

    // ============ Test Helpers ============

    function setCollateral(address asset, uint256 amount) external {
        collateral[asset] = amount;
    }

    function setDebt(address asset, uint256 amount) external {
        debt[asset] = amount;
    }

    function setShouldFailSupply(bool _shouldFail) external {
        shouldFailSupply = _shouldFail;
    }

    function setShouldFailWithdraw(bool _shouldFail) external {
        shouldFailWithdraw = _shouldFail;
    }

    function setShouldFailBorrow(bool _shouldFail) external {
        shouldFailBorrow = _shouldFail;
    }

    function setShouldFailRepay(bool _shouldFail) external {
        shouldFailRepay = _shouldFail;
    }

    // Expose command execution for testing
    function executeCommandsPublic(Command[] memory commands) external {
        _executeCommands(commands);
    }

    // Expose swap router configuration for testing
    function setSwapRouter(SwapRouter router, address routerAddress) external {
        _setSwapRouter(router, routerAddress);
    }

    // Register token contract to enable minting on withdraw
    function setTokenContract(address asset, address tokenContract) external {
        tokenContracts[asset] = tokenContract;
    }

    function addTrackedToken(address token) external {
        extraTrackedTokens.push(token);
    }
}
