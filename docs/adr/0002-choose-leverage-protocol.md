# ADR-0002: Choose Aave V3 as Primary Lending Protocol

## Status
Accepted

## Context
For implementing the leveraged strategy, we need to choose a lending protocol for:
- Borrowing assets to create leverage
- Supplying collateral
- Managing health factor
- Liquidation protection

Requirements:
- High liquidity
- Stable interest rates
- Reliable oracles

## Decision
Use **Aave V3** and **Morpho** as the primary lending protocols. But the smart contract architecture should support other lending protocols out of the box.
Currently we plan to use mostly Pendle PT tokens as collateral. Until recently Aave didn't support PT tokens, and Morpho was almost the only one with high liquidity. Other protocols which support PT tokens:
- Euler (smaller liquidity which means worse rates, but will reconsider it later)

Architecture:
- `LendingManager` interface for abstraction
- `AaveV3Adapter` & `MorphoBlueAdapter` as primary implementations

## Consequences
### Positive
- Maximum liquidity and low rates
- Isolation mode for risk management
- Efficient gas usage with Aave V3
- Proven security track record
- Rich feature set (eMode, etc.)

### Negative
- Dependency on Aave governance decisions
- Complexity in multi-protocol architecture
- Potential smart contract risks
- Higher development complexity

### Neutral
- Need to monitor both protocols
- Requires fallback logic implementation

## Alternatives Considered
- **Euler**: Innovative features but less battle-tested

## References
- [Aave V3 Documentation](https://docs.aave.com/developers/)
- [Morpho Blue documentation](https://docs.morpho.org/getting-started/)