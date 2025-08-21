# ADR-0004: Use Chainlink as Primary Oracle with Redundancy

## Status
Accepted

## Context
Leveraged strategies are critically dependent on accurate price feeds for:
- Rebalancing decisions
- Slippage protection
- Calculating the total asset value of the strategy
- Verifying that actions are not causing money loss

Oracle failure risks:
- Price manipulation attacks
- Stale price data
- Oracle downtime
- Flash loan attacks

## Decision
Implement a multi-layered oracle strategy:

1. **Primary**: Chainlink Price Feeds
2. **Secondary**: TWAP from Uniswap V3
3. **Validation**: Cross-reference between sources
4. **Circuit breaker**: Pause on significant deviation

```solidity
contract OracleManager {
    function getPrice(address asset) external view returns (uint256) {
        uint256 chainlinkPrice = getChainlinkPrice(asset);
        uint256 twapPrice = getTWAPPrice(asset);
        
        require(
            isWithinDeviation(chainlinkPrice, twapPrice, MAX_DEVIATION),
            "Oracle deviation too high"
        );
        
        return chainlinkPrice;
    }
}
```

## Consequences
### Positive
- High reliability and security
- Protection from oracle manipulation
- Battle-tested infrastructure
- Industry standard approach

### Negative
- Additional gas costs for validation
- Complexity in oracle management
- Potential delays during oracle issues

### Neutral
- Need for monitoring oracle health
- Fallback procedures for oracle failures

## Alternatives Considered
- **Chainlink only**: Cheaper but single point of failure
- **TWAP only**: Manipulation resistant but can lag
- **Band Protocol**: Alternative oracle but less adoption
- **Custom oracle aggregation**: Too complex and risky

## References
- [Chainlink Documentation](https://docs.chain.link/)
- [Uniswap V3 TWAP Guide](https://docs.uniswap.org/concepts/protocol/oracle)
- Oracle manipulation attack studies

