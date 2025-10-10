# ADR-0008: LeveragedStrategy Architecture (Inheritance-Based)

## Status
Accepted

## Date
2025-01-10

## Implementation Status
🟡 **Partially Implemented** – Core `LeveragedStrategy` base contract and `IChildStrategy` interface shipped (Jan 2025). Protocol-specific children (Aave/Morpho/Euler) remain outstanding per [IMPLEMENTATION_ROADMAP.md](../../IMPLEMENTATION_ROADMAP.md) Phase 2.

## Context

Child strategies need to interact with multiple lending protocols (Aave, Morpho, Euler) while maintaining consistent leverage mechanics, swap handling, and command execution patterns.

Initial consideration was a plugin-based delegatecall pattern (similar to AutomatedVault.sol from previous project), but this approach has limitations:

**Why Plugin Pattern Doesn't Fit:**
- Limited, well-defined operation set: lending (supply, withdraw, borrow, repay) + swaps
- SwapHelper already centralizes all DEX interactions
- Flash loans handled at parent vault level (not child level)
- Commands are simpler and more structured than general-purpose plugins
- No need for dynamic plugin loading/whitelisting

**Requirements:**
- Support multiple lending protocols with minimal code duplication
- Maintain consistent leverage mechanics across all protocols
- Integrate seamlessly with SwapHelper for token swaps
- Provide clean command execution interface
- Enable protocol-specific optimizations where needed

**Related ADRs:**
- [ADR-0006: Child Strategy Interface](0006-child-vault-interface.md) - IChildStrategy interface requirements
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Command structure and execution
- [ADR-0007: Reentrancy Protection Strategy](0007-reentrancy-protection-strategy.md) - Security considerations

## Decision

Implement **inheritance-based architecture** with abstract base class and protocol-specific implementations.

### Architecture Hierarchy

```
SwapHelper (abstract)
    ↓
LeveragedStrategy (abstract) extends SwapHelper
    ↓
├── AaveLeveragedStrategy
├── MorphoLeveragedStrategy
└── EulerLeveragedStrategy
```

### LeveragedStrategy Base Class (Implemented)

**Current Responsibilities:**
- **IChildStrategy Implementation**: `deposit()`, `withdraw()`, `rebalance()`, `totalAssets()`
- **Command Execution Framework**: `_executeCommands` walks typed command list encoded in `data`
- **Access Control**: `onlyParent` modifier restricts entry points
- **SwapHelper Integration**: Inherits oracle-checked swaps and router management
- **Multi-token Support**: `_trackedTokens()` derives base/collateral/debt set with override hook for rewards
- **Approval Management**: Uses `forceApprove` to stage withdrawn assets / flash-loan repayments for the parent
- **Proportional Exit Guardrails**: `_executeProportionalWithdraw` + `_validateIdleBalances` enforce snapshot-based proportionality and prevent idle balance leakage even with keeper-provided swaps

**Command Types (5 total):**
```
SUPPLY    - Supply collateral to lending protocol
WITHDRAW  - Withdraw collateral from lending protocol
BORROW    - Borrow asset from lending protocol
REPAY     - Repay debt to lending protocol
SWAP      - Swap tokens via inherited SwapHelper
```

**Command Structure:**
- Commands are passed via `bytes data` parameter in IChildStrategy methods
- Each command contains: `CommandType cmdType` + `bytes data` (encoded parameters)
- Commands executed atomically (all succeed or all revert)
- No Transfer command - assets remain in strategy, only approvals for parent

**Abstract Methods (Protocol-Specific):**

Child implementations must provide:
- `_supply(asset, amount)` - Supply collateral to protocol
- `_withdraw(asset, amount)` - Withdraw collateral from protocol
- `_borrow(asset, amount)` - Borrow from protocol
- `_repay(asset, amount)` - Repay debt to protocol
- `_getCollateralAsset()` / `_getCollateralAmount()` - Identify collateral token + balance
- `_getDebtAsset()` / `_getDebtAmount()` - Identify debt token + balance

### Protocol-Specific Implementations

**AaveLeveragedStrategy:**
- Implements abstract methods using Aave V3 Pool interface
- Uses variable interest rate mode (interestRateMode = 2)
- Handles multi-currency debt (USDC/USDT/DAI)

**MorphoLeveragedStrategy:**
- Implements abstract methods using Morpho Blue interface
- Manages market parameters for different markets
- Handles Morpho-specific return values (shares vs assets)

**EulerLeveragedStrategy:**
- Implements abstract methods using Euler V2 interface
- Handles Euler-specific vault architecture

### Command Execution Flow

