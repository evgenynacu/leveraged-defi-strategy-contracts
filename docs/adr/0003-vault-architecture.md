# ADR-0003: Vault Architecture v2

## Status
Accepted

## Date
2024-09-26

## Context
We need a safe, fair, and simple vault system with multi-strategy composition. Oracle-based NAV can drift (~±0.8%), so entry/exit must not rely on noisy spot oracles.

## Requirements
- **Security:** users must not operate strategies; only the vault orchestrates flows.
- **Fair entry:** no value transfer between cohorts at deposit time.
- **Fair exit:** withdrawers receive exactly their pro-rata share of *actual* assets, not theoretical NAV.
- **Composability:** support multiple child vaults.
- **Simplicity:** child strategies have one owner (parent) and sync I/O.
- **Determinism:** explicit rounding policy and idempotent processing.

## Decision
- **Parent/child design:** Parent holds users' funds and owns N child strategies.
- **Epochs:** Users submit deposits/withdrawals into queues; `processEpoch()` executes atomically.
- **Entry:** Mint parent shares from **deltaNAV = NAV_after − NAV_before** after real child deposits.
- **Exit:** Redeem strictly by **proportional units** of each asset (incl. cash); optional conversion to cash is done **proportionally**.
- **Child vaults:** single owner (parent), synchronous `deposit/withdraw`, PnL-based accounting.
- **Rounding:** round down to the vault on share/asset conversions to avoid dust exploits.

### Multi-Child Allocation Strategy
When multiple child vaults are present:
- **Target weights:** Each child vault has a configurable target allocation percentage (e.g., Child A: 60%, Child B: 40%).
- **Keeper-driven allocation:** Keeper (off-chain) determines actual allocation per epoch based on:
  - Target weights and current allocations
  - Available liquidity in underlying protocols
  - Lending protocol limits (borrow caps, collateral caps)
  - Gas optimization (may allocate 100% to one child if within threshold)
- **Threshold-based flexibility:** If actual allocation is within `target ± threshold`, deposits may be directed entirely to one child for gas efficiency or liquidity management.
  - Example: If Child A target is 60% ± 5%, and current is 58%, new deposits can go 100% to Child A until it reaches 65%.
- **Rebalancing:** When actual weights drift beyond threshold, reconciliation happens via:
  - **Organic rebalancing:** Future deposit/withdrawal flows adjusted to bring weights back to target (no forced liquidations)
  - **Active rebalancing:** Keeper-initiated `rebalance()` function to move assets between children when necessary
- **Liquidity awareness:** Respect each child's withdrawability; if a child is illiquid during withdrawal, deliver its realizable portion and queue the remainder (see ADR-0005).
- **Transparency:** Expose per-child values and current vs target allocations via view functions.

### Unified Rebalancing Architecture

Parent vault implements a single `rebalance()` function that handles all rebalancing operations through a flexible step-based approach:

```solidity
enum RebalanceOp { Withdraw, Deposit, Internal }

struct RebalanceStep {
    uint256 childIndex;   // which child vault to operate on
    RebalanceOp operation; // type of operation
    bytes data;           // operation-specific parameters (deserialized based on operation type)
}

function rebalance(
    uint256 totalFlashLoan,
    RebalanceStep[] calldata steps
) external onlyKeeper {
    uint256 navBefore = _calculateTotalNAV();

    // Single flash loan for entire rebalance sequence
    flashLoanProvider.flashLoan(
        totalFlashLoan,
        abi.encode(OperationType.REBALANCE, steps)
    );
}

function _executeRebalance(RebalanceStep[] memory steps) internal {
    for (uint i = 0; i < steps.length; i++) {
        RebalanceStep memory step = steps[i];
        IChildVault child = children[step.childIndex];

        if (step.operation == RebalanceOp.Withdraw) {
            // Deserialize: (shares, flashLoanRepay, params)
            (uint256 shares, uint256 flashLoanRepay, bytes memory params) =
                abi.decode(step.data, (uint256, uint256, bytes));

            underlying.transfer(address(child), flashLoanRepay);
            uint256 assets = child.withdraw(shares, flashLoanRepay, params);
            underlying.transferFrom(address(child), address(this), flashLoanRepay + assets);

        } else if (step.operation == RebalanceOp.Deposit) {
            // Deserialize: (assets, flashLoanRepay, commands)
            (uint256 assets, uint256 flashLoanRepay, bytes memory commands) =
                abi.decode(step.data, (uint256, uint256, bytes));

            underlying.transfer(address(child), assets + flashLoanRepay);
            (uint256 shares,,) = child.deposit(assets, flashLoanRepay, commands);
            underlying.transferFrom(address(child), address(this), flashLoanRepay);

        } else if (step.operation == RebalanceOp.Internal) {
            // Deserialize: (flashLoanRepay, commands)
            (uint256 flashLoanRepay, bytes memory commands) =
                abi.decode(step.data, (uint256, bytes));

            underlying.transfer(address(child), flashLoanRepay);
            child.rebalance(flashLoanRepay, commands);
            underlying.transferFrom(address(child), address(this), flashLoanRepay);
        }
    }

    uint256 navAfter = _calculateTotalNAV();

    // INVARIANT: NAV should not decrease significantly (only gas/slippage)
    require(navAfter >= navBefore * 99 / 100, "NAV decreased too much");

    // INVARIANT: weights must be within thresholds after rebalance
    _checkWeightInvariants();
}
```

**Use cases:**

1. **Cross-child migration** - Move assets from Child A to Child B:
   ```solidity
   steps = [
       RebalanceStep(childA, Withdraw, encode(shares, flashLoan, params)),
       RebalanceStep(childB, Deposit, encode(assets, flashLoan, commands))
   ]
   ```

2. **Internal optimization** - Refinance debt within single child:
   ```solidity
   steps = [
       RebalanceStep(childA, Internal, encode(flashLoan, refinanceCommands))
   ]
   ```

3. **Complex rebalancing** - Combine multiple operations atomically:
   ```solidity
   steps = [
       RebalanceStep(childA, Withdraw, ...),
       RebalanceStep(childB, Withdraw, ...),
       RebalanceStep(childC, Deposit, ...),
       RebalanceStep(childA, Internal, ...)  // optimize after partial withdrawal
   ]
   ```

**Benefits:**
- Single entry point for all rebalancing operations
- Flexible composition of operations in single atomic transaction
- Efficient flash loan usage (one loan for entire sequence)
- Clear separation between cross-child and internal operations

## Consequences
- Honest entry and exit independent of oracle noise.
- Simple child adapters; all complexity (queues/epochs/mint/burn) lives in the parent.
- Predictable, auditable accounting.

## Related ADRs
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - Defines how NAV is calculated for entry/exit
- [ADR-0005: Deposit & Withdrawal Settlement](0005-deposit-withdrawal-settlement.md) - Details epoch processing mechanics
- [ADR-0006: Child Vault Interface](0006-child-vault-interface.md) - Specifies child vault contract interface
