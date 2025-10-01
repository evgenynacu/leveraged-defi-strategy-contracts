# ADR-0007: Child Vault Interface

## Status
Accepted

## Date
2024-10-01

## Context
Children are single-owner strategy adapters with synchronous I/O and PnL-based accounting.

## Requirements
- **Single caller:** only parent can deposit/withdraw.
- **Sync operations:** no user queues, no internal epochs.
- **Stable interface:** minimal, consistent across strategies.
- **PnL-based totalAssets:** avoid external oracle spot where possible.
- **Share semantics:** maintain internal shares for proportional math; ERC20 not required.

## Decision
- **Interface (view):**
    - `totalAssets()` — PnL-based value.
    - `totalShares()` — internal supply counter.
    - `pricePerShare()` — 1e18 scaled.
- **Interface (mutating, onlyParent):**
    - `deposit(assets,data) -> shares` - deposit assets and return shares, use data to execute the strategy (routes etc.).
    - `withdraw(shares,data) -> assets` - withdraw shares and return assets, use data to execute the strategy (routes etc.). 
- **Rounding:** round down to the child on mint/burn to avoid over-issuance.

## Consequences
- Easy integration of heterogeneous strategies.
- Parent can perform accurate proportional exits across children.

## Related ADRs
- [ADR-0004: Vault Architecture v2](0004-vault-architecture.md) - Defines parent-child relationship and multi-child allocation
- [ADR-0005: NAV Calculation Method](0005-nav-calculation-method.md) - totalAssets contributes to parent NAV
- [ADR-0003: Command-Based Execution](0003-command-based-execution.md) - Data parameter may contain command sequences
