# ADR-0006: Use Upgradeable Smart Contract Architecture

## Status
Accepted

## Date
2024-09-10

## Context
The leveraged DeFi strategy needs flexibility for:
- Bug fixes without user migration
- New flash loan providers with different callback interfaces
- Protocol changes in external dependencies

Traditional immutable contracts require complete redeployment and user migration for any changes.

## Decision
Use **OpenZeppelin upgradeable contracts** with a transparent proxy pattern.

Architecture:
- **Proxy Contract**: Immutable, holds state, delegates calls
- **Implementation Contract**: Upgradeable logic
- **Storage Layout Management**: Strict storage slot preservation

## Consequences
### Positive
- Bug fixes without user migration
- Ability to adapt to external protocol changes
- Support for new flash loan providers

### Negative
- Increased complexity in storage management
- Potential centralization risk via upgrade mechanism
- Need for rigorous upgrade governance

## Related ADRs
- [ADR-0007: Command-Based Execution](0007-command-based%20execution.md) - Command system enables flexibility without frequent upgrades
