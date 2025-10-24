# Architecture Decision Records (ADR)

This directory contains Architecture Decision Records for the Leveraged DeFi Strategy Contracts project.

## What is an ADR?

An Architecture Decision Record (ADR) captures an important architectural decision made along with its context and consequences.

## ADR Structure

Each ADR should follow this structure:

```markdown
# ADR-XXXX: [Title]

## Status
[Proposed | Accepted | Accepted (Implementation Pending) | Deprecated | Superseded]

## Date
YYYY-MM-DD

## Implementation Status (if applicable)
🔴 Not Implemented | 🟡 In Progress | ✅ Implemented
- Link to implementation tracking (e.g., IMPLEMENTATION_ROADMAP.md)

## Context
What is the issue that we're seeing that is motivating this decision or change?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or more difficult to do because of this change?

### Positive
- List of benefits

### Negative
- List of drawbacks

### Neutral
- Neutral observations

## Alternatives Considered
What other approaches were considered and why were they rejected?

## Related ADRs
- Links to related ADRs

## Requirements Traceability
- Map to functional/technical/security requirements

## References
- External documentation, specifications, etc.
```

## ADR Guidelines

### 1. Keep ADRs Concept-Focused

**DO:**
- Explain the architectural decision and rationale
- Use high-level diagrams (ASCII art, mermaid)
- Show minimal code snippets for clarity (5-10 lines max)
- Focus on "what" and "why", not "how"

**DON'T:**
- Include full contract implementations
- Copy-paste large code blocks
- Document implementation details that belong in code comments
- Turn ADR into a code review

**Example:**
```markdown
✅ GOOD:
The LeveragedStrategy base class provides:
- Command execution framework
- Abstract methods for protocol operations (_supply, _borrow, etc.)
- Integration with SwapHelper for token swaps

❌ BAD:
[50 lines of Solidity code with full contract implementation]
```

### 2. Use Diagrams for Clarity

Prefer ASCII art or mermaid diagrams for architecture visualization:

```
SwapHelper (abstract)
    ↓
LeveragedStrategy (abstract)
    ↓
├── AaveLeveragedStrategy
├── MorphoLeveragedStrategy
└── EulerLeveragedStrategy
```

### 3. Keep It Concise

- ADR should be readable in 5-10 minutes
- Long code examples → link to GitHub or separate docs
- Implementation details → reference contracts/interfaces directory

### 4. Focus on Decisions, Not Documentation

ADRs capture **decisions**, not comprehensive documentation:
- **Decision**: "We chose inheritance over plugins because..."
- **Documentation**: "Here's how to use the API..." (belongs in docs/)

### 5. Distinguish Decision from Implementation

**ADRs document decisions, not implementation status:**

- **"Accepted"** = Decision made, may or may not be implemented yet
- **"Accepted (Implementation Pending)"** = Decision made, implementation tracked elsewhere
- Add **Implementation Status** section to clarify current state

**Example:**
```markdown
## Status
Accepted (Implementation Pending)

## Implementation Status
🔴 Not Implemented - This ADR documents the architectural decision.
Implementation tracked in IMPLEMENTATION_ROADMAP.md Phase 2.
```

**Use future tense when describing unimplemented features:**
- ✅ "Commands **will be** executed only by parent vault"
- ❌ "Commands **are** executed only by parent vault" (implies already done)

### 6. Update Status, Don't Delete

When an ADR becomes outdated:
- Update Status to "Deprecated" or "Superseded"
- Add reference to newer ADR
- Don't delete - historical context is valuable

## ADR Numbering

- Use sequential numbering: ADR-0001, ADR-0002, etc.
- Never reuse numbers
- Maintain chronological order

## Current ADRs

- [ADR-0001: Upgradeable Contract Architecture](0001-upgradeable-contract-architecture.md)
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md)
- [ADR-0003: Vault Architecture](0003-vault-architecture.md)
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md)
- [ADR-0005: Deposit & Withdrawal Settlement](0005-deposit-withdrawal-settlement.md)
- [ADR-0006: Child Strategy Interface](0006-child-vault-interface.md)
- [ADR-0007: Reentrancy Protection Strategy](0007-reentrancy-protection-strategy.md)
- [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md)
- [ADR-0009: Selective Withdrawal with Tolerance-Based Validation](0009-selective-withdrawal-validation.md)

## Pending Decisions

See [TODO.md](TODO.md) for pending architectural decisions.

## References

- [ADR GitHub](https://adr.github.io/)
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
