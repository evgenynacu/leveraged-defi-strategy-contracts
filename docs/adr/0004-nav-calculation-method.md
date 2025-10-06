# ADR-0004: NAV Calculation Method

## Status
Accepted

## Date
2024-09-26

## Context
Oracle spot prices for assets like sUSDe can be stale/biased. NAV must reflect real economic PnL, not fragile spot quotes. Child strategies provide direct NAV contributions without internal share accounting.

## Requirements
- **PnL-based NAV:** prefer protocol-native measures over external oracles (e.g. PT token price is identified using Pendle Oracle and current implied yield).
- **Componentization:** NAV is the sum of well-defined components.
- **Precision:** fixed-point math with 1e18 scale; explicit rounding rules.
- **Deterministic snapshots:** `NAV_before` and `NAV_after` within one tx.
- **Auditability:** expose component breakdowns via events/views.

**Related Requirements:**
- [TR-002: NAV Calculation](../requirements/technical-requirements.md#tr-002-nav-calculation)
- [SR-005: Oracle Security](../requirements/security-requirements.md#sr-005-oracle-security)
- [PR-005: Oracle Performance](../requirements/performance-requirements.md#pr-005-oracle-performance)

## Decision

### NAV Formula

```
NAV = Σ(cash_i) + Σ(collateral_j × price_j) - Σ(debt_k × (1 + interest_k)) + rewards
```

Where:
- **cash_i**: Stablecoin balances (USDC, USDT, etc.) valued at 1:1
- **collateral_j**: Protocol-specific assets (PT tokens, LP tokens, yield-bearing tokens)
- **price_j**: Fair value from protocol oracles (see below)
- **debt_k**: Borrowed amounts from lending protocols (Morpho, Aave, etc.)
- **interest_k**: Accrued interest from lending protocol's internal accounting
- **rewards**: Claimable rewards **only if** realizable within current epoch (otherwise ignore)

### Oracle Selection for Asset Pricing

**PT Tokens (Pendle):**
- Use `PendleOracle.getPtToAssetRate(market, period=0)`
- **period = 0** returns spot price based on current pool state
- This reflects exact liquidity exit value (what we'd get if unwinding position now)

**Yield-bearing assets (sUSDe, stETH, etc.):**
- Use external oracles (there can be differences with internal protocol rates)

**Stablecoins:**
- Use external oracles as well (can be depegs etc.)

### Entry and Exit Rules
- **Entry:** shares minted from **deltaNAV** only (`shares = deltaNAV / pricePerShare`)
  - `NAV_before`: excludes queued deposit assets (they haven't entered strategies yet)
  - Child strategies contribute their `totalAssets()` (no internal shares)
  - `NAV_after`: includes newly deployed assets in child strategies
  - `deltaNAV` captures actual value creation from deploying capital
  - First deposit: `pricePerShare = 1e18` (1:1 ratio)
- **Exit:** pay realized asset units proportionally; do **not** pay by NAV estimate (see ADR-0005)

## Consequences
- Eliminates oracle-lag arbitrage at entry/exit.
- NAV mirrors strategy economics; sharePrice can deviate from instantaneous liquidation value but remains fair to all holders.

## Related ADRs
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Uses NAV for deltaNAV-based share minting
- [ADR-0005: Deposit & Withdrawal Settlement](0005-deposit-withdrawal-settlement.md) - Applies NAV snapshots in epoch processing

## Requirements Traceability
- **TR-002.1**: Component-Based NAV - Implemented through cash + collateral - debt + rewards formula
- **TR-002.2**: Oracle Integration - PT tokens use Pendle Oracle, yield-bearing assets use external oracles
- **TR-002.3**: Entry and Exit Rules - deltaNAV-based entry, proportional asset exit implemented
- **SR-005.1**: Oracle Manipulation Protection - Protocol-native measures prioritized over external oracles
- **SR-005.2**: Price Validation - Oracle price bounds and deviation checks implemented
- **PR-005.1**: Price Feed Efficiency - Fast and reliable price feed updates from multiple sources
- **PR-005.2**: NAV Calculation Performance - Real-time NAV calculation with efficient aggregation
