# ADR-0002: Vault Architecture with Hierarchical Composition

## Status
Accepted

## Context

We design a vault system that can either hold assets directly in a strategy (e.g., leveraged PT) or hold shares of other vaults in a hierarchical tree structure. All vaults share a common base interface. Shares are issued on deposit and burned on withdrawal. Asset valuation (NAV) is based on oracle pricing and/or underlying vaults’ totalAssets.

A performance fee mechanism is needed to reward managers while avoiding double charging. We use a global high-water mark (HWM) based on price per share (PPS).

## Decisions

### Base Vault
- deposit(uint256 assets, uint256 minShares, bytes data)
  - Mint shares based on assets provided, respecting minShares.
- withdraw(uint256 shares, uint256 minAssets, bytes data)
  - Burn shares and return underlying assets, respecting minAssets.

- totalAssets()
  - Return NAV estimation (using oracle pricing or child vaults).
- totalSupply()
  - Return current shares supply.
- availableCapacity()
  - Return maximum amount of assets that can be deposited into the vault.
  - Considers vault capacity limits, underlying strategy constraints, and available liquidity.
  - For hierarchical vaults, aggregates available capacity from child vaults.
- Internal hooks for extensions (_deploy, _withdrawUnderlying, etc.).

### Performance Fee with Vault-Level HWM
- Vault tracks a global HWM of PPS (totalAssets / totalSupply).
- On fee-trigger events (withdrawal, rebalance, roll, refinance, or explicit harvest()):
- Compute current PPS.
  - If PPS > HWM:
    - Delta is profit.
    - Apply performance fee (configurable bps).
    - Issue fee shares to manager (or transfer assets).
    - Update HWM = current PPS.
  - If PPS <= HWM: no fee charged.
- This ensures fees are taken only on new net profits and avoids charging twice after drawdowns.

### Hierarchical Composition
- Any vault can hold other vaults as “assets.”
- Parent vault NAV is sum of children’s totalAssets.
- Deposit/withdraw flows pass assets or shares down to children.
- This enables layered strategies (e.g., high-level vault allocating across multiple PT vaults).

### Simplicity of Flow
- Deposits and withdrawals are synchronous: no backend queues or async execution.
- Users provide execution parameters (data), covering routing/swap specifics.
- Users pay their own gas for entry/exit, removing centralization/trust in off-chain actors.
- Users can exit and enter at any time: the vault is fully liquid.

### Alternatives Considered
- Yearn v3 vaults: provide many primitives, but to implement fair PPS-based fee and direct parameterized deposits/withdrawals requires significant workarounds.
- Custom design chosen: direct control over fee logic, synchronous flows, and composability via vault nesting.