**Leveraged Deposit Example:**
1. Parent takes flash loan (e.g., USDC)
2. Parent transfers tokens to child + calls deposit() with commands
3. Child executes command sequence:
   - SWAP: USDC → PT tokens
   - SUPPLY: PT as collateral
   - BORROW: USDC against PT
4. Child approves expected tokens (flash loan repayment) for parent
5. Parent collects and repays flash loan

**Deleverage Withdrawal Example:**
1. Parent takes flash loan (for debt repayment)
2. Parent transfers liquidity to child + calls withdraw() with commands
3. Child executes command sequence:
   - REPAY: Debt using provided liquidity
   - WITHDRAW: PT collateral
   - SWAP: PT → USDC (optional keeper-supplied commands validated against tracked token set)
4. Child approves withdrawn tokens + flash loan repayment for parent
5. Parent collects and repays flash loan

## Consequences

### Positive
- **Code Reuse**: Common leverage logic in base class, only protocol calls differ
- **Type Safety**: Full Solidity type checking (vs delegatecall plugins)
- **Simplicity**: Clear inheritance hierarchy, easy to understand
- **Gas Efficiency**: Direct calls (no delegatecall overhead)
- **Testing**: Each protocol implementation can be tested independently
- **Maintainability**: Changes to leverage logic update all protocols
- **No Plugin Whitelist**: No need to manage approved plugins
- **Clear Separation**: Base class for logic, implementations for protocol integration

### Negative
- **Limited Flexibility**: Cannot add new protocols without deploying new contracts
- **Code Duplication**: Some similarity between protocol implementations
- **Upgrade Complexity**: Must upgrade all protocol implementations separately

### Neutral
- **Command Parsing**: Still requires careful ABI encoding/decoding
- **Off-chain Complexity**: Keeper must prepare correct command sequences

## Comparison with Plugin Pattern

| Aspect | Inheritance Pattern (Chosen) | Plugin Pattern (Rejected) |
|--------|------------------------------|---------------------------|
| Operation Set | Fixed, well-defined (5 types) | Dynamic, extensible |
| Gas Cost | Lower (direct calls) | Higher (delegatecall) |
| Type Safety | Full Solidity checking | Lost in bytes encoding |
| Complexity | Simpler (inheritance) | Complex (plugin management) |
| Flexibility | Protocol-specific only | Protocol + operation types |
| Security | Clear boundaries | Delegatecall risks |
| Testing | Straightforward | More complex mocking |
| Best For | Limited, structured operations | Diverse, dynamic operations |

**Conclusion**: Inheritance pattern is better fit for our structured lending + swap operations. Plugin pattern would be overkill.

## Security Considerations

### Command Validation (Implemented)
- Commands executed only by parent vault (`onlyParent` modifier)
- No Transfer command type – assets stay on strategy; only allowances granted back to parent
- `_validateKeeperCommands` restricts keeper data during withdrawals to SWAP-only operations touching tracked tokens
- All swaps protected by oracle-based slippage checks (SwapHelper – ✅ implemented)
- Command execution is atomic (all or nothing)

### Reentrancy Protection (Planned - ADR-0007)
- No reentrancy guard in LeveragedStrategy (per ADR-0007)
- **Parent vault will have** nonReentrant on deposit/withdraw/rebalance entry points
- `onlyParent` access control provides protection at child level pending vault implementation

**⚠️ Note:** ParentVault not yet implemented. This describes the planned security architecture.

### Protocol-Specific Risks (Future Implementation)
- Each implementation must handle protocol-specific failure modes
- Collateral/debt calculations must be accurate for each protocol
- Interest accrual handling varies by protocol

## Related ADRs
- [ADR-0006: Child Strategy Interface](0006-child-vault-interface.md) - IChildStrategy implementation requirements
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Command structure and validation
- [ADR-0007: Reentrancy Protection Strategy](0007-reentrancy-protection-strategy.md) - Security pattern for entry points
- [ADR-0003: Vault Architecture](0003-vault-architecture.md) - Parent-child relationship and rebalancing

## Requirements Traceability
- **FR-002.1**: Multi-Protocol Support - Inheritance enables Aave, Morpho, Euler implementations
- **FR-003.1**: Command System - CommandType enum and Command struct with typed operations
- **TR-003.1**: Child Interface - LeveragedStrategy implements IChildStrategy
- **TR-004.1**: Command Structure - CommandType enum with 5 operation types
- **SR-001.1**: Access Control - onlyParent modifier restricts access
- **SR-004.1**: Command Safety - No Transfer command, assets remain in strategy

## References
- AutomatedVault.sol (previous project) - Plugin pattern reference for comparison
- [Aave V3 Documentation](https://docs.aave.com/developers/)
- [Morpho Blue Documentation](https://docs.morpho.org/)
- [Euler V2 Documentation](https://docs.euler.finance/)
