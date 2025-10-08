# Implementation Roadmap

Дерево задач для завершения проекта leveraged DeFi strategy contracts.

**Legend:**
- ✅ Completed
- 🟡 In Progress
- ⚪ Not Started
- 🔴 Blocked

---

## Phase 1: Core Infrastructure (Foundation) 🟡

### 1.1 Oracle & Pricing ✅
- [x] PriceOracle implementation
- [x] Chainlink integration
- [x] Pendle PT token pricing
- [x] Multi-decimals support
- [x] USD value calculation
- [x] Comprehensive tests

### 1.2 Swap Infrastructure ✅
- [x] SwapHelper base contract
- [x] Multi-router support (KyberSwap, Odos, Pendle)
- [x] USD-based slippage protection
- [x] Configurable maxOracleSlippageBps
- [x] Precise approval management
- [x] Event logging (SR-009.1)
- [x] Integration tests
- [x] ADR-0007: Reentrancy Protection Strategy (decision documented, implementation in Phase 3)
- [x] ADR-0008: LeveragedStrategy Architecture (decision documented, implementation in Phase 2)
- [x] ADR-0002: Command-Based Execution updates (decision documented, implementation in Phase 2)

**Note:** ADRs 0002, 0007, 0008 document architectural decisions. Implementation tracked in subsequent phases.

### 1.3 Access Control (MVP) ⚪
**Dependencies:** Phase 2 completion

**Note:** Internal access control for vault/strategies will be implemented in MVP. External governance contracts deferred to post-launch.

#### 1.3.1 Internal Access Control (MVP)
- [ ] ParentVault: Ownable pattern
  - [ ] Owner address (hw wallet or multisig)
  - [ ] onlyOwner modifier for critical functions
- [ ] Keeper management in ParentVault
  - [ ] keeper address state variable
  - [ ] onlyKeeper modifier
  - [ ] setKeeper() function (onlyOwner)
- [ ] Child strategies: onlyParent modifier (part of Phase 2)
- [ ] Basic pause mechanism
  - [ ] paused state variable
  - [ ] pause()/unpause() functions (onlyOwner)
  - [ ] whenNotPaused modifier

#### 1.3.2 Deferred to Post-Launch (External Governance)
- [ ] ~~TimelockController contract~~
- [ ] ~~Governance token & voting~~
- [ ] ~~Multi-role RBAC (separate GOVERNANCE/EMERGENCY roles)~~
- [ ] ~~DAO integration~~

**Related Requirements:**
- SR-001: Access Control (internal implementation)

---

## Phase 2: Child Strategies (Inheritance-Based) 🟡

### 2.1 Base Leveraged Strategy ⚪
**Dependencies:** 1.2 (SwapHelper completed)

#### 2.1.1 IChildStrategy Interface
- [ ] Create `IChildStrategy.sol`
  - [ ] `deposit()` function signature (multi-token support)
  - [ ] `withdraw()` function signature (proportional exit)
  - [ ] `rebalance()` function signature (internal optimization)
  - [ ] `totalAssets()` view function
  - [ ] Events (Deposited, Withdrawn, Rebalanced)
- [ ] Comprehensive NatSpec documentation

**Related ADRs:** ADR-0006, ADR-0008

#### 2.1.2 LeveragedStrategy Abstract Contract
- [ ] Create `LeveragedStrategy.sol`
  - [ ] Inherit from SwapHelper and IChildStrategy
  - [ ] Command execution framework (_executeCommands)
  - [ ] CommandType enum (SUPPLY, WITHDRAW, BORROW, REPAY, SWAP)
  - [ ] Command struct (cmdType, data)
  - [ ] `onlyParent` access control
  - [ ] Oracle integration (inherited from SwapHelper)
  - [ ] Abstract methods for protocol-specific operations
    - [ ] `_supply()` - supply collateral
    - [ ] `_withdraw()` - withdraw collateral
    - [ ] `_borrow()` - borrow assets
    - [ ] `_repay()` - repay debt
    - [ ] `_getCollateralValue()` - get collateral in base asset terms
    - [ ] `_getDebtValue()` - get debt in base asset terms
  - [ ] Event emission helpers
- [ ] Tests for base functionality
  - [ ] Command parsing
  - [ ] Access control (onlyParent)
  - [ ] Approval logic for parent

**Related ADRs:** ADR-0008, ADR-0002, ADR-0007

### 2.2 Aave Leveraged Strategy ⚪
**Dependencies:** 2.1

