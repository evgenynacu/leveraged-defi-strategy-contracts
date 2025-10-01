# ADR 0005: Child Vault Interface

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
