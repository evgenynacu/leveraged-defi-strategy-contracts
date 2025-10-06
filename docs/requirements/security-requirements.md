# Security Requirements

## Overview
Security requirements for the leveraged DeFi strategy system covering access control, invariant protection, and safety measures.

## SR-001: Access Control

### SR-001.1: Role-Based Permissions
- Only parent vault can call child strategy operations
- Only authorized keepers can call epoch processing functions (`processDeposits`, `processWithdrawals`, `rebalance`)
- Only authorized governance can perform contract upgrades
- Child strategies must enforce single-owner constraint (only parent can call)

### SR-001.2: Keeper Authorization
- Keeper role must be properly configured and managed
- Keeper decisions must respect on-chain invariants:
  - Target weight percentages and thresholds
  - Slippage protection (`minSharesOut` for deposits, `minAssetsOut` for withdrawals)
  - Single-owner constraint enforcement
  - NAV preservation (rebalance cannot significantly decrease NAV)

## SR-002: Invariant Protection

### SR-002.1: NAV Preservation
- NAV must not significantly decrease after operations (only gas/slippage tolerance)
- NAV decrease threshold: maximum 1% (99% of previous NAV)
- Weight constraints must be maintained after rebalancing
- All borrowed flash loan funds must be repaid in same transaction

### SR-002.2: Asset Protection
- All intermediate tokens must be converted to strategy assets
- No tokens should be sent to external addresses (except authorized transfers)
- Vault's position must remain internally consistent (collateral/debt ratios valid)
- Assets must remain within vault contracts during command execution

### SR-002.3: Command Validation
- Validate command sequences for known attack patterns
- Reentrancy protection for command execution
- Ensure flash loan repayment is always possible
- Validate slippage limits and deadlines for all swaps
- Check that no commands attempt unauthorized token transfers

## SR-003: Flash Loan Security

### SR-003.1: Flash Loan Constraints
- Flash loans must be repaid within same transaction
- Flash loan amount must not exceed available liquidity
- Flash loan callbacks must validate operation type and data integrity
- No nested flash loans from different providers

### SR-003.2: Flash Loan Validation
- Validate flash loan data before execution
- Ensure flash loan amount matches expected requirements
- Verify flash loan provider is authorized
- Check flash loan fee handling (zero fees for Morpho)

## SR-004: Command System Security

### SR-004.1: Command Restrictions
- NO Transfer operations allowed in commands
- Commands cannot move funds out of vault
- All assets must remain in vault after command execution
- Only vault logic (not keeper commands) can transfer assets to parent or users

### SR-004.2: Command Execution Safety
- Each command must have clear safety guarantees
- Atomic execution: all commands succeed or fail together
- Limited type safety: bytes encoding requires thorough validation
- Gas overhead must be reasonable and predictable

## SR-005: Oracle Security

### SR-005.1: Oracle Manipulation Protection
- Use protocol-native measures over external oracles when possible
- PT token pricing must use Pendle Oracle with period=0 for spot pricing
- Multiple oracle sources for critical price feeds
- Oracle staleness checks and circuit breakers

### SR-005.2: Price Validation
- Validate oracle prices against reasonable bounds
- Implement price deviation checks between different oracle sources
- Handle oracle failures gracefully (circuit breakers)
- Prevent oracle-based arbitrage at entry/exit

## SR-006: Upgrade Security

### SR-006.1: Upgrade Constraints
- Storage layout must be preserved (append-only)
- Proxy contracts must remain immutable
- Upgrade timelock must be enforced
- Upgrade governance must be multi-signature or DAO-based

### SR-006.2: Upgrade Validation
- Comprehensive testing before upgrade deployment
- Upgrade impact assessment on existing positions
- Rollback mechanism in case of upgrade issues
- Clear upgrade communication to users

## SR-007: Emergency Procedures

### SR-007.1: Emergency Actions
- Emergency pause functionality for critical operations
- Emergency withdrawal mechanism for users
- Circuit breakers for abnormal market conditions
- Admin emergency functions with time locks

### SR-007.2: Incident Response
- Clear escalation procedures for security incidents
- Automated monitoring and alerting systems
- Communication protocols for users during incidents
- Post-incident analysis and improvement processes

## SR-008: User Protection

### SR-008.1: Slippage Protection
- `minSharesOut` enforcement for deposits
- `minAssetsOut` enforcement for withdrawals
- Deadline parameters for time-sensitive operations
- MEV protection for user transactions

### SR-008.2: Fair Treatment
- No front-running of user transactions by keepers
- Equal treatment of users within same epoch
- Transparent fee structure and calculation
- Clear disclosure of risks and mechanisms

## SR-009: Monitoring and Auditing

### SR-009.1: Event Logging
- Comprehensive event logging for all monetary flows
- Events must enable complete financial reconstruction
- Include both token amounts and USD values using oracles
- All monetary flows must be traceable for audit purposes

### SR-009.2: Audit Requirements
- Regular smart contract audits by reputable firms
- Formal verification for critical components
- Bug bounty program for continuous security testing
- Public security documentation and reports