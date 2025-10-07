# ADR-0007: Reentrancy Protection Strategy

## Status
Accepted

## Date
2025-01-10

## Context

The vault system performs multiple external calls during operations:
- Token swaps via DEX routers (KyberSwap, Odos, Pendle)
- Lending protocol interactions (Aave, Morpho, Euler)
- Flash loan providers (Morpho, Balancer)

These external calls create reentrancy risks, especially during swap operations where:
1. Token approvals are active
2. External routers receive control flow
3. Balances are being updated

We need a consistent, efficient, and secure reentrancy protection strategy across the entire system.

**Related Requirements:**
- [SR-002.3: Command Validation](../requirements/security-requirements.md#sr-0023-command-validation) - Reentrancy protection for command execution
- [SR-004.2: Command Execution Safety](../requirements/security-requirements.md#sr-0042-command-execution-safety) - Atomic execution with safety guarantees

## Decision

### Entry-Point Protection Strategy

We implement reentrancy protection **only at external entry points** (public/external functions), NOT at internal helper functions.

**Architecture:**

```
┌─────────────────────────────────────────────────────┐
│ Parent Vault (Entry Points)                         │
│ ✓ processDeposits() - nonReentrant                  │
│ ✓ processWithdrawals() - nonReentrant               │
│ ✓ rebalance() - nonReentrant                        │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Child Strategies (No Guard)                         │
│ • deposit() - called by parent (protected)          │
│ • withdraw() - called by parent (protected)         │
│ • rebalance() - called by parent (protected)        │
│   └─> _swap() - internal helper (no guard)          │
└─────────────────────────────────────────────────────┘
```

### Implementation Rules

1. **Parent Vault:**
   - All external entry points MUST have `nonReentrant` modifier
   - Entry points: `processDeposits`, `processWithdrawals`, `rebalance`, `executeCommand`
   - Uses OpenZeppelin's ReentrancyGuard

2. **Child Strategies:**
   - External functions that can ONLY be called by parent - NO guard needed
   - Access control (`onlyParent`) provides sufficient protection
   - Parent's guard protects the entire call chain

3. **Helper Contracts (SwapHelper, etc.):**
   - Internal functions (`_swap`, `_executeSwap`) - NO guard
   - Rely on caller's protection
   - Document requirement clearly

### Code Example

```solidity
// ParentVault.sol
contract ParentVault is ReentrancyGuard {
    /// @notice Process pending deposits for current epoch
    function processDeposits(
        DepositParams calldata params
    ) external onlyKeeper nonReentrant {
        // All operations in this call chain are protected
        for (uint i = 0; i < childStrategies.length; i++) {
            childStrategies[i].deposit(...); // Protected by parent's guard
        }
    }
}

// ChildStrategy.sol
contract ChildStrategy {
    /// @notice Deposit assets into strategy
    /// @dev Can only be called by parent vault (already protected)
    function deposit(...) external onlyParent {
        // No nonReentrant needed - parent has it
        _swap(...); // Protected via parent
    }

    function _swap(...) internal {
        // No guard - relies on entry point protection
        // External call to DEX router happens here
    }
}

// SwapHelper.sol (base contract)
abstract contract SwapHelper {
    /// @dev IMPORTANT: Caller MUST have reentrancy protection
    function _swap(...) internal returns (uint256) {
        // No guard - documented requirement for caller
    }
}
```

### Rationale

**Why Entry-Point Only:**

1. **Gas Efficiency**
   - Single guard check per transaction instead of multiple
   - Critical for multi-step operations (deposit → swap → supply → borrow)
   - Example: 3 swaps = 1 guard check vs 3 guard checks

2. **Simplified Architecture**
   - Clear separation of concerns
   - Entry points = security boundary
   - Internal helpers = pure logic

3. **No Conflicts**
   - Avoids "ReentrancyGuard: reentrant call" when guard is nested
   - OpenZeppelin's guard doesn't support nested calls

4. **Controlled Environment**
   - We control all contracts in the call chain
   - No third-party contracts inherit our helpers
   - Access control (`onlyParent`) provides additional safety

**Why NOT Per-Function:**

1. **Gas Overhead**
   ```solidity
   // Bad: Multiple checks
   processDeposits() → nonReentrant (+2.1k gas)
     └─> child.deposit() → nonReentrant (+2.1k gas)
         └─> _swap() → nonReentrant (+2.1k gas)
   Total: +6.3k gas

   // Good: Single check
   processDeposits() → nonReentrant (+2.1k gas)
     └─> child.deposit() → no guard
         └─> _swap() → no guard
   Total: +2.1k gas
   ```

2. **Complexity**
   - Harder to reason about protection boundaries
   - Risk of conflicting guards
   - Unnecessary for internal calls

### Safety Analysis

**Attack Surface:**

| Entry Point | Protected | Attack Vector | Mitigation |
|-------------|-----------|---------------|------------|
| processDeposits() | ✓ nonReentrant | Malicious DEX router | Guard blocks reentrancy |
| processWithdrawals() | ✓ nonReentrant | Compromised lending protocol | Guard blocks reentrancy |
| rebalance() | ✓ nonReentrant | Flash loan callback exploit | Guard blocks reentrancy |
| executeCommand() | ✓ nonReentrant | Command sequence manipulation | Guard blocks reentrancy |
| child.deposit() | ✓ via parent | Direct call attempt | onlyParent blocks access |
| _swap() | ✓ via parent | N/A - internal only | Not externally callable |

**Defense in Depth:**

1. **Primary:** ReentrancyGuard at entry points
2. **Secondary:** Access control (`onlyParent`, `onlyKeeper`)
3. **Tertiary:** Approval cleanup after swaps
4. **Monitoring:** Event logging for all critical operations

## Consequences

### Positive

- **Gas Efficiency:** ~2.1k gas saved per nested call
- **Simplicity:** Clear security boundary at entry points
- **Maintainability:** Easy to verify all entry points are protected
- **No Conflicts:** No nested guard issues

### Negative

- **Requires Discipline:** Developers must remember to add guard to new entry points
- **Documentation Critical:** Must clearly document protection requirements
- **Trust in Architecture:** Helper functions rely on caller protection

### Risks & Mitigations

**Risk 1: Forgotten Guard on New Entry Point**
- **Mitigation:** Code review checklist
- **Mitigation:** CI/CD tests verify all external functions have guard
- **Mitigation:** Documentation and ADR reference

**Risk 2: Third-Party Inherits Helper Without Guard**
- **Mitigation:** Helpers are internal/abstract - not meant for external use
- **Mitigation:** Clear documentation in contract comments
- **Mitigation:** This is acceptable since we control all implementations

**Risk 3: Direct Call to Child Strategy**
- **Mitigation:** `onlyParent` modifier prevents direct calls
- **Mitigation:** Even if bypassed, operations would fail due to missing liquidity

## Verification

### Testing Requirements

1. **Positive Tests:**
   - Normal operations succeed with single guard
   - Multiple nested operations work correctly
   - Gas usage is optimized

2. **Negative Tests:**
   - Reentrancy attempts via malicious router are blocked
   - Direct calls to child strategies are rejected
   - Multiple entry point calls in same tx are blocked

3. **Integration Tests:**
   - Full flow: processDeposits → child.deposit → _swap
   - Verify guard is checked only once
   - Confirm reentrancy attack fails

### Code Review Checklist

For every new external/public function:
- [ ] Is this an entry point? (called externally)
- [ ] Does it have `nonReentrant` modifier?
- [ ] Is it documented in this ADR?
- [ ] Are tests added for reentrancy protection?

## Implementation Notes

### OpenZeppelin ReentrancyGuard

We use OpenZeppelin's standard implementation:
- Version: ^5.0.0
- Single storage slot: `_status`
- Status: `NOT_ENTERED` (1) or `ENTERED` (2)
- Gas: ~2.1k per call (SLOAD + SSTORE + check)

### Protected Entry Points

**Parent Vault:**
```solidity
function processDeposits(...) external onlyKeeper nonReentrant { }
function processWithdrawals(...) external onlyKeeper nonReentrant { }
function rebalance(...) external onlyKeeper nonReentrant { }
function executeCommand(...) external onlyKeeper nonReentrant { }
```

**Child Strategies:**
```solidity
// No nonReentrant - relies on parent protection + onlyParent access control
function deposit(...) external onlyParent { }
function withdraw(...) external onlyParent { }
function rebalance(...) external onlyParent { }
```

### Future Considerations

If we ever:
1. Allow direct user calls to child strategies → Add `nonReentrant`
2. Open-source helpers for third-party use → Add `nonReentrant` to helpers
3. Integrate with untrusted protocols → Consider per-call guards

## Related ADRs

- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Commands execute under parent's guard
- [ADR-0003: Vault Architecture](0003-vault-architecture.md) - Parent-child relationship and call flow
- [ADR-0006: Child Strategy Interface](0006-child-vault-interface.md) - Single-owner constraint (onlyParent)

## Requirements Traceability

- **SR-002.3:** Command validation with reentrancy protection ✓ (via entry point guards)
- **SR-004.2:** Atomic execution safety ✓ (single guard protects entire operation)
- **SR-001.1:** Role-based permissions ✓ (onlyParent + onlyKeeper + guard)

## References

- OpenZeppelin ReentrancyGuard: https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuard
- Consensys Smart Contract Best Practices: https://consensys.github.io/smart-contract-best-practices/attacks/reentrancy/
