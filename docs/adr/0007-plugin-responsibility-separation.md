# ADR-0007: Plugin Responsibility Separation and Value Calculation

## Status
Accepted

## Context
In the plugin-based architecture (ADR-0006), we need to define clear responsibilities for:
- Asset quantity tracking (positions in lending protocols)
- Price discovery and asset valuation 
- Total portfolio value calculation for invariant checking

Key challenges:
- Multiple lending plugins should not duplicate pricing logic
- Plugins need to report positions without knowing asset prices
- Central strategy contract needs accurate total value for invariant protection
- Oracle integration should be unified across all protocols

## Decision
Implement **separated responsibility architecture** where plugins handle quantities and main contract handles valuation.

Responsibility distribution:
- **Plugins**: Report asset quantities only (supplied/borrowed amounts)
- **Main Strategy Contract**: Asset pricing, total value calculation, invariant checking
- **Price Oracle**: Centralized price feeds with manipulation protection
