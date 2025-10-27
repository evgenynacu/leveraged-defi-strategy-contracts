# Operational Requirements

## Overview
Operational requirements for the keeper (backend service) that manages the leveraged DeFi strategy system, including deposit/withdrawal processing, rebalancing, risk management, and profit-taking.

## OR-001: Backend Keeper Responsibilities

### OR-001.1: Core Keeper Functions
The keeper is an off-chain service responsible for:
- **Strategy Execution**: Processing user deposit/withdrawal requests through optimal execution paths as directed by manager
- **Automated Risk Management**: Executing stop-loss, take-profit, and delayed rebalancing operations
- **Risk Monitoring**: Continuous monitoring of strategy health, liquidation risks, and market conditions
- **Performance Tracking**: Measuring strategy effectiveness, PnL, and risk metrics

### OR-001.2: Keeper Architecture Requirements
- Must operate as a reliable, fault-tolerant service with high uptime (>99.9%)
- Must handle concurrent operations across multiple strategies safely
- Must maintain transaction nonce management and gas price optimization
- Must implement comprehensive logging and monitoring for all operations
- Must support multiple deployment environments (mainnet, testnets)

## OR-002: Deposit and Withdrawal Processing

### OR-002.1: Manual Strategy Selection
For each pending deposit/withdrawal request:
- **Manager Decision**: Vault manager explicitly selects which child strategy to use for the operation
- **Strategy Selection Criteria** (manager considerations):
  - Current allocation across strategies and desired portfolio balance
  - Available liquidity in each strategy's underlying protocol
  - Protocol caps and limits (borrow caps, supply caps, collateral limits)
  - Current yield opportunities and borrowing costs in each protocol
  - Gas costs for different execution paths
  - Liquidity conditions for withdrawal (which strategy can provide funds most efficiently)
- **No Automatic Distribution**: Parent vault does NOT automatically split deposits across multiple strategies
- **Explicit Control**: Each deposit/withdrawal operation targets a specific child strategy chosen by manager

### OR-002.2: Execution Path Calculation
Once strategy is selected, keeper must calculate optimal execution:
- **Analyze Market Conditions**: Check liquidity, slippage, and gas costs across all supported DEX protocols
- **Calculate Optimal Routes**: Determine best DEX routing for token swaps:
  - Pendle Router for PT token operations
  - Odos API for cross-DEX aggregation and optimal pricing
  - KyberSwap MetaAggregationRouter for additional routing options
  - Simulate transactions and select optimal path based on output amount minus gas costs
- **Determine Flash Loan Requirements**: Calculate optimal flash loan amounts and providers
- **Generate Command Sequences**: Create detailed command arrays for smart contract execution targeting selected strategy
- **Validate Execution**: Simulate transactions before submission to ensure success

### OR-002.3: Execution Timing and Batching
- **Epoch Processing**: Process all pending requests in batches during designated epochs
- **Gas Optimization**: Batch multiple operations when economically beneficial
- **MEV Protection**: Use private mempools or protected transaction pools when available
- **Deadline Management**: Ensure all operations complete within acceptable timeframes
- **Failed Transaction Handling**: Implement retry logic with adjusted parameters

## OR-003: Keeper Automation Responsibilities

### OR-003.1: Stop-Loss Monitoring and Execution
Keeper must continuously monitor strategy performance and execute protective measures:
- **NAV Monitoring**: Track strategy NAV changes in real-time to detect drawdowns
- **Stop-Loss Thresholds**: Monitor configured stop-loss levels per strategy (specific values determined per strategy)
- **Automatic Deleveraging**: When stop-loss is triggered:
  - Calculate optimal deleveraging path to reduce risk exposure
  - Execute withdrawal operations to reduce position size or exit completely
  - Use flash loans to unwind leveraged positions efficiently
  - Convert volatile assets to stable assets if configured
- **Graduated Response**: Implement partial deleveraging for moderate losses, full exit for severe losses
- **Notification**: Alert manager when stop-loss actions are executed

### OR-003.2: Take-Profit Monitoring and Execution
Keeper must monitor profit targets and execute profit-taking operations:
- **Profit Tracking**: Calculate unrealized profits for each strategy in real-time
- **Take-Profit Thresholds**: Monitor configured profit targets per strategy (specific values determined per strategy)
- **Automatic Profit-Taking**: When profit target is reached:
  - Execute partial or full withdrawal to lock in gains
  - Determine optimal output token (stable asset or base asset)
  - Calculate gas-efficient execution path
- **Reinvestment Logic**: Profits can be:
  - Held in parent vault as idle stable assets
  - Redeployed into same or different strategies (per manager configuration)
  - Distributed to users during next epoch
- **Time-Based Decay**: Adjust profit targets over time to capture profits in slow-moving markets

