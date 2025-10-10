# ADR-0006: Child Strategy Interface

## Status
Accepted (Updated 2025-01-10)

## Date
2024-10-01 (Last Updated: 2025-01-10)

## Change Log
- **2025-01-10**: Simplified to single `flashLoanToken` parameter (removed separate `providedToken`/`expectedToken`)

## Context
Child strategies are single-owner execution engines with no internal share accounting. Parent vault controls all asset movements and debt obligations.

**Implementation Note (Updated 2025-01-10):**
The IChildStrategy interface is implemented by LeveragedStrategy base contract, which uses inheritance-based architecture for multi-protocol support. See [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) for implementation details.

## Requirements
- **Single caller:** only parent can call operations.
- **Sync operations:** no user queues, no internal epochs.
- **Multi-token support:** accept any token for deposit/withdraw, not just base asset.
- **Debt obligation pattern:** parent specifies debt that child strategy owes back.
- **Minimal interface:** only essential functions for strategy execution.
- **No internal shares:** parent owns all assets directly, no share minting in child.

**Related Requirements:**
- [FR-005: Multi-Token Support](../requirements/functional-requirements.md#fr-005-multi-token-support)
- [TR-003: Child Strategy Interface](../requirements/technical-requirements.md#tr-003-child-strategy-interface)
- [SR-001: Access Control](../requirements/security-requirements.md#sr-001-access-control)
- [SR-009: Monitoring and Auditing](../requirements/security-requirements.md#sr-009-monitoring-and-auditing)

## Decision

### Solidity Interface

```solidity
interface IChildStrategy {
    // ============ Core Operations ============

    /// @notice Deploy assets into strategy
    /// @param depositToken Token being deposited (PT, USDC, ETH, etc.)
    /// @param depositAmount Amount of deposit token
    /// @param flashLoanToken Token used for flash loans (address(0) if none)
    /// @param providedAmount Amount of flash loan token provided by parent
    /// @param expectedAmount Amount of flash loan token parent expects back
    /// @param data Strategy-specific execution data
    function deposit(
        address depositToken,
        uint256 depositAmount,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    /// @notice Withdraw from strategy by percentage
    /// @param percentage Percentage to withdraw (1e18 = 100%)
    /// @param outputToken Desired output token
    /// @param flashLoanToken Token used for flash loans (address(0) if none)
    /// @param providedAmount Amount of flash loan token provided by parent
    /// @param expectedAmount Amount of flash loan token parent expects back
    /// @param data Strategy-specific execution data
    /// @return actualWithdrawn Amount actually withdrawn in outputToken
    function withdraw(
        uint256 percentage,
        address outputToken,
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external returns (uint256 actualWithdrawn);

    /// @notice Rebalance strategy
    /// @param flashLoanToken Token used for flash loans (address(0) if none)
    /// @param providedAmount Amount of flash loan token provided by parent
    /// @param expectedAmount Amount of flash loan token parent expects back
    /// @param data Strategy-specific execution data
    function rebalance(
        address flashLoanToken,
        uint256 providedAmount,
        uint256 expectedAmount,
        bytes calldata data
    ) external;

    // ============ View Functions ============

    /// @notice Get strategy's net asset value in base asset terms
    function totalAssets() external view returns (uint256);
}
```

### Flash Loan Token Pattern with netFlow Tracking

**Core Principle:** Single flash loan token per parent vault transaction enables efficient netFlow tracking.

**Key Changes (2025-01-10):**
- Consolidated `providedToken` and `expectedToken` into single `flashLoanToken` parameter
- Enables parent vault to track flash loan debt with simple `netFlow` counter
- Parent validates `netFlow == 0` at transaction end to ensure flash loan is fully repaid

**netFlow Tracking in Parent Vault:**
```solidity
function userWithdraw(uint256 amount) external nonReentrant {
    address flashLoanToken = USDC;
    uint256 netFlow = 0;

    // Get flash loan from Aave/Balancer
    uint256 flashLoanAmount = 1000e6;

    // Call Child Strategy A
    childA.withdraw(
        percentage: 50%,
        outputToken: PT_TOKEN,
        flashLoanToken: USDC,
        providedAmount: 1000e6,    // Parent provides
        expectedAmount: 0,          // Child doesn't return yet
        data: commands
    );
    netFlow += 1000e6;  // Debt increased

    // Call Child Strategy B
    childB.rebalance(
        flashLoanToken: USDC,
        providedAmount: 0,
        expectedAmount: 1000e6,     // Child must return
        data: commands
    );
    netFlow -= 1000e6;  // Debt decreased

    // Validate flash loan fully repaid
    require(netFlow == 0, "Flash loan not fully repaid");
}
```

**Benefits:**
1. **Single Token Per Transaction**: Only one flash loan token per parent vault call
2. **Flexible Multi-Child Operations**: Flash loan can flow through multiple children
3. **Automatic Validation**: `netFlow == 0` ensures complete repayment
4. **Prevents Theft**: Keeper cannot steal flash loan tokens

**Security Properties:**
- ✅ Keeper Cannot Steal Flash Loan: Parent validates `netFlow == 0`
- ✅ Idle Token Protection: Child validates idle balances during operations
- ✅ Single Token Enforcement: Only one `flashLoanToken` per transaction
- ✅ No Intermediate Theft: Even if one child doesn't return, `netFlow != 0` will revert

**Deposit Operation Examples:**

```solidity
// Scenario 1: Standard leverage with flash loan
ptChildStrategy.deposit(
    USDC_TOKEN, 1000e6,      // depositToken/Amount: main deposit
    USDC_TOKEN, 7000e6,      // flashLoanToken, providedAmount: flash loan liquidity
    7000e6,                  // expectedAmount: must repay flash loan
    leverageData
);

// Scenario 2: Deposit without flash loan
ptChildStrategy.deposit(
    PT_TOKEN, 1500,          // depositToken/Amount: deposit PT directly
    address(0), 0, 0,        // No flash loan
    depositData
);

// Scenario 3: Multi-child rebalance - intermediate child (receives flash loan)
childA.deposit(
    PT_TOKEN, 1000,
    USDC_TOKEN, 5000e6,      // flashLoanToken, providedAmount: receive flash loan
    0,                       // expectedAmount: don't return yet
    commands
);

// Scenario 4: Multi-child rebalance - final child (returns flash loan)
childB.deposit(
    USDC_TOKEN, 500e6,
    USDC_TOKEN, 0,           // flashLoanToken, providedAmount: already received
    5000e6,                  // expectedAmount: must return flash loan
    commands
);

// Child strategy execution:
function deposit(
    address depositToken, uint256 depositAmount,
    address flashLoanToken, uint256 providedAmount, uint256 expectedAmount,
    bytes calldata data
) external {
    // Execute strategy with depositToken and flash loan liquidity
    Command[] memory commands = abi.decode(data, (Command[]));
    _executeCommands(commands);

    // Approve expected tokens for parent collection
    if (flashLoanToken != address(0) && expectedAmount > 0) {
        IERC20(flashLoanToken).approve(parent, expectedAmount);
    }
}
```

**Withdrawal Operation Examples:**

```solidity
// Scenario 1: Standard deleverage with flash loan
uint256 withdrawn = child.withdraw(
    1e17,                    // percentage: 10%
    USDC_TOKEN,              // outputToken: receive USDC
    USDT_TOKEN,              // flashLoanToken
    200e6,                   // providedAmount: flash loan for debt repayment
    200e6,                   // expectedAmount: must repay flash loan
    standardParams
);

// Scenario 2: Withdraw without flash loan
uint256 amount = child.withdraw(
    5e17,                    // percentage: 50%
    USDC_TOKEN,              // outputToken
    address(0), 0, 0,        // No flash loan
    simpleParams
);

// Scenario 3: Multi-child rebalance - first child returns PT (receives flash loan)
uint256 ptAmount = childA.withdraw(
    1e18,                    // percentage: 100%
    PT_TOKEN,                // outputToken: receive PT directly
    USDC_TOKEN,              // flashLoanToken
    2000e6,                  // providedAmount: flash loan for debt repayment
    0,                       // expectedAmount: don't return yet (intermediate step)
    transferParams
);

// Scenario 4: Multi-child rebalance - second child uses PT (returns flash loan)
childB.deposit(
    PT_TOKEN, ptAmount,      // Use PT from previous withdraw
    USDC_TOKEN,              // flashLoanToken (same as step 3)
    0,                       // providedAmount: already provided in step 3
    2000e6,                  // expectedAmount: must return flash loan now
    depositParams
);
```

### Position Transfer Flow

**Key Innovation:** No special `transferPosition()` function needed - use existing deposit/withdraw with flash loan.

**Example: Transfer PT position from Morpho strategy to Aave strategy**

```solidity
function transferPosition() external nonReentrant {
    address flashLoanToken = USDT;
    uint256 netFlow = 0;

    // Get flash loan
    uint256 flashLoanAmount = 2000e6;

    // Step 1: Withdraw PT from Morpho child
    uint256 ptAmount = morphoChild.withdraw(
        1e18,                    // percentage: 100%
        PT_TOKEN,                // outputToken: receive PT directly
        flashLoanToken,          // flashLoanToken: USDT
        2000e6,                  // providedAmount: flash loan for debt repayment
        0,                       // expectedAmount: don't return yet
        morphoParams
    );
    netFlow += 2000e6;  // Debt increased

    // Step 2: Deposit PT into Aave child
    aaveChild.deposit(
        PT_TOKEN, ptAmount,      // depositToken/Amount: deposit received PT
        flashLoanToken,          // flashLoanToken: USDT (same token)
        0,                       // providedAmount: already provided in step 1
        2000e6,                  // expectedAmount: strategy borrows and returns
        aaveCommands
    );
    netFlow -= 2000e6;  // Debt decreased

    // Validate flash loan repaid
    require(netFlow == 0, "Flash loan not fully repaid");

    // Net result: PT position moved from Morpho to Aave, flash loan repaid
}
```

### Proportional Exit Logic

**Fair withdrawal:** Each user gets exactly their proportional share of actual assets.

```solidity
function withdraw(
    uint256 percentage,
    address outputToken,
    address flashLoanToken,
    uint256 providedAmount,
    uint256 expectedAmount,
    bytes calldata data
) external onlyParent returns (uint256 actualWithdrawn) {

    // Calculate proportional amounts based on percentage
    uint256 currentCollateral = _getCollateralAmount();
    uint256 currentDebt = _getDebtAmount();

    uint256 collateralToWithdraw = (currentCollateral * percentage) / 1e18;
    uint256 debtToRepay = (currentDebt * percentage) / 1e18;

    // Execute proportional unwind using flash loan liquidity
    actualWithdrawn = _executeWithdrawal(
        collateralToWithdraw,
        debtToRepay,
        outputToken,
        flashLoanToken,
        providedAmount,
        data
    );

    // Approve parent to collect withdrawn assets and flash loan repayment
    if (outputToken == flashLoanToken && flashLoanToken != address(0)) {
        // Same token: approve sum of both amounts
        uint256 totalAmount = actualWithdrawn + expectedAmount;
        if (totalAmount > 0) {
            IERC20(outputToken).approve(parent, totalAmount);
        }
    } else {
        // Different tokens: approve separately
        if (actualWithdrawn > 0) {
            IERC20(outputToken).approve(parent, actualWithdrawn);
        }
        if (flashLoanToken != address(0) && expectedAmount > 0) {
            IERC20(flashLoanToken).approve(parent, expectedAmount);
        }
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
- [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) - Inheritance-based implementation of IChildStrategy
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Defines parent-child relationship and multi-child allocation
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - totalAssets contributes to parent NAV
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Data parameter contains command sequences

## Requirements Traceability
- **FR-005.1**: Flexible Token Operations - Multi-token support for deposit/withdraw, direct position transfers
- **FR-005.2**: Provided/Expected Token Pattern - Parent explicitly specifies provided/expected tokens
- **TR-003.1**: Core Interface Requirements - Single caller, sync operations, multi-token support implemented
- **TR-003.2**: Function Signatures - IChildStrategy interface with deposit/withdraw/rebalance/totalAssets
- **TR-003.3**: Proportional Exit Logic - Fixed proportional withdrawal logic implemented
- **SR-001.1**: Role-Based Permissions - Single-owner constraint enforced (only parent can call)
- **SR-009.1**: Event Logging - Comprehensive logging for money flow tracking and financial reconstruction
- **SR-009.2**: Audit Requirements - Event logging enables complete audit trail and PnL calculation
