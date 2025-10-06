# Functional Requirements

## Overview
Functional requirements for the leveraged DeFi strategy system with parent/child vault architecture.

## FR-001: User Deposits and Withdrawals

### FR-001.1: Deposit Flow
- Users must be able to deposit in base tokens (USDC, USDT)
- System must support batch deposits through epoch system
- Deposits must be processed atomically - either all succeed or all revert
- Users must receive slippage protection through `minSharesOut`
- Users must be able to cancel pending deposits before epoch processing

### FR-001.2: Withdrawal Flow
- Users must be able to request withdrawals by share amount
- System must support batch withdrawals through epoch system
- Withdrawals must be proportional - each user receives exact fraction of all assets
- Users must receive slippage protection through `minAssetsOut`
- System must support partial fills when liquidity is insufficient
- Users must be able to cancel pending withdrawals before epoch processing

### FR-001.3: Fair Entry/Exit
- Entry must be based on deltaNAV (NAV_after - NAV_before) for fair valuation
- Exit must provide exact proportional share of actual assets, not theoretical NAV
- No value transfer between user cohorts during entry/exit

## FR-002: Multi-Strategy Support

### FR-002.1: Child Strategy Management
- Parent vault must support multiple child strategies
- Each child strategy must have single owner (parent vault)
- Child strategies must support multi-token operations (not just base asset)
- Each child strategy must provide totalAssets() for NAV calculation

### FR-002.2: Asset Allocation
- System must support configurable target weights for each child vault
- Keeper must be able to determine actual allocation per epoch based on:
  - Target weights and current allocations
  - Available liquidity in underlying protocols
  - Lending protocol limits (borrow caps, collateral caps)
  - Gas optimization
- System must support threshold-based flexibility for efficient gas usage

### FR-002.3: Rebalancing
- System must support organic rebalancing through deposit/withdrawal flows
- System must support active rebalancing through keeper-initiated functions
- Rebalancing must support cross-child position transfers
- Rebalancing must support internal child optimization
- All rebalancing operations must be atomic

## FR-003: Command-Based Execution

### FR-003.1: Command System
- System must support flexible command-based execution for complex strategies
- Commands must include: FlashLoan, LendingDeposit, LendingWithdraw, LendingBorrow, LendingRepay, Swap
- Transfer operations must NOT be allowed in commands - only vault logic can transfer assets
- Commands must be composable for complex strategies

### FR-003.2: Safety and Validation
- Each command must have clear safety guarantees
- System must validate command sequences for known attack patterns
- All assets must remain in vault after command execution
- Flash loan repayment must always be possible

## FR-004: Flash Loan Management

### FR-004.1: Flash Loan Coordination
- Parent vault must manage all flash loans for operation coordination
- System must support single flash loan for multiple children (efficiency)
- System must support atomic coordination across deposit/withdraw/rebalance operations
- Primary provider: Morpho (zero fee flash loans)

### FR-004.2: Operation Types
- System must support DEPOSIT operations (user deposits to children)
- System must support WITHDRAW operations (user withdrawals from children)
- System must support REBALANCE operations (asset movement/optimization)

## FR-005: Multi-Token Support

### FR-005.1: Flexible Token Operations
- Child strategies must accept any token for deposit/withdraw
- System must support direct position transfers (PT → PT)
- System must support optimal flash loan currency selection
- System must minimize slippage through reduced token swaps

### FR-005.2: Provided/Expected Token Pattern
- Parent must explicitly specify what it provides to child strategy
- Parent must explicitly specify what it expects back
- Child strategies must approve expected tokens for parent collection
- System must support debt obligation pattern