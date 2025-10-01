# ADR 0009: Multi-level Vaults

## Context
Parent aggregates multiple child strategies with different liquidity/yield profiles while preserving proportional exits.

## Requirements
- **Allocation policy:** target weights per child.
- **Liquidity awareness:** respect child withdrawability without violating proportionality over time.
- **Proportional exits:** maintain portfolio mix for each withdrawal.
- **Transparency:** expose per-child values and allocations.

## Decision
- **Deposits:** distribute by target allocation during epoch; reconcile drift over future epochs.
- **Withdrawals:** compute fraction f; attempt to withdraw f * child.totalShares() from each child.
    - If a child is short on liquidity, deliver its realizable part now and queue remaining units for later epochs; do **not** substitute from other children beyond their own f-share.
- **Accounting:** parent NAV derives from Σ child.totalAssets() + cash; proportional math relies on child shares.

## Consequences
- Honest portfolio-fraction exits in heterogeneous, multi-strategy setups.
- Predictable rebalancing via future epochs without breaking fairness.
