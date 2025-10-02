# Architecture Decision Records - TODO

This document tracks pending improvements and clarifications for the ADR documentation.

## High Priority

### 1. Add weight invariants concrete formula to ADR-0003
**Status:** Pending
**Description:** Define `_checkWeightInvariants()` implementation with concrete formulas
- What are the weight thresholds?
- How are they configured?
- What happens if invariant fails (revert)?
- Example implementation

**Location:** ADR-0003, add new section after "Unified Rebalancing Architecture"

---

### 2. Document commands validation in ADR-0002
**Status:** Pending
**Description:** Specify concrete validation logic for command execution
- What are "known attack patterns"?
- How to ensure flash loan repayment is "always possible"?
- What slippage limits are acceptable?
- How to prevent unauthorized transfers in command data?
- Whitelist of allowed protocols/addresses
- Token balance checks before/after commands
- Reentrancy guard implementation

**Location:** ADR-0002, expand "Validation Requirements" section

---

## Medium Priority

### 3. Add gas estimation benchmarks for keeper operations
**Status:** Pending
**Description:** Document expected gas costs for each operation type
- processDeposits() with N children
- processWithdrawals() with N children
- rebalance() operations (cross-child, internal)
- Comparison with/without flash loans
- Multi-currency debt overhead

**Location:** Create new section in ADR-0005 or separate ADR-0008

---

### 4. Design emergency procedures (pause, circuit breakers)
**Status:** Pending
**Description:** Document emergency response mechanisms
- Emergency pause mechanism
- Emergency withdrawal mode (bypass epochs)
- Oracle override for governance
- Flash loan provider switching
- Upgrade emergency fast-track
- Fund recovery procedures
- Who can trigger emergency actions?
- Timelock requirements

**Location:** Create ADR-0007: "Emergency Procedures and Circuit Breakers"

---

### 5. Design oracle failure handling mechanisms
**Status:** Pending
**Description:** Specify fallback logic for oracle failures
- Maximum acceptable staleness (current: 1 hour mentioned)
- Price deviation limits (current: ±2% mentioned)
- Fallback oracles (Chainlink as secondary)
- Emergency mode: Pause deposits/withdrawals if all oracles fail
- Manual override: Governance can update prices in emergency
- Handling for each oracle type:
  - PendleOracle (PT pricing)
  - Stablecoin price feeds (USDT/USDC/DAI)
  - Yield-bearing token oracles (sUSDe, stETH)

**Location:** Add section to ADR-0004: "NAV Calculation Method"

---

## Completed

- [x] Add `rebalance()` to IChildVault interface (ADR-0006)
- [x] Fix withdraw signature in ADR-0005 line 99 (added flashLoanRepay, params)
- [x] Document flash loan repayment pattern (ADR-0006)
- [x] Fix first deposit decimals - shares normalized to 1e18 scale (ADR-0006)
- [x] Fix NAV accumulation logic - pending deposits exclusion (ADR-0005)
- [x] Add multi-currency debt support documentation (ADR-0006)

---

## Future Considerations

### Low Priority Items
- Slippage protection validation (who sets minSharesOut/minAssetsOut?)
- Partial withdrawal fulfillment - locked share accounting details
- Flash loan fee handling for non-Morpho providers
- First epoch multi-user handling documentation
- Rounding policy unification across ADRs
- Keeper authorization mechanism details
- Child share transferability clarification
- Deposit cancellation refund mechanics

---

## Notes

- All critical and high severity issues from initial architecture audit have been resolved
- Multi-currency debt support was added to optimize borrow rates (1-2% difference → 5-10% equity returns with leverage)
- Unified rebalance architecture successfully consolidates all rebalancing operations

**Last Updated:** 2025-10-02