#### 2.2.1 Aave Strategy Implementation
- [ ] Create `AaveLeveragedStrategy.sol`
  - [ ] Inherit LeveragedStrategy
  - [ ] Implement `_supply()` - Aave Pool.supply()
  - [ ] Implement `_withdraw()` - Aave Pool.withdraw()
  - [ ] Implement `_borrow()` - Aave Pool.borrow() with variable rate
  - [ ] Implement `_repay()` - Aave Pool.repay()
  - [ ] Implement `_getCollateralValue()` - query Aave user data
  - [ ] Implement `_getDebtValue()` - query Aave user data
  - [ ] Multi-currency debt support (USDC/USDT/DAI)
- [ ] Strategy-specific state
  - [ ] Aave Pool address
  - [ ] Market IDs mapping

#### 2.2.2 Aave Strategy Testing
- [ ] Unit tests
  - [ ] All abstract method implementations
  - [ ] Command sequence execution
  - [ ] Leverage mechanics
  - [ ] Multi-currency debt
- [ ] Integration tests
  - [ ] Full deposit cycle (with leverage)
  - [ ] Full withdrawal cycle (deleverage)
  - [ ] Rebalance operations (debt refinancing)
  - [ ] Edge cases (liquidation threshold proximity)
- [ ] Fork tests (Aave mainnet fork)

**Related Requirements:**
- FR-002.1: Multi-protocol support
- TR-003: Child strategy interface
- ADR-0008: LeveragedStrategy Architecture

### 2.3 Morpho Leveraged Strategy ⚪
**Dependencies:** 2.1

#### 2.3.1 Morpho Strategy Implementation
- [ ] Create `MorphoLeveragedStrategy.sol`
  - [ ] Inherit LeveragedStrategy
  - [ ] Implement `_supply()` - Morpho.supplyCollateral()
  - [ ] Implement `_withdraw()` - Morpho.withdrawCollateral()
  - [ ] Implement `_borrow()` - Morpho.borrow()
  - [ ] Implement `_repay()` - Morpho.repay()
  - [ ] Implement `_getCollateralValue()` - query Morpho position
  - [ ] Implement `_getDebtValue()` - query Morpho position
  - [ ] Market params handling
- [ ] Strategy-specific state
  - [ ] Morpho contract address
  - [ ] Market parameters

#### 2.3.2 Morpho Strategy Testing
- [ ] Similar test suite to Aave strategy
- [ ] Morpho-specific edge cases
- [ ] Fork tests (Morpho mainnet fork)

**Related Requirements:**
- FR-002.1: Multi-protocol support
- ADR-0008: LeveragedStrategy Architecture

### 2.4 Euler Leveraged Strategy ⚪
**Dependencies:** 2.1

#### 2.4.1 Euler Strategy Implementation
- [ ] Create `EulerLeveragedStrategy.sol`
  - [ ] Inherit LeveragedStrategy
  - [ ] Implement all abstract methods for Euler V2
  - [ ] Euler-specific parameter handling
- [ ] Testing suite

**Related Requirements:**
- FR-002.1: Multi-protocol support

### 2.5 Strategy Configuration & Parameters ⚪
**Dependencies:** 2.2, 2.3

- [ ] Target leverage ratio configuration
- [ ] Liquidation threshold buffer
- [ ] Preferred borrow currencies
- [ ] Rebalancing thresholds
- [ ] Emergency de-leverage triggers

---

## Phase 3: Parent Vault 🔴

### 3.1 Vault Core ⚪
**Dependencies:** 2.2, 1.3

#### 3.1.1 Vault Storage & State
- [ ] Create `ParentVault.sol`
  - [ ] ERC4626 interface implementation
  - [ ] Epoch management
  - [ ] Child strategy registry
  - [ ] Weight management
  - [ ] Share accounting
- [ ] Storage layout optimization

#### 3.1.2 Vault Constructor & Initialization
- [ ] Constructor parameters
  - [ ] Base asset
  - [ ] Oracle address
  - [ ] Initial governance
  - [ ] Initial keeper
- [ ] Post-deployment initialization
- [ ] Child strategy registration

#### 3.1.3 NAV Calculation
- [ ] Implement `totalAssets()` (ADR-0004)
  - [ ] Aggregate child strategies
  - [ ] Include pending deposits
  - [ ] Exclude pending withdrawals
  - [ ] Handle multi-currency debt
- [ ] Implement `convertToShares()` / `convertToAssets()`
- [ ] Share price calculation
- [ ] Tests for NAV edge cases

