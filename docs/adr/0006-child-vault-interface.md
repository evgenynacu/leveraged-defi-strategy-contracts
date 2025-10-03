# ADR-0006: Child Strategy Interface

## Status
Accepted

## Date
2024-10-01

## Context
Child strategies are single-owner execution engines with no internal share accounting. Parent vault controls all asset movements and debt obligations.

## Requirements
- **Single caller:** only parent can call operations.
- **Sync operations:** no user queues, no internal epochs.
- **Multi-token support:** accept any token for deposit/withdraw, not just base asset.
- **Debt obligation pattern:** parent specifies debt that child strategy owes back.
- **Minimal interface:** only essential functions for strategy execution.
- **No internal shares:** parent owns all assets directly, no share minting in child.

## Decision

### Solidity Interface

```solidity
interface IChildStrategy {
    // ============ Core Operations ============

    /// @notice Deploy assets into strategy
    /// @param depositToken Token being deposited (PT, USDC, ETH, etc.)
    /// @param depositAmount Amount of deposit token
    /// @param providedToken Token that parent provides additionally (address(0) if none)
    /// @param providedAmount Amount of provided token
    /// @param expectedToken Token that parent expects back (address(0) if none)
    /// @param expectedAmount Amount of expected token
    /// @param data Strategy-specific execution data
    function deposit(
        address depositToken,
        uint256 depositAmount,
        address providedToken,
        uint256 providedAmount,
        address expectedToken,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    /// @notice Withdraw from strategy by percentage
    /// @param percentage Percentage to withdraw (1e18 = 100%)
    /// @param outputToken Desired output token
    /// @param providedToken Token that parent provides (address(0) if none)
    /// @param providedAmount Amount of provided token
    /// @param expectedToken Token that parent expects back (address(0) if none)
    /// @param expectedAmount Amount of expected token
    /// @param data Strategy-specific execution data
    /// @return actualWithdrawn Amount actually withdrawn in outputToken
    function withdraw(
        uint256 percentage,
        address outputToken,
        address providedToken,
        uint256 providedAmount,
        address expectedToken,
        uint256 expectedAmount,
        bytes calldata data
    ) external returns (uint256 actualWithdrawn);

    /// @notice Rebalance strategy
    /// @param providedToken Token that parent provides (address(0) if none)
    /// @param providedAmount Amount of provided token
    /// @param expectedToken Token that parent expects back (address(0) if none)
    /// @param expectedAmount Amount of expected token
    /// @param data Strategy-specific execution data
    function rebalance(
        address providedToken,
        uint256 providedAmount,
        address expectedToken,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    // ============ View Functions ============

    /// @notice Get strategy's net asset value in base asset terms
    function totalAssets() external view returns (uint256);
}
```

### Provided/Expected Token Pattern

**Core Principle:** Parent explicitly specifies what it provides to child strategy and what it expects back.

**Deposit Operation Examples:**

```solidity
// Scenario 1: Standard leverage - parent provides extra liquidity, expects it back
ptChildStrategy.deposit(
    USDC_TOKEN, 1000e6,      // depositToken/Amount: main deposit
    USDC_TOKEN, 7000e6,      // providedToken/Amount: leverage liquidity
    USDC_TOKEN, 7000e6,      // expectedToken/Amount: expect leverage back
    leverageData
);

// Scenario 2: Reverse leverage - parent expects debt from strategy
ptChildStrategy.deposit(
    PT_TOKEN, 1500,          // depositToken/Amount: deposit PT directly
    address(0), 0,           // providedToken/Amount: nothing provided
    USDT_TOKEN, 2000e6,      // expectedToken/Amount: expect USDT debt
    reverseData
);

// Child strategy execution:
function deposit(
    address depositToken, uint256 depositAmount,
    address providedToken, uint256 providedAmount,
    address expectedToken, uint256 expectedAmount,
    bytes calldata data
) external {
    // Handle provided liquidity if any
    if (providedToken != address(0)) {
        // Use provided liquidity for leverage
    }

    // Execute strategy with depositToken
    // ...

    // Approve expected tokens for parent collection
    if (expectedToken != address(0)) {
        IERC20(expectedToken).approve(parent, expectedAmount);
    }
}
```

**Withdrawal Operation Examples:**

