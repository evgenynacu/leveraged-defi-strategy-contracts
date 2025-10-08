# ADR-0002: Command-Based Execution System for Leveraged Strategies

## Status
Accepted (Implementation Pending)

## Date
2024-09-26 (Last Updated: 2025-01-10)

## Implementation Status
🔴 **Not Implemented** - This ADR documents the architectural decision. Implementation tracked in [IMPLEMENTATION_ROADMAP.md](../../IMPLEMENTATION_ROADMAP.md) Phase 2.

## Context
The Leveraged strategy system requires complex multistep operations that combine:
- Flash loans for capital efficiency (at parent level)
- Lending protocol operations (supply, withdraw, borrow, repay)
- Token swaps via DEX aggregators (KyberSwap, Odos, Pendle)

Requirements:
- Each atomic operation must be safe (no fund loss possible)
- Operations must be composable for complex strategies
- Off-chain keeper determines optimal execution paths
- System should support multiple lending protocols (Aave, Morpho, Euler)

**Architecture Context (Updated 2025-01-10):**
After evaluating plugin-based delegatecall pattern vs inheritance-based pattern, we chose **inheritance** for the following reasons:
- Limited, well-defined operation set (5 command types)
- SwapHelper already centralizes all DEX interactions
- Flash loans handled at parent vault level
- Better type safety and gas efficiency than delegatecall plugins
- See [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) for detailed analysis

