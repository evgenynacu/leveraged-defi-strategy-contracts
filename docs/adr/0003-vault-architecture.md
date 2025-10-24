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

**Related Requirements:**
- [FR-001: User Deposits and Withdrawals](../requirements/functional-requirements.md#fr-001-user-deposits-and-withdrawals)
- [FR-002: Multi-Strategy Support](../requirements/functional-requirements.md#fr-002-multi-strategy-support)
- [TR-005: Rebalancing Architecture](../requirements/technical-requirements.md#tr-005-rebalancing-architecture)
- [SR-001: Access Control](../requirements/security-requirements.md#sr-001-access-control)
- [SR-002: Invariant Protection](../requirements/security-requirements.md#sr-002-invariant-protection)

## Decision
- **Parent/child design:** Parent holds users' funds and owns N child strategies.
- **Epochs:** Users submit deposits/withdrawals into queues; `processEpoch()` executes atomically.
- **Entry:** Mint parent shares from **deltaNAV = NAV_after − NAV_before** after real child deposits.
- **Exit:** Selective withdrawal from chosen strategies with tolerance-based validation (see [ADR-0009](0009-selective-withdrawal-validation.md)). Total withdrawn amount must match expected percentage of total NAV within tolerance. Each child strategy validates its own proportional withdrawal.
- **Child strategies:** single owner (parent), synchronous operations, no internal shares, multi-token support.
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
        IChildStrategy child = children[step.childIndex];

        if (step.operation == RebalanceOp.Withdraw) {
            // Deserialize: (percentage, outputToken, flashLoanToken, providedAmount, expectedAmount, data)
            (uint256 percentage, address outputToken, address flashLoanToken,
             uint256 providedAmount, uint256 expectedAmount, bytes memory data) =
                abi.decode(step.data, (uint256, address, address, uint256, uint256, bytes));

            // Transfer flash loan liquidity to child if any
            if (flashLoanToken != address(0) && providedAmount > 0) {
                IERC20(flashLoanToken).transfer(address(child), providedAmount);
            }

            // Execute withdrawal
            uint256 actualWithdrawn = child.withdraw(
                percentage, outputToken, flashLoanToken, providedAmount, expectedAmount, data
            );

            // Collect withdrawn assets
            IERC20(outputToken).transferFrom(address(child), address(this), actualWithdrawn);

            // Collect flash loan repayment if any
            if (flashLoanToken != address(0) && expectedAmount > 0) {
                IERC20(flashLoanToken).transferFrom(address(child), address(this), expectedAmount);
            }

        } else if (step.operation == RebalanceOp.Deposit) {
            // Deserialize: (depositToken, depositAmount, flashLoanToken, providedAmount, expectedAmount, data)
            (address depositToken, uint256 depositAmount, address flashLoanToken,
             uint256 providedAmount, uint256 expectedAmount, bytes memory data) =
                abi.decode(step.data, (address, uint256, address, uint256, uint256, bytes));

            // Transfer deposit assets to child
            IERC20(depositToken).transfer(address(child), depositAmount);

            // Transfer flash loan liquidity if any
            if (flashLoanToken != address(0) && providedAmount > 0) {
                IERC20(flashLoanToken).transfer(address(child), providedAmount);
            }

            // Execute deposit
            child.deposit(depositToken, depositAmount, flashLoanToken, providedAmount, expectedAmount, data);

            // Collect flash loan repayment if any
            if (flashLoanToken != address(0) && expectedAmount > 0) {
                IERC20(flashLoanToken).transferFrom(address(child), address(this), expectedAmount);
            }

        } else if (step.operation == RebalanceOp.Internal) {
            // Deserialize: (flashLoanToken, providedAmount, expectedAmount, data)
            (address flashLoanToken, uint256 providedAmount, uint256 expectedAmount, bytes memory data) =
                abi.decode(step.data, (address, uint256, uint256, bytes));

            // Transfer flash loan liquidity if any
            if (flashLoanToken != address(0) && providedAmount > 0) {
                IERC20(flashLoanToken).transfer(address(child), providedAmount);
            }

            // Execute rebalance
            child.rebalance(flashLoanToken, providedAmount, expectedAmount, data);

            // Collect flash loan repayment if any
            if (flashLoanToken != address(0) && expectedAmount > 0) {
                IERC20(flashLoanToken).transferFrom(address(child), address(this), expectedAmount);
            }
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

1. **Cross-child migration** - Move PT position from Morpho to Aave:
   ```solidity
   steps = [
       RebalanceStep(morphoChild, Withdraw, encode(
           1e18,                    // percentage: 100%
           PT_TOKEN,                // outputToken: receive PT
           USDT_TOKEN,              // flashLoanToken
           2000e6,                  // providedAmount: flash loan for deleverage
           0,                       // expectedAmount: parent keeps liquidity
           morphoParams
       )),
       RebalanceStep(aaveChild, Deposit, encode(
           PT_TOKEN, ptAmount,      // depositToken/Amount: deposit received PT
           USDT_TOKEN,              // flashLoanToken: same token
           0,                       // providedAmount: already provided in step 1
           2000e6,                  // expectedAmount: strategy borrows and returns
           aaveCommands
       ))
   ]
   ```

2. **Internal optimization** - Refinance debt within single child:
   ```solidity
   steps = [
       RebalanceStep(childA, Internal, encode(
           USDC_TOKEN,              // flashLoanToken
           1000e6,                  // providedAmount: flash loan for refinancing
           1000e6,                  // expectedAmount: expect flash loan back
           refinanceCommands
       ))
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
- [ADR-0009: Selective Withdrawal with Tolerance-Based Validation](0009-selective-withdrawal-validation.md) - Implements gas-efficient selective withdrawal model

## Requirements Traceability
- **FR-001.3**: Fair Entry/Exit - Implemented through deltaNAV-based entry and proportional exit
- **FR-002.1**: Child Strategy Management - Parent/child design with single owner pattern
- **FR-002.2**: Asset Allocation - Target weights and keeper-driven allocation strategy
- **FR-002.3**: Rebalancing - Unified rebalancing architecture with step-based approach
- **TR-005.1**: Unified Rebalancing System - RebalanceOp enum and RebalanceStep struct implemented
- **TR-005.2**: Rebalancing Function - Single rebalance() function with NAV and weight invariant checks
- **SR-001.1**: Role-Based Permissions - Parent-child ownership and keeper authorization
- **SR-002.1**: NAV Preservation - NAV invariant checks during rebalancing
- **SR-002.2**: Asset Protection - Proportional exit logic ensures fair asset distribution
