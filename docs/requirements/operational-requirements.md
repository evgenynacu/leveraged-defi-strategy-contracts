# Operational Requirements

## Overview
Operational requirements for the keeper (backend service) that manages the leveraged DeFi strategy system, including deposit/withdrawal processing, rebalancing, risk management, and profit-taking.

## OR-001: Backend Keeper Responsibilities

### OR-001.1: Core Keeper Functions
The keeper is an off-chain service responsible for:
- **Strategy Execution**: Processing user deposit/withdrawal requests through optimal execution paths
- **Portfolio Management**: Maintaining target allocations across child strategies
- **Risk Monitoring**: Continuous monitoring of strategy health and market conditions
- **Automated Trading**: Executing rebalancing, risk management, and profit-taking operations

### OR-001.2: Keeper Architecture Requirements
- Must operate as a reliable, fault-tolerant service with high uptime (>99.9%)
- Must handle concurrent operations across multiple strategies safely
- Must maintain transaction nonce management and gas price optimization
- Must implement comprehensive logging and monitoring for all operations
- Must support multiple deployment environments (mainnet, testnets)

## OR-002: Deposit and Withdrawal Processing

### OR-002.1: Execution Path Calculation
For each pending deposit/withdrawal request, keeper must:
- **Analyze Market Conditions**: Check liquidity, slippage, and gas costs across all supported DEX protocols
- **Calculate Optimal Routes**: Determine best DEX routing for token swaps:
  - Pendle Router for PT token operations
  - Odos API for cross-DEX aggregation and optimal pricing
  - KyberSwap MetaAggregationRouter for additional routing options
  - Simulate transactions and select optimal path based on output amount minus gas costs
- **Determine Flash Loan Requirements**: Calculate optimal flash loan amounts and providers
- **Generate Command Sequences**: Create detailed command arrays for smart contract execution
- **Validate Execution**: Simulate transactions before submission to ensure success

**Note**: Lending protocol selection and strategy allocation is determined manually by the vault manager, including target weights for assets within strategies. This may be automated in the future.

### OR-002.2: Execution Timing and Batching
- **Epoch Processing**: Process all pending requests in batches during designated epochs
- **Gas Optimization**: Batch multiple operations when economically beneficial
- **MEV Protection**: Use private mempools or protected transaction pools when available
- **Deadline Management**: Ensure all operations complete within acceptable timeframes
- **Failed Transaction Handling**: Implement retry logic with adjusted parameters

## OR-003: Strategy Rebalancing Management

### OR-003.1: Target Weight Monitoring
Keeper must continuously monitor actual vs target allocations:
- **Weight Calculation**: Calculate current allocation percentages across all child strategies
- **Deviation Tracking**: Monitor deviations from target weights in real-time
- **Threshold Configuration**: Define rebalancing thresholds to prevent excessive operations (specific values determined per strategy)

### OR-003.2: Rebalancing Opportunity Detection
Keeper must identify rebalancing opportunities based on:
- **Rate Arbitrage**: Detect significant borrowing rate differences between protocols (>0.5% APY)
- **Liquidity Availability**: Monitor when previously unavailable liquidity becomes accessible
- **Market Conditions**: Identify favorable conditions for strategy migration:
  - Improved yield opportunities in specific protocols
  - Reduced borrowing costs or increased lending yields
  - Better liquidation protection parameters
- **Protocol Capacity Changes**: React to changes in borrowing caps, supply limits, or risk parameters

### OR-003.3: Rebalancing Execution Strategy
- **Cost-Benefit Analysis**: Only execute rebalancing when benefits exceed gas costs by significant margin (>2x)
- **Gradual Rebalancing**: Implement gradual shifts over multiple transactions for large rebalances
- **Market Impact Minimization**: Split large operations to reduce slippage and market impact
- **Timing Optimization**: Execute rebalancing during optimal market conditions and gas prices
- **Rollback Capability**: Ability to reverse rebalancing if market conditions change adversely

## OR-004: Risk Management and Loss Protection

### OR-004.1: Drawdown Monitoring
Keeper must implement comprehensive drawdown protection:
- **Real-time NAV Tracking**: Monitor strategy NAV changes with block-level precision
- **Drawdown Calculation**: Track rolling drawdown from recent peaks over multiple timeframes
- **Strategy-Specific Limits**: Apply different drawdown limits based on strategy risk profiles (specific values determined per strategy)
- **Portfolio-Level Monitoring**: Track overall portfolio drawdown across all strategies

### OR-004.2: Risk Response Actions
When drawdown limits are exceeded, keeper must:
- **Immediate Assessment**: Analyze cause of drawdown (market movement, liquidation risk, protocol issues)
- **Graduated Response**: Implement response based on severity (specific thresholds and actions determined per strategy)
- **Deleveraging Execution**: Systematically reduce positions to lower risk exposure
- **Asset Protection**: Convert volatile assets to stable assets during severe market stress
- **Communication**: Alert administrators and users about risk management actions

### OR-004.3: Liquidation Prevention
- **Collateral Ratio Monitoring**: Continuously track collateral ratios across all lending protocols
- **Early Warning System**: Alert when collateral ratios approach danger zones (specific thresholds determined per strategy)
- **Automatic Position Adjustment**: Reduce leverage automatically when approaching liquidation
- **Emergency Deleveraging**: Rapid position closure using flash loans when necessary

## OR-005: Profit-Taking Automation

### OR-005.1: Profit Target Configuration
Keeper must manage profit-taking based on:
- **Strategy-Level Targets**: Configure profit targets per strategy type (specific values determined per strategy)
- **Time-Based Targets**: Implement time decay for profit targets (reduce targets over time)
- **Market Condition Adjustments**: Adjust targets based on overall market volatility

### OR-005.2: Profit-Taking Execution
- **Partial Profit-Taking**: Take profits gradually rather than all at once (specific thresholds determined per strategy)
- **Optimal Timing**: Execute profit-taking during favorable market conditions
- **Reinvestment Strategy**: Redeploy profits into lower-risk strategies or hold as stable assets
- **Gas Efficiency**: Only execute profit-taking when profits significantly exceed gas costs

### OR-005.3: PnL Calculation and Tracking
- **Real-time PnL Monitoring**: Track unrealized and realized PnL for each strategy
- **Benchmark Comparison**: Compare strategy performance against relevant benchmarks
- **Risk-Adjusted Returns**: Calculate Sharpe ratios and other risk-adjusted metrics
- **Historical Performance**: Maintain comprehensive performance history for analysis
- **Profit Attribution**: Track profit sources (yield, leverage, arbitrage, etc.)

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