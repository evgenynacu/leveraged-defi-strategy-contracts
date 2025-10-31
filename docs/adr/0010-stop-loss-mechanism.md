# ADR-0010: Stop-Loss Mechanism

## Status
Accepted (Implementation Pending)

## Date
2025-10-31

## Implementation Status
🔴 Not Implemented - This ADR documents the architectural decision for stop-loss protection.

## Context

Leveraged DeFi strategies involve significant risk of capital loss due to:
1. **Underlying Asset Depeg**: For PT-token strategies, the underlying asset (e.g., sUSDe, wstETH) may lose its peg, causing severe losses
2. **Market Volatility**: Price movements can quickly erode leveraged positions
3. **Liquidation Risk**: Excessive leverage can lead to liquidation on lending protocols
4. **Protocol Failures**: Smart contract bugs or exploits in integrated protocols

The system needs automated protection that:
- Detects genuine threats without false positives from normal market fluctuations
- Enables fast emergency response while maintaining security controls
- Differentiates between temporary price volatility and structural problems
- Provides clear audit trail for all protective actions

**Challenge for PT-Token Strategies**: PT tokens naturally experience price and yield fluctuations as they approach maturity. Stop-loss must NOT trigger on these normal fluctuations, only on underlying asset problems.

**Related Requirements:**
- [OR-003.1: Stop-Loss Protection](../requirements/operational-requirements.md#or-0031-stop-loss-protection)
- [OR-004.1: Liquidation Risk Monitoring](../requirements/operational-requirements.md#or-0041-liquidation-risk-monitoring)
- [FR-006.5: Strategy Responsibilities](../requirements/functional-requirements.md#fr-0065-strategy-responsibilities)

## Decision

### Unified Monitoring Approach: "Primary Asset" Concept

Each strategy defines a **primary asset** - the core asset whose price stability directly impacts strategy safety:
- **PT-Token Strategies**: Primary asset = underlying asset that PT redeems to (e.g., sUSDe, wstETH)
  - Rationale: PT price fluctuations are normal as it approaches maturity, but underlying asset depeg is a genuine threat
- **Non-PT Strategies**: Primary asset = collateral asset (e.g., wstETH, stETH)
  - Rationale: Collateral value directly determines liquidation risk

**Unified Trigger Logic:**
- Calculate reference price: moving average or 99th percentile over recent period (e.g., 24 hours)
  - 99th percentile filters outlier spikes while capturing sustained price level
- Compare current price to reference: `(Reference_price - Current_price) / Reference_price > Threshold`
- Require time confirmation (e.g., 10 minutes) to filter temporary spikes
- Trigger when drawdown from reference exceeds threshold for confirmation period

### Volatility-Based Thresholds

Stop-loss thresholds will be dynamically configured based on asset volatility:
- **Data Sources**: CoinGecko, CoinMarketCap, DEX historical data, trusted on-chain oracles
- **Calculation**: Historical volatility analysis (e.g., 30-day rolling)
- **Examples**:
  - Stablecoins (USDC, DAI): 2-3% threshold
  - Wrapped ETH (wstETH): 5-7% threshold
  - Higher volatility assets: proportionally wider thresholds
- **Periodic Review**: Thresholds adjusted based on changing market conditions

### State Machine Design

```
                    ┌──────────────┐
                    │    Normal    │
                    │   Operation  │
                    └──────┬───────┘
                           │
              Trigger      │
              Condition    │
              Met          │
                           ▼
                    ┌──────────────┐      Conditions
                    │    Alarm /   │◄──── Normalize
                    │  Stop-Loss   │      (Hysteresis)
                    │   Pending    │
                    └──────┬───────┘
                           │
              Approver     │
              Confirms     │
                           ▼
                    ┌──────────────┐
                    │  Stop-Loss   │
                    │   Approved   │
                    └──────┬───────┘
                           │
              Execution    │
              Complete     │
                           ▼
                    ┌──────────────┐
                    │  Recovered / │
                    │   Completed  │
                    └──────────────┘
```

**State Behaviors:**

1. **Normal State**
   - All operations allowed within normal risk parameters
   - Continuous monitoring of trigger conditions

2. **Alarm / Stop-Loss Pending State**
   - Keeper sets state when trigger conditions met
   - Records: timestamp, prices, trigger type, relevant metrics
   - **Restrictions**: Block operations that increase risk
     - New borrows
     - Increased leverage
     - Large swap operations
   - **Allowed**: Deposits, normal operations not increasing risk
   - **Recovery**: Keeper can clear if conditions normalize (hysteresis)

3. **Stop-Loss Approved State**
   - Special role (Stop-Loss Approver) confirms execution
   - **Emergency Powers**: Allows operations bypassing normal safety checks
     - Asset sales without oracle validation
     - Trades accepting larger slippage than normal limits
     - Forced position unwinding
   - Keeper executes within predefined limits:
     - Maximum volume per transaction
     - Time limits for completion
   - All actions logged with full audit trail

4. **Recovered State**
   - Position closed or deleveraged successfully
   - Return to Normal state when strategy is safe

### Stop-Loss Approver Role

**Purpose**: Enable fast, trusted decision-making for emergencies while maintaining accountability

**Design Options:**
- **Human Multisig**: 2-of-3 or 3-of-5 trusted operators (higher security, slower response)
- **Automated Service with Collateral**: Always-online service with economic stake (faster response)
- **Hybrid**: Automated service for smaller positions, multisig for large positions

**Responsibilities:**
- Review alarm conditions and context
- Approve stop-loss execution if threat is genuine
- Can reject if alarm was false positive
- Cannot directly execute trades (separation of duties)

**Accountability:**
- All approvals logged on-chain with justification hash
- Off-chain monitoring tracks approver response times
- Economic incentives for correct decisions, penalties for incorrect ones

### Hysteresis Mechanism

To prevent oscillation between Normal and Alarm states:
- **Trigger Threshold**: Lower threshold to enter Alarm (e.g., 3% depeg)
- **Recovery Threshold**: Higher threshold to exit Alarm (e.g., 1.5% depeg)
- **Time Requirements**: Both trigger and recovery require sustained conditions (e.g., 10 minutes)

### Keeper Responsibilities

**Monitoring Phase:**
- Continuous price feed monitoring for each strategy's primary asset
- Calculate reference price (moving average or 99th percentile over configured period)
- Compare current price to reference price to determine drawdown percentage
- Track time duration of threshold breaches

**Alarm Phase:**
- Set contract state to Alarm with trigger parameters
- Alert manager and Stop-Loss Approver
- Continue monitoring for recovery conditions
- Prepare execution plan for stop-loss

**Execution Phase:**
- After approval, calculate optimal deleveraging path:
  - Use flash loans for efficient unwinding
  - Minimize slippage through optimal routing
  - Consider gas costs in execution plan
- Execute position closing in stages if needed
- Convert to stable assets if configured
- Log all execution steps with outcomes

### On-Chain Contract Support

Strategy contracts must maintain stop-loss state and enforce access controls:

**State Tracking:**
- Stop-loss state enum (Normal, Alarm, Approved, Recovered)
- Alarm timestamp and trigger parameters hash for audit trail
- Stop-loss approver address for access control

**Access Control:**
- Modifier to block risk-increasing operations during Alarm state
- Modifier to restrict approver-only functions

**Key Functions:**
- Set alarm state with trigger parameters (keeper-only)
- Clear alarm state when conditions normalize (keeper-only, with hysteresis validation)
- Approve stop-loss execution (approver-only)
- Emergency withdrawal with bypass of normal safety checks (keeper-only, when approved)

## Consequences

### Positive

1. **Capital Protection**: Automated response to genuine threats protects user capital
2. **False Positive Avoidance**: Primary asset monitoring with reference price prevents unnecessary triggers on normal market fluctuations
3. **Unified Approach**: Single monitoring logic for all strategy types reduces implementation complexity
4. **Fast Response**: Always-online keeper with approver role enables rapid emergency response
5. **Accountability**: Multi-state design with logging provides clear audit trail
6. **Flexibility**: Volatility-based thresholds adapt to different asset characteristics
7. **Security Balance**: Approver role balances speed with security controls
8. **Recovery Capability**: Hysteresis mechanism allows recovery from temporary issues
9. **Simple Configuration**: Each strategy just needs to specify its primary asset

### Negative

1. **Keeper Dependency**: System relies on keeper being always available and functioning correctly
2. **Approver Risk**: Approver role is powerful and must be carefully secured
3. **Threshold Tuning**: Finding optimal thresholds requires data analysis and may need adjustment
4. **Gas Costs**: Additional state tracking and logging increase transaction costs
5. **Edge Cases**: Unusual market conditions might still cause false positives or missed triggers
6. **Reference Price Lag**: Moving average or percentile calculation may lag sudden market movements

### Neutral

1. **Centralization Trade-off**: Approver role adds centralization but improves response time
2. **Data Dependency**: Relies on accurate price feeds and volatility data
3. **Strategy-Specific Configuration**: Each strategy needs custom threshold configuration

## Alternatives Considered

### Alternative 1: Fully Automated Stop-Loss (No Approver)

**Approach**: Keeper automatically executes stop-loss when conditions met, no approval needed

**Rejected Because:**
- Higher risk of costly false positives
- No human judgment for unusual market conditions
- Cannot distinguish genuine depeg from oracle issues
- Emergency powers without oversight are too risky

### Alternative 2: Oracle-Based Circuit Breakers

**Approach**: Use Chainlink or similar oracles to detect depeg, automatic contract pause

**Rejected Because:**
- Oracle latency may be too slow for fast-moving events
- Circuit breakers are too blunt (freeze everything, no graduated response)
- Does not provide execution capability, only stops operations
- PT token oracle challenges (no reliable PT price oracles)

### Alternative 3: Portfolio-Level Stop-Loss Only

**Approach**: Monitor total portfolio NAV, ignore individual strategy issues

**Rejected Because:**
- Individual strategy failure might be hidden by other strategy gains
- Delayed response allows more damage before portfolio-level threshold reached
- Cannot provide strategy-specific responses
- Harder to diagnose and respond to specific issues

### Alternative 4: Time-Delayed Execution (Governance Vote)

**Approach**: Require governance vote or time-lock before stop-loss execution

**Rejected Because:**
- Too slow for genuine emergencies (hours to days delay)
- DeFi moves too fast for governance processes
- Users expect immediate protection in crisis
- Still need emergency mechanism, making governance layer redundant

## Related ADRs

- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - NAV calculation used in stop-loss monitoring
- [ADR-0008: LeveragedStrategy Architecture](0008-leveraged-strategy-architecture.md) - Base strategy architecture where stop-loss will be implemented

## Requirements Traceability

**Implements:**
- OR-003.1: Stop-Loss Protection
- OR-004.1: Liquidation Risk Monitoring
- FR-006.5: Strategy Responsibilities (Keeper duties)

**Related Security Requirements:**
- SR-007: Emergency Procedures
- SR-009: Monitoring and Auditing

## References

- Historical DeFi depegging events (UST, USDC depeg March 2023)
- Pendle PT token mechanics documentation
- Circuit breaker patterns in TradFi systems
- Chainlink depeg detection methodologies
