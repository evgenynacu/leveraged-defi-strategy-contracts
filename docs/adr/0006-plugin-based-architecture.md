# ADR-0006: Plugin-Based Architecture with Delegatecall and Invariant Protection

## Status
Accepted

## Context
Need flexible architecture for:
- Multiple lending protocols (Aave, Morpho, Euler) where positions are tied to msg.sender
- Multiple swap providers with different interfaces
- Complex rebalancing operations by operators without fund theft risk
- Easy integration of new protocols without contract upgrades

Key requirements:
- Aave and similar protocols require msg.sender to be the position owner
- Operators need ability to execute complex multi-step operations
- Protection against operator key compromise
- Asset value invariants must be maintained

## Decision
Implement **plugin-based architecture** using **delegatecall** with **strict invariant protection**.

Architecture:
- **Core Strategy Contract**: Holds funds, manages plugins, enforces invariants
- **Plugin Contracts**: Stateless logic for specific protocols (Aave, Morpho, Uniswap)
- **Operator System**: Backend executes whitelisted plugin combinations
- **Invariant Checker**: Validates total asset value before/after operations