```solidity
// Scenario 1: Standard deleverage - parent provides liquidity, expects it back
uint256 withdrawn = child.withdraw(
    1e17,                    // percentage: 10%
    USDC_TOKEN,              // outputToken: receive USDC
    USDT_TOKEN, 200e6,       // providedToken/Amount: deleverage liquidity
    USDT_TOKEN, 200e6,       // expectedToken/Amount: expect it back
    standardParams
);

// Scenario 2: Position transfer - parent provides liquidity, keeps it (expects collateral)
uint256 ptAmount = morphoChild.withdraw(
    1e18,                    // percentage: 100%
    PT_TOKEN,                // outputToken: receive PT directly
    USDT_TOKEN, 2000e6,      // providedToken/Amount: deleverage liquidity
    address(0), 0,           // expectedToken/Amount: parent keeps liquidity
    transferParams
);
```

### Position Transfer Flow

**Key Innovation:** No special `transferPosition()` function needed - use existing deposit/withdraw with different tokens.

**Example: Transfer PT position from Morpho strategy to Aave strategy**

```solidity
// Step 1: Withdraw PT from Morpho child (position transfer mode)
uint256 ptAmount = morphoChild.withdraw(
    1e18,                    // percentage: 100%
    PT_TOKEN,                // outputToken: receive PT directly
    USDT_TOKEN, 2000e6,      // providedToken/Amount: flash loan for deleverage
    address(0), 0,           // expectedToken/Amount: parent keeps liquidity
    morphoParams
);

// Step 2: Deposit PT into Aave child (use existing PT, borrow for flash loan repay)
aaveChild.deposit(
    PT_TOKEN, ptAmount,      // depositToken/Amount: deposit received PT
    address(0), 0,           // providedToken/Amount: no additional liquidity
    USDT_TOKEN, 2000e6,      // expectedToken/Amount: strategy borrows and returns
    aaveCommands
);

// Net result: PT position moved from Morpho to Aave, flash loan repaid
```

### Proportional Exit Logic

**Fair withdrawal:** Each user gets exactly their proportional share of actual assets.

```solidity
function withdraw(
    uint256 percentage,
    address outputToken,
    address providedToken,
    uint256 providedAmount,
    address expectedToken,
    uint256 expectedAmount,
    bytes calldata data
) external onlyParent returns (uint256 actualWithdrawn) {

    // Calculate proportional amounts based on percentage
    uint256 currentCollateral = _getCollateralAmount();
    uint256 currentDebt = _getDebtAmount();

    uint256 collateralToWithdraw = (currentCollateral * percentage) / 1e18;
    uint256 debtToRepay = (currentDebt * percentage) / 1e18;

    // Execute proportional unwind using provided liquidity
    actualWithdrawn = _executeWithdrawal(
        collateralToWithdraw,
        debtToRepay,
        outputToken,
        providedToken,
        providedAmount,
        data
    );

    // Approve parent to collect withdrawn assets
    IERC20(outputToken).approve(parent, actualWithdrawn);

    // Approve expected token if parent expects something back
    if (expectedToken != address(0)) {
        IERC20(expectedToken).approve(parent, expectedAmount);
    }

    return actualWithdrawn;
}
```

### Multi-Token Flexibility Benefits

1. **Direct Position Transfers:** PT → PT without USDC conversion
2. **Optimal Flash Loan Currency:** Do not need to borrow in USDC if child strategies use the same token
3. **Reduced Slippage:** Fewer token swaps in transfer operations
4. **Flexible Liquidity:** Parent manages flash loans in most efficient token
5. **Honest Accounting:** Users get actual realized value, not theoretical NAV

### Accounting and Logging Requirements

**Event Logging must enable complete financial reconstruction:**

1. **Money Flow Tracking:**
   - All token transfers between parent vault and child strategies
   - All provided/expected token movements
   - Flash loan amounts and repayments
   - User deposits and withdrawals

2. **Strategy Performance Analysis:**
   - NAV snapshots before and after each operation
   - Oracle prices for all assets at time of operations
   - Proportional withdrawal amounts vs actual received
   - Strategy-specific performance metrics

3. **PnL Calculation Support:**
   - Timestamp-indexed entry/exit prices for all positions
   - Interest accrual and fee tracking
   - Realized vs unrealized gains/losses
   - Cross-strategy rebalancing effects

**Implementation Guidelines:**
- Events should include both token amounts and USD values (using oracles)
- All monetary flows must be traceable for audit purposes
- Enable reconstruction of complete vault state at any block
- Support Dune Analytics queries for performance dashboards
- Include sufficient data for tax reporting and compliance

## Consequences
- Easy integration of heterogeneous strategies
- Parent can perform accurate proportional exits across children
- Withdrawal security through fixed proportional logic (no keeper manipulation possible)
- Flexibility for deposits and rebalancing with proper invariant checks

## Related ADRs
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Defines parent-child relationship and multi-child allocation
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - totalAssets contributes to parent NAV
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Data parameter may contain command sequences