### OR-003.3: Delayed Rebalancing Execution
Keeper must handle rebalancing operations that cannot be executed immediately:
- **Protocol Limit Monitoring**: Track when deposits are blocked due to:
  - Borrowing caps reached in lending protocols
  - Supply caps reached in lending protocols
  - Collateral caps reached
  - Protocol emergency pauses
- **Queued Operations**: When rebalancing cannot execute immediately:
  - Monitor protocol limits and wait for capacity to become available
  - Execute queued deposits/withdrawals when limits are lifted
  - Re-calculate optimal execution parameters before executing (market may have changed)
- **Opportunity Detection**: Proactively identify when:
  - Protocol caps increase and allow pending operations
  - Market conditions become favorable for pending rebalances
  - Better yield opportunities emerge for queued funds
- **Manager Override**: Allow manager to cancel or modify queued operations if conditions change

## OR-004: Risk Monitoring and Alerting

### OR-004.1: Liquidation Risk Monitoring
Keeper must continuously monitor liquidation risks:
- **Collateral Ratio Tracking**: Monitor collateral ratios across all lending protocols in real-time
- **Health Factor Monitoring**: Track protocol-specific health factors (Aave) and LTV ratios (Morpho, etc.)
- **Early Warning Thresholds**: Configure alerts at multiple levels (specific thresholds determined per strategy):
  - Warning level: Collateral ratio approaching concern zone
  - Critical level: Immediate action required to prevent liquidation
  - Emergency level: Liquidation imminent
- **Price Movement Simulation**: Model impact of price swings on collateral ratios
- **Automatic Response**: When critical thresholds are breached, keeper should trigger stop-loss logic (see OR-003.1)

### OR-004.2: Protocol Risk Monitoring
Monitor external protocol health and risks:
- **Protocol Status**: Track protocol pause/emergency states in Aave, Morpho, and other integrated protocols
- **Oracle Health**: Monitor oracle price feeds for staleness, deviations, and failures
- **Liquidity Depth**: Track available liquidity for emergency exits
- **Smart Contract Events**: Listen for protocol upgrade events, parameter changes, and risk alerts

### OR-004.3: Portfolio-Level Risk Metrics
Calculate and monitor overall portfolio risk:
- **Total Exposure**: Sum of all leveraged positions across strategies
- **Correlation Risk**: Monitor correlation between different strategy positions
- **Concentration Risk**: Track if too much capital is in single protocol or asset
- **Overall Drawdown**: Track portfolio-level drawdown from peak NAV
- **Risk-Adjusted Returns**: Calculate Sharpe ratio and other risk metrics

## OR-005: Performance Tracking and Analytics

### OR-005.1: PnL Calculation and Tracking
- **Real-time PnL Monitoring**: Track unrealized and realized PnL for each strategy
- **Entry/Exit Tracking**: Record cost basis for all positions to calculate accurate PnL
- **Benchmark Comparison**: Compare strategy performance against relevant benchmarks (e.g., holding PT without leverage)
- **Risk-Adjusted Returns**: Calculate Sharpe ratios and other risk-adjusted metrics
- **Historical Performance**: Maintain comprehensive performance history for analysis
- **Profit Attribution**: Track profit sources (yield farming, leverage amplification, PT price appreciation, etc.)

### OR-005.2: Strategy Performance Metrics
- **APY Calculation**: Calculate actual APY for each strategy including all costs
- **Cost Breakdown**: Track gas costs, swap fees, borrowing costs, and other expenses
- **Efficiency Metrics**: Measure capital efficiency and utilization rates
- **Yield Comparison**: Compare actual yields vs expected yields from market rates
- **Slippage Tracking**: Monitor actual vs expected execution prices for swaps and deposits/withdrawals

## OR-006: Monitoring and Alerting

### OR-006.1: Health Check Requirements
- **System Health**: Monitor keeper service health, database connectivity, RPC node status
- **Strategy Health**: Check all child strategies for proper operation and fund safety
- **Protocol Health**: Monitor external protocol status and emergency states
- **Market Conditions**: Track relevant market indicators and volatility measures

### OR-006.2: Alert Configuration
- **Critical Alerts**: Immediate notification for liquidation risks, system failures, large losses
- **Warning Alerts**: Early warnings for approaching thresholds and suboptimal conditions
- **Information Alerts**: Regular updates on strategy performance and system status
- **Alert Channels**: Multiple notification channels (email, Slack, SMS, webhooks)

### OR-006.3: Performance Metrics
- **Execution Success Rate**: Track success rate of deposit/withdrawal/rebalancing operations
- **Latency Metrics**: Monitor response times for critical operations
- **Cost Efficiency**: Track gas costs relative to managed assets and profits
- **Yield Performance**: Monitor actual yields versus targets and benchmarks