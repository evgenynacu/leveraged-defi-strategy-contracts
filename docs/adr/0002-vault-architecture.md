# ADR 0002: Vault Architecture v2

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
- **Parent/child design:** Parent holds users’ funds and owns N child strategies.
- **Epochs:** Users submit deposits/withdrawals into queues; `processEpoch()` executes atomically.
- **Entry:** Mint parent shares from **deltaNAV = NAV_after − NAV_before** after real child deposits.
- **Exit:** Redeem strictly by **proportional units** of each asset (incl. cash); optional conversion to cash is done **proportionally**.
- **Child vaults:** single owner (parent), synchronous `deposit/withdraw`, PnL-based accounting.
- **Rounding:** round down to the vault on share/asset conversions to avoid dust exploits.

## Consequences
- Honest entry and exit independent of oracle noise.
- Simple child adapters; all complexity (queues/epochs/mint/burn) lives in the parent.
- Predictable, auditable accounting.
