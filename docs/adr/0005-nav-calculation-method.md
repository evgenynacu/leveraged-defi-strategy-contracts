# ADR-0005: NAV Calculation Method

## Status
Accepted

## Date
2024-09-26

## Context
Oracle spot prices for assets like sUSDe can be stale/biased. NAV must reflect real economic PnL, not fragile spot quotes.

## Requirements
- **PnL-based NAV:** prefer protocol-native measures over external oracles (e.g. PT token price is identified using Pendle Oracle and current implied yield).
- **Componentization:** NAV is the sum of well-defined components.
- **Precision:** fixed-point math with 1e18 scale; explicit rounding rules.
- **Deterministic snapshots:** `NAV_before` and `NAV_after` within one tx.
- **Auditability:** expose component breakdowns via events/views.

## Decision
- **NAV =**
    - Cash balances (stablecoins, unwrapped units).
    - PT / discounted assets **fair value** (protocol curve/discount; not raw DEX spot).
    - Debts (principal + accrued interest) from lending protocols.
    - Claimable rewards **only if** realizable within epoch (otherwise ignore).
- **Entry:** shares minted from **deltaNAV** only.
- **Exit:** pay realized asset units; do **not** pay by NAV estimate.

## Consequences
- Eliminates oracle-lag arbitrage at entry/exit.
- NAV mirrors strategy economics; sharePrice can deviate from instantaneous liquidation value but remains fair to all holders.

## Related ADRs
- [ADR-0004: Vault Architecture v2](0004-vault-architecture.md) - Uses NAV for deltaNAV-based share minting
- [ADR-0006: Deposit & Withdrawal Settlement](0006-deposit-withdrawal-settlement.md) - Applies NAV snapshots in epoch processing