**Related Requirements:**
- TR-002: NAV calculation
- FR-001.3: Share price calculation

### 3.2 Deposit Flow ⚪
**Dependencies:** 3.1

#### 3.2.1 User Deposit Interface
- [ ] Implement `deposit()` (ERC4626)
- [ ] Implement `mint()` (ERC4626)
- [ ] Implement `requestDeposit()` (epoch-based)
- [ ] Queue management
  - [ ] FIFO deposit queue
  - [ ] Epoch assignment
  - [ ] Deposit cancellation
- [ ] Events (DepositRequested, DepositProcessed, DepositCancelled)

#### 3.2.2 Keeper Deposit Processing
- [ ] Implement `processDeposits()`
  - [ ] Epoch settlement
  - [ ] Share minting
  - [ ] Asset distribution across children
  - [ ] Weight-based allocation
  - [ ] Flash loan for leverage
  - [ ] Multi-child coordination
- [ ] Add `nonReentrant` guard
- [ ] Command-based execution integration
- [ ] Slippage protection
- [ ] Tests for deposit processing

**Related ADRs:** ADR-0005

**Related Requirements:**
- FR-001.1: User deposits
- OR-002.1: Deposit processing

### 3.3 Withdrawal Flow ⚪
**Dependencies:** 3.1

#### 3.3.1 User Withdrawal Interface
- [ ] Implement `withdraw()` (ERC4626)
- [ ] Implement `redeem()` (ERC4626)
- [ ] Implement `requestWithdrawal()` (epoch-based)
- [ ] Queue management
  - [ ] FIFO withdrawal queue
  - [ ] Epoch assignment
  - [ ] Partial fulfillment support
  - [ ] Share burning
- [ ] Events (WithdrawalRequested, WithdrawalProcessed)

#### 3.3.2 Keeper Withdrawal Processing
- [ ] Implement `processWithdrawals()`
  - [ ] Epoch settlement
  - [ ] Share burning
  - [ ] Asset liquidation from children
  - [ ] Pro-rata distribution
  - [ ] Flash loan for de-leverage
  - [ ] Multi-child coordination
- [ ] Add `nonReentrant` guard
- [ ] Tests for withdrawal processing

**Related ADRs:** ADR-0005

**Related Requirements:**
- FR-001.2: User withdrawals
- OR-002.2: Withdrawal processing

### 3.4 Rebalancing System ⚪
**Dependencies:** 3.1, 2.2

#### 3.4.1 Weight Management
- [ ] Implement weight invariants (ADR-0003)
  - [ ] Weight sum = 100%
  - [ ] Min/max weight per child
  - [ ] Weight update mechanism
  - [ ] Gradual weight transitions
- [ ] `setChildWeights()` function
- [ ] `_checkWeightInvariants()` implementation
- [ ] Tests for weight invariants

#### 3.4.2 Rebalancing Operations
- [ ] Implement `rebalance()`
  - [ ] Cross-child rebalancing
  - [ ] Intra-child rebalancing
  - [ ] Weight-based target allocation
  - [ ] Flash loan for liquidity
  - [ ] Multi-step coordination
- [ ] Add `nonReentrant` guard
- [ ] Command-based execution
- [ ] Tests for rebalancing scenarios

**Related ADRs:** ADR-0003

**Related Requirements:**
- TR-005: Rebalancing architecture
- OR-003: Strategy rebalancing

### 3.5 Command System Integration ⚪
**Dependencies:** 3.1, Phase 2 (LeveragedStrategy)

**Note:** Commands are executed by child strategies (see Phase 2). Parent vault prepares command sequences and passes them to children via `data` parameter.

#### 3.5.1 Command Preparation (Parent Level)
- [ ] Off-chain command planning logic
  - [ ] Deposit flow: prepare leverage commands
  - [ ] Withdrawal flow: prepare deleverage commands
  - [ ] Rebalance flow: prepare optimization commands
  - [ ] Command encoding helpers
- [ ] Command sequence validation
  - [ ] Balance checks before/after
  - [ ] Flash loan repayment validation
  - [ ] Slippage parameters

#### 3.5.2 Integration with Child Strategies
- [ ] Parent → Child command passing
  - [ ] Encode Command[] into bytes for deposit()
  - [ ] Encode Command[] into bytes for withdraw()
  - [ ] Encode Command[] into bytes for rebalance()
