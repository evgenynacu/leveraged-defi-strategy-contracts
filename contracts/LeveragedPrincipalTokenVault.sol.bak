// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseVault.sol";

/**
 * @title LeveragedPTVault
 * @notice Leveraged Principal Token strategy vault using command-based execution
 * @dev Inherits from BaseVault and implements command execution for complex DeFi operations
 */
contract LeveragedPTVault is BaseVault {
    using SafeERC20 for IERC20;

    IERC20 public base;

    // ============ Command System ============

    enum Op {
        MorphoFlashLoan,
        OdosSwap
    }

    struct Cmd {
        Op op;
        bytes data; // ABI-encoded arguments for this operation
    }

    // ============ State Variables ============

    /// @notice Role for keepers who can execute commands for rebalancing
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ============ Events ============

    event CommandsExecuted(uint256 commandCount, address indexed executor);

    // ============ Errors ============

    error UnsupportedOperation(Op op);
    error CommandExecutionFailed(uint256 commandIndex, Op op);
    error EmptyCommandArray();

    // ============ Initialization ============

    /**
     * @notice Initialize the LeveragedPTVault
     * @param _asset The underlying asset token (e.g., USDC)
     * @param _name The vault token name
     * @param _symbol The vault token symbol
     * @param _performanceFee Performance fee in basis points
     * @param _feeRecipient Address to receive fees
     */
    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _performanceFee,
        address _feeRecipient
    ) external initializer {
        __BaseVault_init(_asset, _name, _symbol, _performanceFee, _feeRecipient);

        // Grant keeper role to deployer initially
        _grantRole(KEEPER_ROLE, msg.sender);
    }

    // ============ BaseVault Implementation ============

    /**
     * @notice Calculate total assets managed by the vault
     * @dev For now returns simple balance - will be enhanced with PT valuation
     * @return Total asset value in underlying token
     */
    function totalAssets() public view override returns (uint256) {
        // TODO: Implement proper NAV calculation with:
        // - PT token valuation using oracles
        // - Outstanding debt calculation
        // - Collateral positions across lending protocols
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Get available capacity for new deposits
     * @dev For now returns unlimited capacity - will be enhanced with strategy limits
     * @return Available capacity in asset tokens
     */
    function availableCapacity() external view override returns (uint256) {
        // TODO: Implement capacity calculation based on:
        // - Maximum leverage ratios
        // - Available liquidity in lending protocols
        // - PT market depth and liquidity
        return type(uint256).max;
    }

    /**
     * @notice Deploy assets into leveraged PT strategy
     * @param assets Amount of assets to deploy
     * @param data ABI-encoded array of commands to execute
     */
    function _deploy(uint256 assets, bytes calldata data) internal override {
        // deposit
        /**
         * store debt balance
         * store assets balance
         * calculate flashLoanAmount с помощью оракулов (если debt != base)
         * flashLoan(debt token, flashLoanAmount). leverage - описан в стратегии
         *   swap base token to collateral => out = approx
         *   swap flash loan to collateral => out = approx (if are different)
         *      TODO: check exchanged tokens, exchanged amounts as user provides routes, check slippage
         *   supply all collateral (diff from start) - lending is provided by the user (Aave, Morpho etc)
         *   borrow (flashLoanAmount) debt
         * return debt
         */

        if (data.length > 0) {
            Cmd[] memory commands = abi.decode(data, (Cmd[]));
            _executeCommands(commands);
        }
        // If no commands provided, assets remain in vault as idle cash
    }

    function _deposit(
        IERC20 debt,
        uint256 assets,
        address debtSwapRouter,
        bytes calldata debtSwapData
    ) internal {
        uint256 debtBalanceBefore = debt.balanceOf(address(this));
        //
        _swap(base, debt, assets, debtSwapRouter, debtSwapData);
        // тут мы будем знать, сколько примерно будет токенов (будем знать on-chain + проверим через оракул)
        // можем посчитать, сколько будет funds * leverage = это будет примерно,
        // берем flashLoan - будем знать, сколько примерно их
        // после получения flash loan меняем все на PT (тут мы знаем только примерное количество токенов, как с этим быть?)
    }

    function _swap(IERC20 from, IERC20 to, uint amount, address router, bytes calldata swapData) internal {

    }

    /**
     * @notice Withdraw assets from strategy by executing commands
     * @param shares Amount of shares being withdrawn
     * @param data ABI-encoded array of commands to execute
     * @return assets Actual amount of assets withdrawn
     */
    function _withdrawUnderlying(uint256 shares, bytes calldata data)
        internal
        override
        returns (uint256 assets)
    {
        /**
         * shares - считаем какая часть коллатерала должна быть снята.
         * и считаем весь долг, берем часть долга по shares, считаем сколько base нужно по оракулу (сравниваем с обмениваемым значением)
         * берем flash loan base token
         *    меняем base на debt - будет примерное значение
         *    repay debt (diff)
         *    withdraw collateral (снимаем ту часть, которой владеет shares, должно быть в пределах погрешности)
         *    swap collateral diff to base
         * остаток отдаем в качестве base assets, который заработал чувак
         *
         * flash loan debt (сколько брать для освобождения нужного количества shares) TODO не ясно, сколько нужно взять в долг
         *    repay diff from start
         *    withdraw collateral TODO calculate how much
         *    swap all new collateral to debt ()
         *
         * осталось debt поменять на base и менять параметры (либо менять минимально возможное количество токенов после отдачи flash loan)
         */


        uint256 assetsBefore = asset.balanceOf(address(this));

        if (data.length > 0) {
            Cmd[] memory commands = abi.decode(data, (Cmd[]));
            _executeCommands(commands);
        }

        uint256 assetsAfter = asset.balanceOf(address(this));

        // Return the increase in asset balance
        assets = assetsAfter > assetsBefore ? assetsAfter - assetsBefore : 0;
    }

    // ============ Command Execution ============

    /**
     * @notice Execute arbitrary commands (keeper only)
     * @dev Allows keepers to rebalance positions, refinance debt, etc.
     * @param commands Array of commands to execute
     */
    function executeCommands(Cmd[] calldata commands)
        external
        onlyRole(KEEPER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _executeCommands(commands);
    }

    /**
     * @notice Execute array of commands
     * @param commands Array of commands to execute
     */
    function _executeCommands(Cmd[] memory commands) internal {
        if (commandExecutionPaused) revert CommandExecutionPaused();
        if (commands.length == 0) revert EmptyCommandArray();

        for (uint256 i = 0; i < commands.length; i++) {
            _executeCommand(commands[i], i);
        }

        emit CommandsExecuted(commands.length, msg.sender);
    }

    /**
     * @notice Execute a single command
     * @param cmd Command to execute
     * @param index Command index for error reporting
     */
    function _executeCommand(Cmd memory cmd, uint256 index) internal {
        if (!supportedOps[cmd.op]) {
            revert UnsupportedOperation(cmd.op);
        }

        try this._executeCommandInternal(cmd) {
            // Command executed successfully
        } catch {
            revert CommandExecutionFailed(index, cmd.op);
        }
    }

    /**
     * @notice Internal command execution (external for try-catch)
     * @param cmd Command to execute
     */
    function _executeCommandInternal(Cmd memory cmd) external {
        require(msg.sender == address(this), "Only self-call allowed");

        if (cmd.op == Op.FlashLoan) {
            _executeFlashLoan(cmd.data);
        } else if (cmd.op == Op.LendingDeposit) {
            _executeLendingDeposit(cmd.data);
        } else if (cmd.op == Op.LendingWithdraw) {
            _executeLendingWithdraw(cmd.data);
        } else if (cmd.op == Op.LendingBorrow) {
            _executeLendingBorrow(cmd.data);
        } else if (cmd.op == Op.LendingRepay) {
            _executeLendingRepay(cmd.data);
        } else if (cmd.op == Op.Swap) {
            _executeSwap(cmd.data);
        } else if (cmd.op == Op.Transfer) {
            _executeTransfer(cmd.data);
        }
    }

    // ============ Command Implementations (Stubs) ============

    function _executeFlashLoan(bytes memory data) internal {
        // TODO: Implement flash loan execution
        revert("FlashLoan not implemented");
    }

    function _executeLendingDeposit(bytes memory data) internal {
        // TODO: Implement lending deposit
        revert("LendingDeposit not implemented");
    }

    function _executeLendingWithdraw(bytes memory data) internal {
        // TODO: Implement lending withdraw
        revert("LendingWithdraw not implemented");
    }

    function _executeLendingBorrow(bytes memory data) internal {
        // TODO: Implement lending borrow
        revert("LendingBorrow not implemented");
    }

    function _executeLendingRepay(bytes memory data) internal {
        // TODO: Implement lending repay
        revert("LendingRepay not implemented");
    }

    function _executeSwap(bytes memory data) internal {
        // TODO: Implement swap execution
        revert("Swap not implemented");
    }

    function _executeTransfer(bytes memory data) internal {
        // TODO: Implement transfer
        revert("Transfer not implemented");
    }

    // ============ Management Functions ============

    /**
     * @notice Toggle command execution pause (manager only)
     * @param paused Whether to pause command execution
     */
    function setCommandExecutionPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        commandExecutionPaused = paused;
        emit CommandExecutionPaused(paused);
    }

    /**
     * @notice Update supported operation (manager only)
     * @param op Operation to update
     * @param supported Whether operation is supported
     */
    function setSupportedOperation(Op op, bool supported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedOps[op] = supported;
        emit SupportedOperationUpdated(op, supported);
    }

    /**
     * @notice Grant keeper role (manager only)
     * @param keeper Address to grant keeper role
     */
    function grantKeeperRole(address keeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEEPER_ROLE, keeper);
    }

    /**
     * @notice Revoke keeper role (manager only)
     * @param keeper Address to revoke keeper role from
     */
    function revokeKeeperRole(address keeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(KEEPER_ROLE, keeper);
    }
}
