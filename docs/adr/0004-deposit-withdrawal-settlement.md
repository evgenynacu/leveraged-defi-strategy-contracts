# ADR 0004: Deposit & Withdrawal Settlement

## Context
We need fair batching without oracle reliance, supporting multiple children and proportional exits.

## Requirements
- **Batched deposits:** users get receipts; no instant mint.
- **Atomic epoch:** one keeper tx executes allocation + mint/burn.
- **Entry fairness:** use deltaNAV; do not dilute existing holders.
- **Exit proportionality:** withdraw exact fraction f of every asset (incl. cash buffer).
- **No substitution:** cash buffer can only cover its proportional share.
- **Partial fills:** if some child is illiquid, deliver what’s realizable and queue the rest.
- **Idempotency:** safe re-runs on tx failure.

## Decision
- **Deposits:**
    1) Queue receipts.
    2) `processEpoch()`: compute `NAV_before`, deposit into children, compute `NAV_after`, mint by `deltaNAV` and distribute shares pro-rata to receipts.
- **Withdrawals:**
    1) Compute `f = shares/totalShares`.
    2) For each asset j (including cash): target_units_j = f * units_j_before.
    3) Deliver units_j up to what is withdrawable; queue remainder per asset.
    4) Burn shares proportionally to delivered fraction; burn the rest as later tranches settle.

## Consequences
- No NAV-based over/underpayments.
- Predictable proportional exits, with transparent partial-fill queues.
