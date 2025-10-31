# Functional Requirements

## Overview
Functional requirements for the leveraged DeFi strategy system with parent/child vault architecture.

## FR-001: User Deposits and Withdrawals

### FR-001.1: Deposit Flow
- Users must be able to deposit in base tokens (USDC, USDT)
- System must support batch deposits through epoch system
- Users must be protected from receiving fewer shares than expected due to unfavorable execution
- Users must be able to cancel pending deposits before epoch processing

### FR-001.2: Withdrawal Flow
- Users must be able to request withdrawals by share amount
- System must support batch withdrawals through epoch system
- Withdrawals must be proportional - each user receives exact fraction of all assets
- Users must be protected from receiving fewer assets than expected due to unfavorable execution
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

### FR-002.2: Asset Allocation (Manual Mode)
- Manager must manually select which child strategy receives each deposit
- Manager must manually select which child strategy to withdraw from
- Allocation decisions must consider:
  - Current allocation across strategies and desired portfolio balance
  - Available liquidity in underlying protocols
  - Lending protocol limits (borrow caps, collateral caps)
  - Current yield opportunities and borrowing costs
  - Gas costs for different execution paths
- System must NOT enforce automatic target weights or threshold-based distributions
- Parent vault must provide view functions to expose per-child allocations for manager decision-making

### FR-002.3: Rebalancing
- System must support organic rebalancing through deposit/withdrawal flows
- System must support active rebalancing through keeper-initiated functions
- Rebalancing must support cross-child position transfers
- Rebalancing must support internal child optimization
- All rebalancing operations must be atomic

## FR-003: Command-Based Execution

### FR-003.1: Command System
- Child strategies must support flexible command-based execution for complex operations
- Child strategy commands must include: SUPPLY, WITHDRAW, BORROW, REPAY, SWAP
- Commands must be composable for complex strategies

### FR-003.2: Safety and Validation
- Each command must have clear safety guarantees
- System must validate command sequences for known attack patterns
- All assets must remain in vault after command execution
- Flash loan repayment must always be possible

## FR-004: Flash Loan Management

### FR-004.1: Flash Loan Coordination
- System must coordinate borrowed capital across multiple strategies within single transaction
- System must support atomic coordination across deposit/withdraw/rebalance operations
- Flash loan costs must be minimized to maximize net user returns

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

### FR-005.2: Flash Loan Repayment
- System must ensure all borrowed capital is repaid within the same transaction
- System must support scenarios where borrowed funds flow through multiple strategies before repayment

## FR-006: Child Strategy Types

### FR-006.1: Leveraged Yield-Token Strategies
- System must support leveraged yield-bearing token strategies as primary strategy type
- Strategies must involve purchasing yield-bearing tokens with leverage (borrowed capital)
- Each child strategy must focus on specific yield-token/debt-token/protocol combination
- Strategies must maximize yield through leverage while managing liquidation risk

### FR-006.2: DEX and Aggregator Support
- Child strategies must support token purchases through multiple DEX protocols:
  - **Pendle** - for PT (Principal Token) and yield token trading
  - **Odos** - for DEX aggregation and optimal routing
  - **KyberSwap** - for additional liquidity and routing options
- System must be extensible to support additional DEX protocols in the future
- Strategies must use optimal routing to minimize slippage and maximize efficiency
- Each strategy must handle protocol-specific interfaces and requirements

### FR-006.3: Lending Protocol Support
- Child strategies must support borrowing from multiple lending protocols:
  - **Aave** - for established lending with high liquidity
  - **Morpho** - for optimized lending rates and zero-fee flash loans
  - **Euler** - for advanced risk management and capital efficiency
- Protocol selection must be based on:
  - Available liquidity for target assets
  - Competitive borrowing rates
  - Risk parameters and collateral requirements
  - Protocol reliability and security

### FR-006.4: Strategy Granularity
- Each child strategy must handle specific combination of:
  - **Yield Token** - specific yield-bearing asset (e.g., sUSDe, stETH, PT-tokens)
  - **Debt Token** - specific borrowing asset (e.g., USDC, USDT, ETH)
  - **Lending Protocol** - specific protocol and market (e.g., Aave V3 USDC market)
- New yield token, debt token, or protocol/market requires separate child strategy
- Parent vault manages fund transfers between child strategies for optimization

### FR-006.5: Strategy Responsibilities
- Child strategies must handle:
  - **Capital Deployment** - executing leveraged positions using provided capital
  - **Position Monitoring** - tracking collateral ratios, liquidation risks, yield accrual
  - **Risk Management** - maintaining safe collateral ratios within strategy parameters
  - **Yield Optimization** - maximizing returns while staying within risk limits
- Keeper (off-chain service) must handle:
  - **Stop-Loss Execution** - automatically deleverage or exit positions when NAV drops below configured thresholds
  - **Take-Profit Execution** - automatically lock in profits when NAV reaches configured profit targets
  - **Delayed Rebalancing** - execute queued rebalancing operations when protocol limits allow
  - **Risk Monitoring** - continuously monitor liquidation risks and collateral ratios
  - **Performance Tracking** - measuring strategy effectiveness and ROI
- Manager (human operator) must handle:
  - **Strategy Selection** - manually choose which child strategy for each deposit/withdrawal
  - **Rebalancing Decisions** - decide when and how to move funds between strategies
  - **Portfolio Management** - monitor overall allocation and adjust as needed

### FR-006.6: Strategy Lifecycle Management
- System must support adding new child strategies without disrupting existing ones
- Parent vault must handle migration of capital between strategies when:
  - New strategy offers better risk/reward profile
  - Existing strategy approaches capacity limits
  - Market conditions favor different token/protocol combinations
  - Protocol upgrades or changes require strategy updates
- Migration must preserve user positions and maintain fair value distribution