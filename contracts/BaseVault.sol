// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BaseVault
 * @dev Base vault implementation that supports hierarchical composition and performance fees
 * @notice This contract provides core vault functionality with PPS-based high water mark fee mechanism
 */
abstract contract BaseVault is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20% max
    uint256 public constant FEE_PRECISION = 10000; // 100%
    uint256 private constant INITIAL_PPS = 1e18; // 1:1 ratio initially

    // ============ State Variables ============

    /// @notice The underlying asset token
    IERC20 public asset;

    /// @notice Performance fee in basis points (0-2000 = 0-20%)
    uint256 public performanceFee;

    /// @notice High water mark for performance fee calculation (price per share)
    uint256 public highWaterMark;

    /// @notice Address to receive performance fees
    address public feeRecipient;

    // ============ Events ============

    event Deposit(
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event PerformanceFeeCharged(
        uint256 feeAmount,
        uint256 newHighWaterMark,
        address indexed recipient
    );

    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    // ============ Errors ============

    error InsufficientAssets();
    error InsufficientShares();
    error InvalidFeeRate();
    error ZeroAddress();
    error ZeroAmount();

    // ============ Modifiers ============

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Not manager");
        _;
    }

    // ============ Initialization ============

    /**
     * @notice Initialize the vault
     * @param _asset The underlying asset token
     * @param _name The vault token name
     * @param _symbol The vault token symbol
     * @param _performanceFee Performance fee in basis points
     * @param _feeRecipient Address to receive fees
     */
    function __BaseVault_init(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _performanceFee,
        address _feeRecipient
    ) internal onlyInitializing {
        if (_asset == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_performanceFee > MAX_PERFORMANCE_FEE) revert InvalidFeeRate();

        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        asset = IERC20(_asset);
        performanceFee = _performanceFee;
        feeRecipient = _feeRecipient;
        highWaterMark = INITIAL_PPS;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ============ Core Vault Functions ============

    /**
     * @notice Deposit assets into the vault
     * @param assets Amount of assets to deposit
     * @param minShares Minimum shares to receive
     * @param data Additional data for strategy execution
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        uint256 minShares,
        bytes calldata data
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        // Get pre-deploy NAV and total supply
        uint256 preDeployNav = totalAssets();
        uint256 totalSupply_ = totalSupply();

        // Transfer assets from user
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Deploy assets via strategy hook
        _deploy(assets, data);

        // Get post-deploy NAV
        uint256 postDeployNav = totalAssets();

        // Calculate shares to mint based on NAV increase and total supply
        if (totalSupply_ == 0) {
            // First deposit: 1:1 ratio
            shares = assets;
        } else {
            // Calculate shares based on NAV increase
            uint256 navIncrease = postDeployNav - preDeployNav;
            shares = (navIncrease * totalSupply_) / preDeployNav;
        }

        if (shares < minShares) revert InsufficientShares();

        // Mint shares to user
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, assets, shares);
    }

    /**
     * @notice Withdraw assets from the vault
     * @param shares Amount of shares to burn
     * @param minAssets Minimum assets to receive
     * @param data Additional data for strategy execution
     * @return assets Amount of assets withdrawn
     */
    function withdraw(
        uint256 shares,
        uint256 minAssets,
        bytes calldata data
    ) external nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientShares();

        // Withdraw underlying assets via strategy hook first - strategy determines actual amount
        assets = _withdrawUnderlying(shares, data);
        if (assets < minAssets) revert InsufficientAssets();

        // Burn shares only after successful withdrawal
        _burn(msg.sender, shares);

        // Transfer assets to user
        asset.safeTransfer(msg.sender, assets);

        emit Withdraw(msg.sender, assets, shares);
    }

    /**
     * @notice Get total assets managed by the vault
     * @dev Must be implemented by derived contracts
     * @return Total asset value in underlying token
     */
    function totalAssets() public view virtual returns (uint256);

    /**
     * @notice Get available capacity for new deposits
     * @dev Must be implemented by derived contracts
     * @return Available capacity in asset tokens
     */
    function availableCapacity() external view virtual returns (uint256);

    // ============ Performance Fee Mechanism ============

    /**
     * @notice Charge performance fee based on high water mark
     */
    function _chargePerformanceFee() internal {
        uint256 totalSupply_ = totalSupply();
        if (performanceFee == 0 || totalSupply_ == 0) {
            return;
        }

        uint256 totalAssets_ = totalAssets();
        uint256 currentPPS = (totalAssets_ * 1e18) / totalSupply_;

        if (currentPPS > highWaterMark) {
            uint256 profit = ((currentPPS - highWaterMark) * totalSupply_) / 1e18;
            uint256 feeAmount = (profit * performanceFee) / FEE_PRECISION;

            if (feeAmount > 0) {
                // Calculate fee shares to mint
                uint256 feeShares = (feeAmount * totalSupply_) / (totalAssets_ - feeAmount);

                // Mint fee shares to recipient
                _mint(feeRecipient, feeShares);

                // Update high water mark
                highWaterMark = (totalAssets_ * 1e18) / (totalSupply_ + feeShares);

                emit PerformanceFeeCharged(feeAmount, currentPPS, feeRecipient);
            }
        }
    }

    /**
     * @notice Calculate current price per share
     * @return Price per share in 1e18 precision
     */
    function _pricePerShare() internal view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return INITIAL_PPS;
        }
        return (totalAssets() * 1e18) / totalSupply_;
    }

    /**
     * @notice Get current price per share (external view)
     * @return Price per share in 1e18 precision
     */
    function pricePerShare() external view returns (uint256) {
        return _pricePerShare();
    }

    /**
     * @notice Manually trigger performance fee charging (manager only)
     */
    function harvest() external onlyManager {
        _chargePerformanceFee();
    }

    // ============ Strategy Hooks ============

    /**
     * @notice Deploy assets into strategy (must be implemented by derived contracts)
     * @param assets Amount of assets to deploy
     * @param data Strategy-specific execution data
     */
    function _deploy(uint256 assets, bytes calldata data) internal virtual;

    /**
     * @notice Withdraw assets from strategy (must be implemented by derived contracts)
     * @param shares Amount of shares being withdrawn
     * @param data Strategy-specific execution data
     * @return assets Actual amount of assets withdrawn by the strategy
     */
    function _withdrawUnderlying(uint256 shares, bytes calldata data) internal virtual returns (uint256 assets);

    // ============ Management Functions ============

    /**
     * @notice Update performance fee (manager only)
     * @param _performanceFee New performance fee in basis points
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyManager {
        if (_performanceFee > MAX_PERFORMANCE_FEE) revert InvalidFeeRate();

        uint256 oldFee = performanceFee;
        performanceFee = _performanceFee;

        emit PerformanceFeeUpdated(oldFee, _performanceFee);
    }

    /**
     * @notice Update fee recipient (manager only)
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyManager {
        if (_feeRecipient == address(0)) revert ZeroAddress();

        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    /**
     * @notice Pause the vault (manager only)
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause the vault (manager only)
     */
    function unpause() external onlyManager {
        _unpause();
    }

    // ============ View Functions ============

    /**
     * @notice Get vault configuration
     */
    function getVaultInfo() external view returns (
        address assetToken,
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 pricePerShare_,
        uint256 performanceFee_,
        uint256 highWaterMark_,
        address feeRecipient_
    ) {
        return (
            address(asset),
            totalAssets(),
            totalSupply(),
            _pricePerShare(),
            performanceFee,
            highWaterMark,
            feeRecipient
        );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[40] private __gap;
}
