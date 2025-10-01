# ADR-0004: Vault Architecture v2

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
- **Deposit distribution:** New deposits are allocated to children based on target weights, adjusted to bring actual allocations closer to targets.
- **Threshold-based flexibility:** If actual allocation is within `target ± threshold`, deposits may be directed entirely to one child for gas efficiency or liquidity management.
  - Example: If Child A target is 60% ± 5%, and current is 58%, new deposits can go 100% to Child A until it reaches 65%.
- **Rebalancing:** When actual weights drift beyond threshold, future epochs gradually reconcile by adjusting deposit flows (no forced liquidations).
- **Liquidity awareness:** Respect each child's withdrawability; if a child is illiquid during withdrawal, deliver its realizable portion and queue the remainder (see ADR-0006).
- **Transparency:** Expose per-child values and current vs target allocations via view functions.

## Consequences
- Honest entry and exit independent of oracle noise.
- Simple child adapters; all complexity (queues/epochs/mint/burn) lives in the parent.
- Predictable, auditable accounting.

## Related ADRs
- [ADR-0005: NAV Calculation Method](0005-nav-calculation-method.md) - Defines how NAV is calculated for entry/exit
- [ADR-0006: Deposit & Withdrawal Settlement](0006-deposit-withdrawal-settlement.md) - Details epoch processing mechanics
- [ADR-0007: Child Vault Interface](0007-child-vault-interface.md) - Specifies child vault contract interface
