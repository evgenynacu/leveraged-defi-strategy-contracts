# ADR-0009: Selective Withdrawal with Tolerance-Based Validation

## Status
Accepted

## Date
2025-01-10

## Context

### Problem
When parent vault has many child strategies (e.g., 10+), withdrawing proportionally from ALL strategies becomes impractical:
- **Gas costs:** Each strategy withdrawal is expensive (protocol operations + swaps)
- **Transaction limits:** Multiple strategy operations may exceed block gas limit
- **Inefficiency:** If some strategies have low liquidity, touching all strategies is wasteful

### Original Approach (Impractical)
Strict proportional withdrawal from all strategies:
```solidity
// Withdraw 10% from user
for (uint i = 0; i < 10; i++) {
    strategies[i].withdraw(10%);  // Touch ALL strategies
}
// Problem: 10+ external calls, high gas, may not fit in block
```

### Desired Approach
**Hybrid model**: Offchain keeper selects which strategies to withdraw from, onchain contract validates fairness.

## Requirements
- **Gas Efficiency:** Enable withdrawals from 1-3 strategies instead of all
- **Fairness:** Users get correct percentage of total NAV (within tolerance)
- **Flexibility:** Keeper chooses optimal strategies (based on liquidity, fees, etc.)
- **Security:** Prevent keeper from manipulating withdrawal amounts

**Related Requirements:**
- [FR-006: Efficient Gas Usage](../requirements/functional-requirements.md)
- [SR-002: Economic Security](../requirements/security-requirements.md)
- [TR-004: Withdrawal Validation](../requirements/technical-requirements.md)

## Decision

### Architecture: Two-Level Validation

**Level 1: Parent Vault Validation**
- Validates total withdrawn amount matches expected percentage of total NAV
- Uses configurable tolerance to allow minor deviations
- Keeper selects which strategies to withdraw from

**Level 2: Child Strategy Validation**
- Each child validates its own proportional withdrawal
- Protects idle token balances (already implemented in LeveragedStrategy)
- Prevents keeper manipulation within individual strategy

### Implementation

#### 1. Parent Vault Interface

```solidity
interface IParentStrategy {
    struct WithdrawalRequest {
        address strategy;
        uint256 percentage;      // % of this strategy's NAV to withdraw
        address outputToken;
        address flashLoanToken;
        uint256 providedAmount;
        uint256 expectedAmount;
        bytes data;
    }

    /// @notice Withdrawal tolerance in basis points (e.g., 50 = 0.5%)
    function withdrawalToleranceBps() external view returns (uint256);

    /// @notice Withdraw with validation
    function withdraw(
        uint256 shares,
        WithdrawalRequest[] calldata requests,
        address receiver
    ) external returns (uint256 assets);
}
```

#### 2. Validation Logic

```solidity
function withdraw(
    uint256 shares,
    WithdrawalRequest[] calldata requests,
    address receiver
) external nonReentrant returns (uint256 assets) {
    require(requests.length > 0, "No strategies");

    // 1. Calculate expected withdrawal based on shares
    uint256 totalNAV = getTotalNAV();  // Sum of all child strategies' totalAssets()
    uint256 expectedAssets = convertToAssets(shares);
    uint256 expectedPercentageOfNAV = (expectedAssets * 1e18) / totalNAV;

    // 2. Execute withdrawals from selected strategies
    uint256 totalWithdrawn = 0;
    for (uint i = 0; i < requests.length; i++) {
        WithdrawalRequest memory req = requests[i];

        uint256 withdrawn = IChildStrategy(req.strategy).withdraw(
            req.percentage,
            req.outputToken,
            req.flashLoanToken,
            req.providedAmount,
            req.expectedAmount,
            req.data
        );

        totalWithdrawn += withdrawn;
    }

    // 3. Validate: total withdrawn matches expected within tolerance
    uint256 actualPercentageOfNAV = (totalWithdrawn * 1e18) / totalNAV;

    uint256 toleranceBps = withdrawalToleranceBps;  // e.g., 50 bps = 0.5%
    uint256 tolerance = (expectedPercentageOfNAV * toleranceBps) / 10000;

    require(
        actualPercentageOfNAV >= expectedPercentageOfNAV - tolerance &&
        actualPercentageOfNAV <= expectedPercentageOfNAV + tolerance,
        "Invalid withdrawal amount"
    );

    // 4. Transfer assets to receiver
    _transfer(receiver, totalWithdrawn);

    emit Withdrawn(msg.sender, shares, totalWithdrawn, requests.length);
    return totalWithdrawn;
}
```

#### 3. Tolerance Configuration

```solidity
// Recommended default: 50 bps (0.5%)
uint256 public constant DEFAULT_WITHDRAWAL_TOLERANCE_BPS = 50;

// Configurable by governance
uint256 public withdrawalToleranceBps = DEFAULT_WITHDRAWAL_TOLERANCE_BPS;

function setWithdrawalTolerance(uint256 newToleranceBps) external onlyOwner {
    require(newToleranceBps <= 200, "Tolerance too high");  // Max 2%

    uint256 oldTolerance = withdrawalToleranceBps;
    withdrawalToleranceBps = newToleranceBps;

    emit WithdrawalToleranceUpdated(oldTolerance, newToleranceBps);
}
```

### Example: Selective Withdrawal

**Scenario:** User wants to withdraw 10% of their shares. Vault has 5 strategies.

