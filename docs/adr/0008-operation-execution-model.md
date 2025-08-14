# ADR-0008: Operation Execution Model with Delegatecall

## Status
Accepted

## Context
Need to define how operations are executed in the plugin-based architecture:
- Operators need to execute complex multi-step rebalancing operations
- Each step may involve different protocols (Aave, Morpho, Uniswap, etc.)
- Operations must be atomic (all succeed or all fail)
- Plugins should have flexible function interfaces without standardization constraints
- The main contract must maintain control and invariant checking

Requirements:
- Support arbitrary plugin function signatures
- Atomic execution of operation sequences
- Efficient batch processing
- Clear error handling and reporting

## Decision
Implement **operation-based execution model** where main contract receives a list of operations and executes them sequentially via delegatecall.

Execution flow:
- **Operator generates** encoded operations using algorithms/programs
- **Main contract receives** array of operations with plugin addresses and calldata
- **Sequential execution** via delegatecall in single transaction
- **Invariant validation** before and after complete operation sequence