- [ ] Parent collects assets after child execution
  - [ ] Check expectedToken approval
  - [ ] Transfer expected tokens from child
  - [ ] Verify amounts match expectations
- [ ] Tests for command integration
  - [ ] End-to-end deposit with commands
  - [ ] End-to-end withdrawal with commands
  - [ ] Rebalancing with commands

**Related ADRs:** ADR-0002, ADR-0008

**Related Requirements:**
- FR-003: Command-based execution (implemented in LeveragedStrategy)
- TR-004: Command system implementation
- SR-004: Command system security

### 3.6 Flash Loan Integration ⚪
**Dependencies:** 3.5

#### 3.6.1 Flash Loan Provider Interface
- [ ] Create `IFlashLoanProvider.sol`
- [ ] Morpho integration
- [ ] Balancer V2 integration (fallback)
- [ ] Aave V3 integration (fallback)
- [ ] Provider selection logic

#### 3.6.2 Flash Loan Callback
- [ ] Implement flash loan callback
  - [ ] Debt obligation tracking
  - [ ] Command execution during callback
  - [ ] Repayment guarantee
  - [ ] Fee handling
- [ ] Security checks
- [ ] Tests for flash loan scenarios

**Related Requirements:**
- FR-004: Flash loan management
- TR-006: Flash loan implementation
- SR-003: Flash loan security

---

## Phase 4: Upgradability (MVP) 🔴

### 4.1 Basic UUPS Upgradability ⚪
**Dependencies:** 3.1

#### 4.1.1 UUPS Proxy Pattern (Simplified)
- [ ] Implement UUPS proxy for ParentVault
  - [ ] `_authorizeUpgrade()` with onlyOwner
  - [ ] Storage layout management
  - [ ] Basic upgrade validation
- [ ] Optional: UUPS for child strategies (or redeploy)
- [ ] Upgrade test suite
  - [ ] Storage collision tests
  - [ ] Upgrade continuity tests

**Related ADRs:** ADR-0001

**Related Requirements:**
- TR-001.2: Upgradeable architecture
- SR-006: Upgrade security (simplified)

**Deferred to Post-Launch:**
- [ ] ~~TimelockController for upgrades~~
- [ ] ~~Multi-sig upgrade approval~~
- [ ] ~~Emergency upgrade path~~

### 4.2 Simple Fee Management (MVP) ⚪
**Dependencies:** 4.1

#### 4.2.1 Basic Fees
- [ ] Performance fee (simple percentage)
- [ ] Management fee (annual percentage)
- [ ] Fee collection to owner address
- [ ] Fee parameter updates (onlyOwner)

**Deferred to Post-Launch:**
- [ ] ~~Governance-based parameter updates~~
- [ ] ~~Proposal & voting system~~
- [ ] ~~Complex fee distribution mechanisms~~

---

## Phase 5: Testing & Security 🔴

### 5.1 Comprehensive Testing ⚪
**Dependencies:** All previous phases

#### 5.1.1 Unit Tests
- [ ] ParentVault unit tests (>95% coverage)
- [ ] Child strategies unit tests
- [ ] Helper contracts unit tests
- [ ] Edge cases & boundary conditions

#### 5.1.2 Integration Tests
- [ ] End-to-end flows
  - [ ] Full deposit → rebalance → withdrawal cycle
  - [ ] Multi-user scenarios
  - [ ] Multi-epoch scenarios
  - [ ] Cross-child interactions
- [ ] Flash loan scenarios
- [ ] Emergency scenarios

#### 5.1.3 Fuzz Testing
- [ ] Echidna property tests
  - [ ] Invariant: Share price never decreases (except losses)
  - [ ] Invariant: Total assets = sum of child assets
  - [ ] Invariant: Weight sum = 100%
  - [ ] Invariant: No unauthorized transfers
- [ ] Foundry invariant tests

#### 5.1.4 Fork Testing
- [ ] Mainnet fork tests
  - [ ] Real Pendle markets
  - [ ] Real Aave pools
  - [ ] Real DEX routers
  - [ ] Real price feeds
- [ ] Historical data replay

### 5.2 Security Audit Preparation ⚪
**Dependencies:** 5.1

#### 5.2.1 Documentation
- [ ] Complete NatSpec for all contracts
- [ ] Security considerations document
- [ ] Known limitations document
- [ ] Deployment guide
- [ ] Upgrade procedures

#### 5.2.2 Static Analysis
- [ ] Slither analysis
  - [ ] Fix all high/medium issues
  - [ ] Document false positives
