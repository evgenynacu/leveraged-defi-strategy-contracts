// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockEVault
 * @notice Mock implementation of Euler V2 Vault for testing
 * @dev Simulates Euler vault operations with simplified share-based accounting
 */
contract MockEVault {
    using SafeERC20 for IERC20;

    address public immutable asset;

    // Share balances
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) private _debtShares; // Internal debt shares tracking

    // Total shares
    uint256 public totalSupply;
    uint256 public totalDebt; // Total debt shares

    // Total assets (for share conversion)
    uint256 public totalAssets;
    uint256 public totalDebtAssets;

    // For testing error cases
    bool public shouldFailDeposit;
    bool public shouldFailWithdraw;
    bool public shouldFailBorrow;
    bool public shouldFailRepay;

    constructor(address _asset) {
        asset = _asset;
    }

    /**
     * @notice Deposit assets into the vault
     * @param amount Amount of assets to deposit
     * @param receiver Address to receive the vault shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!shouldFailDeposit, "Deposit failed");
        require(amount > 0, "Amount must be > 0");

        // Transfer assets from sender
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate shares (1:1 for simplicity, or proportional if assets exist)
        if (totalSupply == 0) {
            shares = amount;
        } else {
            shares = (amount * totalSupply) / totalAssets;
        }

        balanceOf[receiver] += shares;
        totalSupply += shares;
        totalAssets += amount;

        return shares;
    }

    /**
     * @notice Withdraw assets from the vault
     * @param amount Amount of assets to withdraw
     * @param receiver Address to receive the assets
     * @param owner Owner of the shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256 shares) {
        require(!shouldFailWithdraw, "Withdraw failed");
        require(amount > 0, "Amount must be > 0");

        // Calculate shares to burn
        if (totalAssets == 0) {
            shares = 0;
        } else {
            shares = (amount * totalSupply) / totalAssets;
        }

        require(balanceOf[owner] >= shares, "Insufficient balance");

        balanceOf[owner] -= shares;
        totalSupply -= shares;
        totalAssets -= amount;

        // Transfer assets to receiver
        IERC20(asset).safeTransfer(receiver, amount);

        return shares;
    }

    /**
     * @notice Borrow assets from the vault
     * @param amount Amount of assets to borrow
     * @param receiver Address to receive the borrowed assets
     * @return shares Amount of debt shares created
     */
    function borrow(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!shouldFailBorrow, "Borrow failed");
        require(amount > 0, "Amount must be > 0");

        // Calculate debt shares (1:1 for simplicity, or proportional)
        if (totalDebt == 0) {
            shares = amount;
        } else {
            shares = (amount * totalDebt) / totalDebtAssets;
        }

        _debtShares[receiver] += shares;
        totalDebt += shares;
        totalDebtAssets += amount;

        // Transfer borrowed assets
        IERC20(asset).safeTransfer(receiver, amount);

        return shares;
    }

    /**
     * @notice Repay borrowed assets to the vault
     * @param amount Amount of assets to repay
     * @param receiver Address on whose behalf to repay
     * @return shares Amount of debt shares burned
     */
    function repay(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!shouldFailRepay, "Repay failed");
        require(amount > 0, "Amount must be > 0");

        // Get current debt in assets
        uint256 currentDebt = this.debtOf(receiver);

        // Calculate actual amount to repay (limited by debt)
        uint256 actualAmount = amount;
        if (actualAmount > currentDebt) {
            actualAmount = currentDebt;
        }

        // Calculate debt shares to burn
        if (totalDebtAssets == 0) {
            shares = 0;
        } else {
            shares = (actualAmount * totalDebt) / totalDebtAssets;
        }

        // Transfer assets from msg.sender
        IERC20(asset).safeTransferFrom(msg.sender, address(this), actualAmount);

        _debtShares[receiver] -= shares;
        totalDebt -= shares;
        totalDebtAssets -= actualAmount;

        return shares;
    }

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        if (totalSupply == 0) {
            return shares; // 1:1 if no shares exist
        }
        return (shares * totalAssets) / totalSupply;
    }

    /**
     * @notice Convert assets to shares
     * @param assets Amount of assets
     * @return shares Amount of shares
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        if (totalSupply == 0) {
            return assets; // 1:1 if no shares exist
        }
        return (assets * totalSupply) / totalAssets;
    }

    /**
     * @notice Convert debt shares to debt assets
     * @param shares Amount of debt shares
     * @return assets Amount of debt assets
     */
    function debtToAssets(uint256 shares) external view returns (uint256 assets) {
        if (totalDebt == 0) {
            return shares; // 1:1 if no debt exists
        }
        return (shares * totalDebtAssets) / totalDebt;
    }

    /**
     * @notice Get debt balance in assets for an account
     * @param account Account address
     * @return Debt balance in assets
     */
    function debtOf(address account) external view returns (uint256) {
        if (totalDebt == 0) {
            return 0;
        }
        return (_debtShares[account] * totalDebtAssets) / totalDebt;
    }

    // ============ Test Helpers ============

    function setShouldFailDeposit(bool _shouldFail) external {
        shouldFailDeposit = _shouldFail;
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

    // Set balances directly for testing
    function setBalance(address account, uint256 amount) external {
        balanceOf[account] = amount;
        totalSupply += amount;
        totalAssets += amount;
    }

    function setDebt(address account, uint256 amount) external {
        _debtShares[account] = amount;
        totalDebt += amount;
        totalDebtAssets += amount;
    }

    // Mint assets to vault for liquidity
    function mintAssets(uint256 amount) external {
        // Mint ERC20 tokens to this vault (requires MockERC20 with mint function)
        totalAssets += amount;
    }
}

/**
 * @title MockEVC
 * @notice Mock implementation of Euler Verification Controller for testing
 * @dev Simulates EVC operations with simplified account management
 */
contract MockEVC {
    // Track enabled collaterals and controllers per account
    mapping(address => mapping(address => bool)) public isCollateralEnabled;
    mapping(address => mapping(address => bool)) public isControllerEnabled;

    // Current authenticated account
    address public currentOnBehalfOfAccount;

    /**
     * @notice Enable a collateral vault for an account
     * @param account Account address
     * @param vault Vault address to enable as collateral
     */
    function enableCollateral(address account, address vault) external {
        isCollateralEnabled[account][vault] = true;
    }

    /**
     * @notice Enable a controller (debt vault) for an account
     * @param account Account address
     * @param vault Vault address to enable as controller
     */
    function enableController(address account, address vault) external {
        isControllerEnabled[account][vault] = true;
    }

    /**
     * @notice Call a function on a target contract on behalf of an account
     * @param targetContract Target contract address
     * @param onBehalfOfAccount Account on whose behalf to execute
     * @param value ETH value to send
     * @param data Calldata for the function call
     * @return result Result of the function call
     */
    function call(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory result) {
        // Set current authenticated account
        currentOnBehalfOfAccount = onBehalfOfAccount;

        // Execute the call
        (bool success, bytes memory returnData) = targetContract.call{value: value}(data);
        require(success, "EVC call failed");

        // Clear authenticated account
        currentOnBehalfOfAccount = address(0);

        return returnData;
    }

    /**
     * @notice Get the currently authenticated account
     * @return account Currently authenticated account address
     */
    function getCurrentOnBehalfOfAccount() external view returns (address account) {
        return currentOnBehalfOfAccount;
    }
}
