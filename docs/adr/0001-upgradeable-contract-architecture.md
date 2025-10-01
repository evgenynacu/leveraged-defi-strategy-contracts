# ADR-0001: Use Upgradeable Smart Contract Architecture

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

### Architecture
- **Proxy Contract**: Immutable, holds state, delegates calls
- **Implementation Contract**: Upgradeable logic
- **Storage Layout Management**: Strict storage slot preservation

### What is Upgradeable
- ✅ Parent vault logic
- ✅ Child vault logic (each child is upgradeable independently)
- ❌ Proxy contracts (immutable)
- ❌ Storage layout (append-only, cannot reorder or remove variables)

### Governance
Upgrade authority and governance mechanisms (timelock, multisig, DAO voting) are intentionally **not specified** in this ADR. These will be implemented using OpenZeppelin Governor and TimelockController, allowing flexibility to evolve governance over time without changing the core proxy architecture.

Initial deployment may use a simple multisig, with migration to full on-chain governance as the protocol matures.

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
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Command system enables flexibility without frequent upgrades