- [ ] Mythril analysis
- [ ] Aderyn analysis

#### 5.2.3 Gas Optimization
- [ ] Gas profiling
- [ ] Optimization implementation
- [ ] Gas benchmarks documentation

**Related Requirements:**
- PR-001: Gas optimization

### 5.3 Formal Verification ⚪
**Dependencies:** 5.1

- [ ] Certora specs for critical invariants
- [ ] Formal verification of key properties

---

## Phase 6: Deployment & Operations 🔴

### 6.1 Deployment Scripts ⚪
**Dependencies:** All previous phases

#### 6.1.1 Testnet Deployment
- [ ] Goerli/Sepolia deployment scripts
  - [ ] Mock oracle deployment
  - [ ] PriceOracle deployment
  - [ ] ParentVault proxy deployment
  - [ ] Child strategies deployment
  - [ ] Configuration & wiring
- [ ] Deployment verification
- [ ] Testnet testing

#### 6.1.2 Mainnet Deployment
- [ ] Mainnet deployment scripts
- [ ] Multi-sig setup
- [ ] Emergency contacts configuration
- [ ] Monitoring setup
- [ ] Deployment checklist

### 6.2 Keeper Backend ⚪
**Dependencies:** 3.2, 3.3, 3.4

#### 6.2.1 Keeper Implementation
- [ ] Typescript/Python keeper service
  - [ ] Deposit processing automation
  - [ ] Withdrawal processing automation
  - [ ] Rebalancing automation
  - [ ] Health monitoring
  - [ ] Gas price optimization
- [ ] Off-chain computation
  - [ ] Optimal swap paths
  - [ ] Slippage calculation
  - [ ] Command batching

**Related Requirements:**
- OR-001: Backend keeper responsibilities
- OR-006: Monitoring and alerting

#### 6.2.2 Risk Management
- [ ] Loss protection monitoring
- [ ] Liquidation risk monitoring
- [ ] Oracle deviation alerts
- [ ] Automatic de-leverage triggers

**Related Requirements:**
- OR-004: Risk management

#### 6.2.3 Profit-Taking
- [ ] Automated profit realization
- [ ] Reinvestment strategies
- [ ] Fee collection

**Related Requirements:**
- OR-005: Profit-taking automation

### 6.3 Monitoring & Alerting ⚪
**Dependencies:** 6.1

#### 6.3.1 On-Chain Monitoring
- [ ] Event indexing (The Graph / Goldsky)
- [ ] Transaction monitoring
- [ ] Contract state monitoring
- [ ] Anomaly detection

#### 6.3.2 Off-Chain Monitoring
- [ ] Keeper uptime monitoring
- [ ] Gas price monitoring
- [ ] Oracle price monitoring
- [ ] Health metrics dashboard

#### 6.3.3 Alerting System
- [ ] Critical alerts (Telegram/Discord/PagerDuty)
  - [ ] Liquidation risk
  - [ ] Oracle failure
  - [ ] Unauthorized access attempts
  - [ ] Emergency pause triggers
- [ ] Warning alerts
  - [ ] High slippage
  - [ ] Rebalancing needed
  - [ ] Keeper delays

**Related Requirements:**
- SR-009: Monitoring and auditing
- OR-006: Monitoring and alerting

### 6.4 Documentation ⚪
**Dependencies:** All previous phases

#### 6.4.1 User Documentation
- [ ] User guide
- [ ] FAQ
- [ ] Risk disclosures
- [ ] Fee structure

#### 6.4.2 Developer Documentation
- [ ] Architecture overview
- [ ] Integration guide
- [ ] API documentation
- [ ] Deployment guide

#### 6.4.3 Operator Documentation
- [ ] Keeper operations manual
- [ ] Emergency procedures
- [ ] Upgrade procedures
- [ ] Troubleshooting guide

---

## Phase 7: Post-Launch (Production Readiness) 🔴

**Note:** This phase starts after successful Friends & Family testnet launch.

### 7.1 Governance Infrastructure ⚪
**Dependencies:** Successful MVP operation

#### 7.1.1 Full RBAC System
- [ ] Multi-role access control
  - [ ] OWNER, KEEPER, GOVERNANCE, EMERGENCY_ADMIN
  - [ ] Role management functions
  - [ ] Multi-sig integration
- [ ] Timelock mechanisms
  - [ ] TimelockController for upgrades
  - [ ] Parameter update delays
  - [ ] Emergency override path