**Offchain (Keeper Decision):**
```javascript
// Total NAV = 1M USDC across 5 strategies
// User wants 10% = 100k USDC

// Keeper analysis:
// - Strategy A: 400k NAV, high liquidity ✓
// - Strategy B: 300k NAV, high liquidity ✓
// - Strategy C: 200k NAV, low liquidity (skip)
// - Strategy D: 50k NAV, locked position (skip)
// - Strategy E: 50k NAV, high fees (skip)

// Keeper decision: withdraw from A and B only
withdrawalRequests = [
    {
        strategy: strategyA,
        percentage: 25%,  // 25% of 400k = 100k USDC
        outputToken: USDC,
        // ... other params
    }
]
// OR distribute across A and B:
// A: 12.5% of 400k = 50k
// B: 16.7% of 300k = 50k
// Total = 100k ✓
```

**Onchain (Contract Validation):**
```solidity
// Expected: 100k / 1M = 10% of NAV
// Actual: 100k / 1M = 10% of NAV
// Within tolerance (0.5%) ✓
// Withdrawal succeeds
```

### Child Strategy Protection (Already Implemented)

Child strategies maintain existing validation in `LeveragedStrategy.withdraw()`:
1. Validate percentage within bounds (0 < percentage <= 100%)
2. Execute proportional protocol operations (repay debt, withdraw collateral)
3. Validate idle token balances remain proportional
4. Keeper can only provide SWAP commands (no protocol manipulation)

See `LeveragedStrategy._executeProportionalWithdraw()` (lines 369-396).

### Why Tolerance is Needed

**Sources of deviation:**
1. **Oracle Price Updates:** NAV calculated with current prices, but prices may change during tx
2. **Swap Slippage:** Actual swap amounts may differ slightly from expected
3. **Protocol State Changes:** Lending protocol interest accrual during tx
4. **Rounding Errors:** Integer division in percentage calculations

**Example calculation:**
```
Expected: 10.00% of NAV
Actual:   10.04% of NAV (due to favorable swap)
Tolerance: 0.5%
Result: ✓ PASS (within 10% ± 0.5%)
```

### Security Properties

✅ **Keeper Cannot Steal:**
- Parent validates total withdrawal matches expected percentage
- Child validates proportional operations
- Two-level validation prevents manipulation

✅ **User Fairness:**
- Users get correct percentage of NAV within tolerance
- Tolerance is small (0.5%) and governance-controlled

✅ **Gas Efficiency:**
- Withdraw from 1-3 strategies instead of all
- Keeper optimizes for liquidity, fees, gas costs

✅ **Flexibility:**
- Keeper can avoid low-liquidity strategies
- Can skip locked or expensive positions
- Enables emergency withdrawals from liquid strategies only

## Consequences

### Positive
- ✅ **Gas Savings:** 5-10x reduction in gas costs for multi-strategy vaults
- ✅ **Transaction Safety:** Withdrawals fit within gas limits even with many strategies
- ✅ **Operational Flexibility:** Keeper can optimize withdrawal execution
- ✅ **Emergency Resilience:** Can withdraw from liquid strategies if some are locked

### Negative
- ❌ **Complexity:** Two-level validation adds conceptual overhead
- ❌ **Keeper Dependency:** Requires offchain keeper to select strategies
- ❌ **Potential Imbalance:** Frequently-withdrawn-from strategies may become depleted

### Mitigation
- **Keeper Automation:** Provide reference implementation with optimal strategy selection
- **Monitoring:** Track strategy balance distribution and trigger rebalances
- **Documentation:** Clear explanations of validation logic and tolerance

## Alternatives Considered

### 1. Strict Proportional Withdrawal (Original)
**Rejected:** Impractical for gas costs with many strategies.

### 2. Round-Robin Strategy Selection
**Rejected:** May select illiquid strategies, causing high slippage.

### 3. User-Specified Strategy Selection
**Rejected:** Requires users to understand strategy states, complex UX.

### 4. No Validation (Trust Keeper)
**Rejected:** Keeper could steal funds by selecting unfavorable strategies.

## Related ADRs
- [ADR-0006: Child Strategy Interface](0006-child-vault-interface.md) - Defines child strategy `withdraw()` interface
- [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) - Child-level validation implementation
- [ADR-0005: Deposit/Withdrawal Settlement](0005-deposit-withdrawal-settlement.md) - Parent vault withdrawal flow

## Requirements Traceability
- **FR-006.1**: Gas Efficiency - Selective withdrawal reduces gas by 5-10x
- **FR-006.2**: Transaction Limits - Enables withdrawals even with 10+ strategies
- **SR-002.1**: Economic Security - Two-level validation prevents fund theft
- **SR-002.2**: User Fairness - Tolerance ensures users get fair share
- **TR-004.1**: Withdrawal Validation - Parent validates total, child validates proportional
- **TR-004.2**: Configurable Tolerance - Governance-controlled tolerance parameter

## Implementation Checklist
- [x] Created `IParentStrategy` interface with `WithdrawalRequest` struct
- [x] Updated `IChildStrategy` documentation with selective withdrawal model
- [x] Updated `LeveragedStrategy.withdraw()` documentation
- [ ] Implement parent vault with tolerance-based validation
- [ ] Add governance functions for tolerance management
- [ ] Create keeper reference implementation for strategy selection
- [ ] Add monitoring for strategy balance distribution
- [ ] Write integration tests with multiple strategies
- [ ] Document keeper strategy selection algorithm
