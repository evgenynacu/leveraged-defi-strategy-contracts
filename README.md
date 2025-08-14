# Leveraged DeFi Strategy Contracts

Smart contracts for Leveraged DeFi Strategy.

## Pendle PT Leveraged Strategy (Overview)

Objective: earn fixed yield by holding discounted Pendle PTs with leverage; rotate into newer PTs before maturity; refinance debt across money markets when advantageous.

### Strategy Requirements
- Focus on leveraged positions in Pendle PT tokens with conservative LTV management.
- Manual control over PT selection, maturity rotation, and lending market choice.
- Ability to refinance between supported lending markets (Aave, Morpho, Euler) when beneficial.
- Continuous LTV monitoring with automatic deleveraging if thresholds are breached.
- Use of reliable pricing sources for PT valuation (implied yield, TWAP, oracles).
- Configurable parameters for slippage tolerance, roll window, and target LTV ranges.

### Vault & Protocol Requirements
- Support for asynchronous deposits and withdrawals with share minting based on actual post-execution NAV.
- Ability to set different entry and exit prices (accounting for fees and execution slippage in PPS).
- Flexible NAV calculation using reliable oracles (TWAP, Chainlink, spot prices) with source aggregation.
- Built-in safeguards: slippage limits, deadlines, min-shares/min-assets conditions.
- Support for integration with external protocols and multi-step asset movement.

## In-depth description

### Instruments
- PT (Principal Token): accrues to par at maturity; trades at discount.
- Pendle router for swapping PT for other tokens and vice versa.
- Lending protocols: Aave v3, Morpho, Euler.

### Leverage Management
- Targets: targetLTV < rebalanceLTV < maxLTV.
- Upside drift: if LTV falls below target (PT rallies), borrow and buy more PT.
- Downside protection: if LTV ≥ rebalance band, sell PT and repay debt until back in range.
- Hard cap: never exceed maxLTV; trigger immediate delever if breached.

### Rotation Before Maturity
- Window: begin N days before maturity.
- Method: buy PT with later maturity and sell PT with earlier maturity.
- Can buy PT and use Morpho / Euler to borrow. Then move debt to Aave when PT is enabled there.

### Refinancing Logic
- Decision rule: switch venue when (APR_old − APR_new) × horizon − refi_costs > threshold.
- Execution: repay on old venue, free collateral, re‑post on new venue, re‑borrow, re‑buy PT.

### Pricing & NAV
- PT mark: derived from implied PT yield (discount to par over remaining term), validated against Pendle AMM TWAP or spot.
- Other assets: priced using reliable on-chain oracles (e.g., Chainlink, venue-specific TWAPs).
- NAV: PT market value − outstanding debt + idle cash.
- Haircuts: apply valuation discount to PT marks for conservative accounting.

### Keeper/Executor Duties (off‑chain)
- Compute optimal swap routes and calldata; enforce slippage.
- Monitor LTV, prices, borrow APRs; trigger lever/delever/refinance.

## Operations overview

Smart contracts allow:
- Open/Close leveraged positions
- Refinance positions (between different lending protocols or between different markets/tokens)
- Change leverage
- Calculate total owned assets using oracles and other on-chain data (e.g. PT implied yield)
- Control risk

## Opening a position

- Borrows assets (using flash loans)
- Buys other tokens (ideally yield-bearing tokens)
- Puts bought tokens into lending protocols as collateral
- Borrows assets
- Returns flash loan

## Closing a position

- Borrows assets
- Repays debt on lending protocol
- Withdraws collateral from lending protocol
- Sells collateral
- Returns flash loan

## Refinancing/Changing leverage (not implemented yet)

Implemented the same way as opening/closing a position.

## Architecture

Architure is described in [Architecture Decision Records](docs/adr).