**Related Requirements:**
- [FR-003: Command-Based Execution](../requirements/functional-requirements.md#fr-003-command-based-execution)
- [TR-004: Command System Implementation](../requirements/technical-requirements.md#tr-004-command-system-implementation)
- [SR-004: Command System Security](../requirements/security-requirements.md#sr-004-command-system-security)

## Decision
Implement **Command-Based Execution System** in child strategies using inheritance-based architecture.

### Core Data Structures

```solidity
// Defined in LeveragedStrategy base contract
enum CommandType {
    SUPPLY,      // Supply collateral to lending protocol
    WITHDRAW,    // Withdraw collateral from lending protocol
    BORROW,      // Borrow asset from lending protocol
    REPAY,       // Repay debt to lending protocol
    SWAP         // Swap tokens via SwapHelper
}

struct Command {
    CommandType cmdType;
    bytes data;  // ABI-encoded parameters specific to command type
}
```

**IMPORTANT:** `Transfer` operation is **NOT** included in CommandType. All assets must remain within strategy contracts. Transfers are only executed by parent vault logic via ERC20 approvals, never by keeper-provided commands.

### Command Execution Flow (Planned)

Commands will be passed to child strategies via the `data` parameter in IChildStrategy methods.

**Planned Flow:**
1. Decode Command[] from `data` parameter
2. Execute command sequence atomically via `_executeCommands()`
3. Approve expected tokens for parent collection

### Integration with Child Strategies (To Be Implemented)

Child strategies will receive commands through three entry points:
1. **deposit()** - Commands for opening/increasing leveraged positions
2. **withdraw()** - Commands for closing/reducing leveraged positions
3. **rebalance()** - Commands for internal optimizations (e.g., refinancing debt)

Keeper will prepare command sequences off-chain and pass them via the `data` parameter.

### Example Operations (Planned Flow)

**Opening Leveraged Position:**
Parent will take flash loan, then pass liquidity to child with commands:
1. SWAP: USDC → PT tokens via Pendle Router
2. SUPPLY: PT as collateral to lending protocol
3. BORROW: USDC against PT collateral
4. return flash loan using borrowed funds

Child will approve expected tokens (flash loan repayment) for parent collection.
Parent will collect and repay flash loan.

**Closing Position:**
Parent will take flash loan, then pass liquidity to child with commands:
1. REPAY: Debt on lending protocol using provided liquidity
2. WITHDRAW: PT collateral from lending protocol
3. SWAP: PT → USDC

Child will approve withdrawn USDC + flash loan repayment for parent.
Parent will collect and repay flash loan.

**Note:** Flash loans will be managed at **parent vault level** (not yet implemented), not in child strategy commands. Commands only handle lending protocol operations and swaps.

## Consequences

### Positive
- **Simplicity**: Clean enum + bytes structure (5 command types only)
- **Safety**: Each operation has clear safety guarantees
- **Composability**: Commands can be combined for complex strategies
- **Type Safety**: Better than plugin pattern (inheritance vs delegatecall)
- **Gas Efficiency**: Direct calls, no delegatecall overhead
- **Atomic Execution**: All commands succeed or fail together
- **Protocol Agnostic**: Base class works with any lending protocol
- **Extensibility**: New protocol implementations via inheritance

### Negative
- **Data Encoding Complexity**: Off-chain must properly encode command data
- **Limited Type Safety**: bytes encoding within Command struct loses some compile-time checking
- **Debug Difficulty**: Harder to debug failed command sequences
- **Fixed Command Set**: Cannot add new command types without contract upgrade

### Neutral
- **Off-chain Dependency**: Requires sophisticated command planning off-chain (keeper responsibility)
- **Validation Requirements**: Must validate each command thoroughly
- **Flash Loan Separation**: Flash loans at parent level separate from child commands (cleaner architecture)

## Security Considerations

### Command Restrictions
- **NO Transfer operations:** Commands cannot move funds out of vault
- All assets must remain in vault after command execution
- Only vault logic (not keeper commands) can transfer assets to parent or users

### Validation Requirements
- Validate command sequences for known attack patterns
- Add reentrancy protection for command execution
- Ensure flash loan repayment is always possible
- Validate slippage limits and deadlines for all swaps
- Check that no commands attempt unauthorized token transfers

### Invariants
After executing any command sequence:
- All borrowed flash loan funds must be repaid
- All intermediate tokens must be converted to strategy assets
- No tokens should be sent to external addresses
- Vault's position must be internally consistent (collateral/debt ratios valid)

## Success Metrics
- Command execution success rate > 99.5%
- Gas cost overhead < 10% compared to direct function calls
- Zero fund loss incidents due to command execution
- Support for 2+ lending protocols and 3+ swap routers
- Sub-1000ms off-chain command planning

## Alternatives Considered

### Direct Function Calls
- **Pros**: Type-safe, predictable gas, simple debugging
- **Cons**: Inflexible, requires upgrades for new protocols
- **Rejected**: Cannot adapt to optimal execution paths

## Related ADRs
- [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) - Inheritance-based implementation of command system
- [ADR-0006: Child Vault Interface](0006-child-vault-interface.md) - Data parameter in deposit/withdraw contains command sequences
- [ADR-0007: Reentrancy Protection Strategy](0007-reentrancy-protection-strategy.md) - Security pattern for command execution
- [ADR-0001: Upgradeable Contract Architecture](0001-upgradeable-contract-architecture.md) - Upgrade mechanism for adding new command types

## Requirements Traceability
- **FR-003.1**: Command System - Implemented through CommandType enum (5 types) and Command struct
- **FR-003.2**: Safety and Validation - Each command has safety guarantees, no Transfer command type
- **TR-004.1**: Data Structures - CommandType enum and Command struct in LeveragedStrategy base class
- **TR-004.2**: Security Constraints - Transfer operation excluded, assets remain in strategy
- **TR-004.3**: Invariants - All invariants enforced after command sequence execution
- **SR-004.1**: Command Restrictions - NO Transfer command, assets remain in strategy, only approvals for parent
- **SR-004.2**: Command Execution Safety - Atomic execution via _executeCommands, onlyParent access control

## References
- [Morpho Flash Loans](https://docs.morpho.org/morpho/developers/flash-loans)
- [Aave V3 Documentation](https://docs.aave.com/developers/)
- [Pendle Integration Guide](https://docs.pendle.finance/)
- [Odos Router Documentation](https://docs.odos.xyz/)
