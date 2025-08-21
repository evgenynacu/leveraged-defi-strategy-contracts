# ADR-0005: Use Morpho for Flash Loans

## Status
Accepted

## Context
The leveraged DeFi strategy requires flash loans for several operations:
- Opening leveraged positions (borrow → buy collateral → supply → borrow → repay flash loan)
- Closing positions (borrow → repay debt → withdraw collateral → sell → repay flash loan)
- Refinancing positions (future feature)
- Leverage adjustments (future feature)

Flash loan requirements:
- Zero fees (to maximize strategy profitability)
- High liquidity for major assets (USDC, USDT, other stablecoins, DAI etc)
- Simple integration without complex callbacks
- Reliable availability
- Gas efficiency

Current flash loan providers:
- **Aave V3**: 0.05% fee, high liquidity, battle-tested
- **Balancer**: 0% fee but limited asset selection and liquidity
- **Morpho**: 0% fee, good liquidity for major assets, newer but growing
- **dYdX**: 0% fee but complex integration and limited assets

## Decision
Use **Morpho Flash Loans** as the primary flash loan provider for the strategy.
As we also use Morpho for other purposes, we can leverage the same liquidity pool for flash loans.

Implementation approach:
- `FlashLoanManager` interface for abstraction
- `MorphoFlashLoanAdapter` as primary implementation
- Fallback to Aave V3 if Morpho liquidity insufficient (future enhancement)

```solidity
interface IFlashLoanManager {
    function executeFlashLoan(
        address asset,
        uint256 amount,
        bytes calldata params
    ) external;
}

contract MorphoFlashLoanAdapter is IFlashLoanManager {
    function executeFlashLoan(
        address asset,
        uint256 amount,
        bytes calldata params
    ) external override {
        // Morpho flash loan implementation
        morpho.flashLoan(asset, amount, params);
    }
}
```

## Consequences
### Positive
- **Zero fees**: Significant cost savings compared to Aave's 0.05% fee (0.05% fee is multiplied n times when leveraged)
- **Simple integration**: Straightforward callback pattern
- **Good liquidity**: Sufficient for major assets we plan to use
- **Gas efficient**: Optimized flash loan implementation
- **No exotic tokens needed**: Strategy will use standard assets available on Morpho

### Negative
- **Newer protocol**: Less battle-tested than Aave
- **Liquidity risk**: Potential liquidity constraints during market stress
- **Protocol risk**: Smart contract risks associated with newer protocol
  - This risk is not too important because we just borrow and repay in the same transaction
- **Limited asset selection**: Fewer assets compared to Aave

### Neutral
- **Monitoring required**: Need to track Morpho liquidity and protocol health
- **Fallback planning**: Should consider backup options for extreme scenarios

## Alternatives Considered
- **Aave V3 Flash Loans**:
    - Pros: Battle-tested, highest liquidity, most reliable
    - Cons: 0.05% fee significantly impacts strategy profitability
    - Rejected due to fee impact on leveraged strategy returns

- **Balancer Flash Loans**:
    - Pros: Zero fees, reliable protocol
    - Cons: Limited asset selection, lower liquidity for some assets
    - Rejected due to liquidity constraints

- **dYdX Flash Loans**:
    - Pros: Zero fees, good for specific assets
    - Cons: Complex integration, limited asset support, different callback pattern
    - Rejected due to integration complexity

## Implementation Notes
- Start with a Morpho-only implementation for MVP
- Monitor liquidity levels and protocol performance
- Consider adding Aave fallback in future versions if needed
- Ensure proper error handling for insufficient liquidity scenarios

## Success Metrics
- Flash loan availability > 99% for target assets
- Gas costs within acceptable range
- Zero fee impact on strategy performance
- No security incidents related to flash loan integration

## References
- [Morpho Documentation](https://docs.morpho.org/)
- [Morpho Flash Loans Guide](https://docs.morpho.org/morpho/developers/flash-loans)
- [Aave Flash Loans Documentation](https://docs.aave.com/developers/guides/flash-loans)
- Internal liquidity analysis for target assets
- Fee impact analysis on strategy profitability
