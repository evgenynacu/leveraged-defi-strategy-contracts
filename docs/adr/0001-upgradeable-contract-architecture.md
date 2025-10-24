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

**Related Requirements:**
- [TR-001: Contract Architecture](../requirements/technical-requirements.md#tr-001-contract-architecture)
- [SR-006: Upgrade Security](../requirements/security-requirements.md#sr-006-upgrade-security)

## Decision
Use **OpenZeppelin upgradeable contracts** with a transparent proxy pattern.

### Architecture
- **Proxy Contract**: Immutable, holds state, delegates calls
- **Implementation Contract**: Upgradeable logic
- **Storage Layout Management**: Strict storage slot preservation
- **Initialization Pattern**: Use initializer functions instead of constructors

### What is Upgradeable
- ✅ Parent vault logic
- ✅ Child vault logic (each child is upgradeable independently)
- ❌ Proxy contracts (immutable)
- ❌ Storage layout (append-only, cannot reorder or remove variables)

### Implementation Requirements

**Initializer Pattern:**
- Implementation contracts MUST use initializer functions instead of constructors
- Use `@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol`
- Initializer functions MUST use `onlyInitializing` modifier
- Follow naming convention: `__ContractName_init()` for internal initializers

**Storage Variables:**
- MUST NOT use `immutable` keyword (incompatible with proxy pattern)
- Use regular storage variables instead
- All state variables stored in proxy contract storage

**Example Pattern:**
```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract LeveragedStrategy is Initializable, SwapHelper {
    // ❌ DON'T: immutable variables
    // address public immutable parent;

    // ✅ DO: storage variables
    address public parent;

    // ❌ DON'T: constructor
    // constructor(address _parent) { ... }

    // ✅ DO: initializer function
    function __LeveragedStrategy_init(address _parent)
        internal onlyInitializing
    {
        parent = _parent;
    }
}
```

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

## Requirements Traceability
- **TR-001.1**: Upgradeable Components - Implemented through OpenZeppelin transparent proxy pattern
- **TR-001.2**: Governance Structure - Flexible governance evolution supported
- **SR-006.1**: Upgrade Constraints - Storage layout preservation and proxy immutability enforced
- **SR-006.2**: Upgrade Validation - Governance and timelock mechanisms provide validation framework