#### 7.1.2 Parameter Governance
- [ ] Parameter registry contract
  - [ ] Fee parameters
  - [ ] Weight bounds
  - [ ] Leverage limits
  - [ ] Slippage tolerances
- [ ] Governance-based updates
- [ ] Proposal & voting (if DAO planned)

### 7.2 Advanced Security ⚪
**Dependencies:** 7.1

- [ ] Circuit breaker enhancements
- [ ] Emergency withdrawal mode
- [ ] Oracle failure handling
- [ ] Flash loan provider redundancy
- [ ] Advanced monitoring & alerts

### 7.3 Public Audit & Mainnet ⚪
**Dependencies:** 7.1, 7.2

#### 7.3.1 Security Audit
- [ ] Select audit firm (Trail of Bits, OpenZeppelin, etc.)
- [ ] Prepare audit materials
- [ ] Implement audit recommendations
- [ ] Re-audit if critical issues found
- [ ] Publish audit report

#### 7.3.2 Mainnet Deployment
- [ ] Mainnet deployment scripts
- [ ] Multi-sig setup (Gnosis Safe)
- [ ] Oracle configuration
- [ ] Initial liquidity provision
- [ ] Monitoring infrastructure
- [ ] Public announcement

### 7.4 Continuous Improvement ⚪
**Dependencies:** 7.3

- [ ] User feedback collection
- [ ] Performance metrics tracking
- [ ] Gas optimization based on real usage
- [ ] New strategy development (Euler, others)
- [ ] Bug bounty program

---

## Critical Path Analysis

**Minimum Viable Product (MVP) Path (Friends & Family Launch):**

1. ✅ **PriceOracle** (Completed)
2. ✅ **SwapHelper** (Completed)
3. ✅ **ADR-0008: LeveragedStrategy Architecture** (Completed)
4. **IChildStrategy Interface** (2.1.1)
5. **LeveragedStrategy Base** (2.1.2)
6. **AaveLeveragedStrategy** (2.2)
7. **MorphoLeveragedStrategy** (2.3)
8. **ParentVault Core** (3.1)
9. **Deposit Flow** (3.2)
10. **Withdrawal Flow** (3.3)
11. **Rebalancing** (3.4)
12. **Command Integration** (3.5)
13. **Flash Loan Integration** (3.6)
14. **Internal Access Control** (1.3 - Ownable + keeper + pause)
15. **Basic UUPS** (4.1 - optional for MVP)
16. **Testing** (5.1)
17. **Testnet Deployment** (6.1)
18. **Keeper Backend** (6.2)

**Deferred to Post-Launch (Production):**
- External governance contracts (TimelockController, voting)
- Multi-role RBAC (separate GOVERNANCE/EMERGENCY roles)
- DAO integration
- Complex fee distribution
- Public audit
- Mainnet deployment

---

## Next Steps

### Phase 2.1: IChildStrategy Interface & LeveragedStrategy Base
1. Create IChildStrategy.sol interface with full documentation
2. Define all function signatures (deposit, withdraw, rebalance, totalAssets)
3. Define events (Deposited, Withdrawn, Rebalanced)
4. Create LeveragedStrategy.sol abstract contract
5. Implement command execution framework (_executeCommands)
6. Define CommandType enum and Command struct
7. Implement abstract methods stubs (_supply, _withdraw, _borrow, _repay, etc.)
8. Integrate SwapHelper inheritance
9. Implement onlyParent access control
10. Write comprehensive tests for base functionality

### Phase 2.2-2.3: Protocol Implementations
1. **Aave**: Implement all abstract methods for Aave V3
2. **Morpho**: Implement all abstract methods for Morpho Blue
3. Add protocol-specific state and configuration
4. Write unit tests for all methods
5. Write integration tests with mainnet forks
6. Test multi-currency debt support

### Phase 1.3 & 3: ParentVault + Access Control
1. **Access Control in ParentVault**:
   - Ownable pattern (owner = hw wallet/multisig)
   - Keeper management (keeper address + onlyKeeper modifier)
   - Pause mechanism (paused state + pause/unpause functions)
2. **ParentVault Core**: ERC4626, epochs, child registry, NAV calculation
3. **Deposit/Withdrawal flows**: User interfaces + keeper processing
4. **Rebalancing**: Weight management + cross-child operations
5. **Command Integration**: Prepare and pass commands to children
6. **Flash Loan Integration**: Morpho/Balancer/Aave providers

This roadmap should be updated as implementation progresses.

**Last Updated:** 2025-01-10