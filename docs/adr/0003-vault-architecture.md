# ADR-0003: Vault Architecture v2

## Status
Accepted

## Date
2024-09-26

## Context
We need a safe, fair, and simple vault system with multi-strategy composition. Oracle-based NAV can drift (~±0.8%), so entry/exit must not rely on noisy spot oracles.

## Requirements
- **Security:** users must not operate strategies; only the vault orchestrates flows.
- **Fair entry:** no value transfer between cohorts at deposit time.
- **Fair exit:** withdrawers receive exactly their pro-rata share of *actual* assets, not theoretical NAV.
- **Composability:** support multiple child vaults.
- **Simplicity:** child strategies have one owner (parent) and sync I/O.
- **Determinism:** explicit rounding policy and idempotent processing.

## Decision
- **Parent/child design:** Parent holds users' funds and owns N child strategies.
- **Epochs:** Users submit deposits/withdrawals into queues; `processEpoch()` executes atomically.
- **Entry:** Mint parent shares from **deltaNAV = NAV_after − NAV_before** after real child deposits.
- **Exit:** Redeem strictly by **proportional units** of each asset (incl. cash); optional conversion to cash is done **proportionally**.
- **Child vaults:** single owner (parent), synchronous `deposit/withdraw`, PnL-based accounting.
- **Rounding:** round down to the vault on share/asset conversions to avoid dust exploits.

### Multi-Child Allocation Strategy
When multiple child vaults are present:
- **Target weights:** Each child vault has a configurable target allocation percentage (e.g., Child A: 60%, Child B: 40%).
- **Keeper-driven allocation:** Keeper (off-chain) determines actual allocation per epoch based on:
  - Target weights and current allocations
  - Available liquidity in underlying protocols
  - Lending protocol limits (borrow caps, collateral caps)
  - Gas optimization (may allocate 100% to one child if within threshold)
- **Threshold-based flexibility:** If actual allocation is within `target ± threshold`, deposits may be directed entirely to one child for gas efficiency or liquidity management.
  - Example: If Child A target is 60% ± 5%, and current is 58%, new deposits can go 100% to Child A until it reaches 65%.
- **Rebalancing:** When actual weights drift beyond threshold, reconciliation happens via:
  - **Organic rebalancing:** Future deposit/withdrawal flows adjusted to bring weights back to target (no forced liquidations)
  - **Active rebalancing:** Keeper-initiated `rebalance()` function to move assets between children when necessary
- **Liquidity awareness:** Respect each child's withdrawability; if a child is illiquid during withdrawal, deliver its realizable portion and queue the remainder (see ADR-0005).
- **Transparency:** Expose per-child values and current vs target allocations via view functions.

### Parent Vault Rebalancing

Parent vault implements `rebalance()` for moving assets between children:

```solidity
function rebalance(
    uint256[] calldata withdrawals,  // shares to withdraw from each child
    uint256[] calldata deposits,     // assets to deposit to each child
    bytes[] calldata withdrawParams, // params for each child withdrawal
    bytes[] calldata depositCommands // commands for each child deposit
) external onlyKeeper {
    uint256 navBefore = _calculateTotalNAV();

    // 1. Withdraw from over-allocated children
    for (uint i = 0; i < withdrawals.length; i++) {
        if (withdrawals[i] > 0) {
            children[i].withdraw(withdrawals[i], withdrawParams[i]);
        }
    }

    // 2. Deposit to under-allocated children
    for (uint i = 0; i < deposits.length; i++) {
        if (deposits[i] > 0) {
            children[i].deposit(deposits[i], depositCommands[i]);
        }
    }

    uint256 navAfter = _calculateTotalNAV();

    // INVARIANT: NAV should not decrease significantly (only gas/slippage)
    require(navAfter >= navBefore * 99 / 100, "NAV decreased too much");

    // INVARIANT: weights must be within thresholds after rebalance
    _checkWeightInvariants();
}
```

**Use cases:**
- Move assets from Child A to Child B when weights drift beyond threshold
- Migrate from deprecated strategy to new strategy
- Respond to changing market conditions (e.g., better yield in different protocol)
- Reduce exposure to strategy approaching capacity limits

## Consequences
- Honest entry and exit independent of oracle noise.
- Simple child adapters; all complexity (queues/epochs/mint/burn) lives in the parent.
- Predictable, auditable accounting.

## Related ADRs
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - Defines how NAV is calculated for entry/exit
- [ADR-0005: Deposit & Withdrawal Settlement](0005-deposit-withdrawal-settlement.md) - Details epoch processing mechanics
- [ADR-0006: Child Vault Interface](0006-child-vault-interface.md) - Specifies child vault contract interface
