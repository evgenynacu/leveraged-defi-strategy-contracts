# ADR-0006: Use Upgradeable Smart Contract Architecture

## Status
Accepted

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
