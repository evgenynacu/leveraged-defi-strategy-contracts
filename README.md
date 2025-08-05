# Leveraged DeFi Strategy Contracts

Smart contracts for Yearn V3 Leveraged DeFi Strategy.

## Overview

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
