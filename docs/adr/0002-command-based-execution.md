# ADR-0002: Command-Based Execution System for Leveraged PT Strategies

## Status
Accepted

## Date
2024-09-26

## Context
The Leveraged PT strategy requires complex multistep operations that combine:
- Flash loans for capital efficiency
- Lending protocol operations (deposit, withdraw, borrow, repay)
- Token swaps via DEX aggregators and Pendle Router

Requirements:
- Each atomic operation must be safe (no fund loss possible)
- Operations must be composable for complex strategies
- Off-chain should determine optimal execution paths
- System should be extensible for new protocols

Traditional approaches lack the flexibility needed for dynamic strategy execution and require contract upgrades for new protocols.

## Decision
Implement a **Command-Based Execution System** using a simple operation enum and command structure.

### Core Data Structures

```solidity
contract CommandBasedVault {
    enum Op { FlashLoan, LendingDeposit, LendingWithdraw, LendingBorrow, LendingRepay, Swap, Transfer }
    struct Cmd {
        Op op;
        bytes data; // ABI-encoded arguments for this operation 
    }
}
```

### Integration with BaseVault

The vault will receive command arrays through calldata in `_deploy` and `_withdrawUnderlying` functions and execute them sequentially.
Also, there should be a function to execute arbitrary commands in the vault (for example, to refinance debt using a better borrow rate).
Vault keeper should be able to call this function to execute arbitrary commands (though safety of all funds should be ensured because each command is safe).

### Example Operations

**Opening Leveraged Position:**
1. FlashLoan USDC from Morpho
2. Swap USDC to PT tokens via Pendle Router
3. Deposit PT as collateral to lending protocol
4. Borrow USDC against PT collateral
5. Repay flash loan

**Closing Position:**
1. FlashLoan USDC from Morpho
2. Repay debt on lending protocol
3. Withdraw PT collateral
4. Swap PT back to USDC
5. Repay flash loan

## Consequences

### Positive
- **Simplicity**: Clean enum + bytes structure is easy to understand
- **Safety**: Each operation has clear safety guarantees
- **Composability**: Commands can be combined for complex strategies
- **Extensibility**: New operations can be added without breaking existing code
- **Gas Efficiency**: Minimal overhead for command parsing
- **Atomic Execution**: All commands succeed or fail together
- **Protocol Agnostic**: Easy to support multiple lending/swap protocols

### Negative
- **Data Encoding Complexity**: Off-chain must properly encode command data
- **Limited Type Safety**: bytes encoding loses compile-time type checking
- **Debug Difficulty**: Harder to debug failed command sequences
- **Gas Overhead**: Command iteration adds small gas cost

### Neutral
- **Off-chain Dependency**: Requires sophisticated command planning off-chain
- **Validation Requirements**: Must validate each command thoroughly
- **Flash Loan Nesting**: Special handling needed for nested commands in flash loans

## Security Considerations
- Validate command sequences for known attack patterns
- Add reentrancy protection for command execution
- Ensure flash loan repayment is always possible
- Validate slippage limits and deadlines for all swaps

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
- [ADR-0006: Child Vault Interface](0006-child-vault-interface.md) - Data parameter in deposit/withdraw may contain command sequences
- [ADR-0001: Upgradeable Contract Architecture](0001-upgradeable-contract-architecture.md) - Command system reduces need for upgrades

## References
- [Morpho Flash Loans](https://docs.morpho.org/morpho/developers/flash-loans)
- [Aave V3 Documentation](https://docs.aave.com/developers/)
- [Pendle Integration Guide](https://docs.pendle.finance/)
- [Odos Router Documentation](https://docs.odos.xyz/)
