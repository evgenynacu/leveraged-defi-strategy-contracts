# Implementation Roadmap

Дерево задач для завершения проекта leveraged DeFi strategy contracts.

**Legend:**
- ✅ Completed
- 🟡 In Progress
- ⚪ Not Started
- 🔴 Blocked

---

## Phase 1: Core Infrastructure (Foundation) ✅

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

### 1.3 Architecture Documentation ✅
- [x] ADR-0001: Upgradeable Contract Architecture
- [x] ADR-0002: Command-Based Execution (updated for inheritance pattern)
- [x] ADR-0003: Vault Architecture v2 (updated for manual strategy selection)
- [x] ADR-0004: NAV Calculation Method
- [x] ADR-0005: Deposit & Withdrawal Settlement (updated for manual allocation)
- [x] ADR-0006: Child Vault Interface (updated for flash loan pattern)
- [x] ADR-0007: Reentrancy Protection Strategy
- [x] ADR-0008: LeveragedStrategy Architecture
- [x] ADR-0009: Selective Withdrawal with Tolerance-Based Validation
- [x] Updated all requirements documents (FR, TR, SR, OR) for manual mode
- [x] Updated TODO.md to remove obsolete weight invariant tasks

**Note:** All core architectural decisions documented. Implementation tracked in subsequent phases.

### 1.4 Access Control (MVP) ⚪
**Dependencies:** Phase 2 completion

**Note:** Internal access control for vault/strategies will be implemented in MVP. External governance contracts deferred to post-launch.

#### 1.4.1 Internal Access Control (MVP)
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

#### 1.4.2 Deferred to Post-Launch (External Governance)
- [ ] ~~TimelockController contract~~
- [ ] ~~Governance token & voting~~
- [ ] ~~Multi-role RBAC (separate GOVERNANCE/EMERGENCY roles)~~
- [ ] ~~DAO integration~~

**Related Requirements:**
- SR-001: Access Control (internal implementation)

---

## Phase 2: Child Strategies (Inheritance-Based) 🟡

### 2.1 Base Leveraged Strategy ✅
**Dependencies:** 1.2 (SwapHelper completed)

#### 2.1.1 IChildStrategy Interface
- [x] Create `IChildStrategy.sol`
  - [x] `deposit()` function signature (multi-token support)
  - [x] `withdraw()` function signature (proportional exit)
  - [x] `rebalance()` function signature (internal optimization)
  - [x] `totalAssets()` view function
  - [x] Events (Deposited, Withdrawn, Rebalanced)
- [x] Comprehensive NatSpec documentation

**Related ADRs:** ADR-0006, ADR-0008

#### 2.1.2 LeveragedStrategy Abstract Contract
- [x] Create `LeveragedStrategy.sol`
  - [x] Inherit from SwapHelper and IChildStrategy
  - [x] Command execution framework (`_executeCommands`)
  - [x] CommandType enum (SUPPLY, WITHDRAW, BORROW, REPAY, SWAP)
  - [x] Command struct (cmdType, data)
  - [x] `onlyParent` access control
  - [x] Oracle integration (inherited from SwapHelper)
  - [x] Abstract methods for protocol-specific operations
    - [x] `_supply()` - supply collateral
    - [x] `_withdraw()` - withdraw collateral
    - [x] `_borrow()` - borrow assets
    - [x] `_repay()` - repay debt
    - [x] `_getCollateralAsset()` / `_getCollateralAmount()`
    - [x] `_getDebtAsset()` / `_getDebtAmount()`
  - [x] Idle balance snapshot & proportional-withdraw safeguards
  - [x] Event emission helpers
- [x] Tests for base functionality
  - [x] Command parsing
  - [x] Access control (`onlyParent`)
  - [x] Approval and idle balance validation

**Related ADRs:** ADR-0008, ADR-0002, ADR-0007

### 2.2 Aave Leveraged Strategy ✅
**Dependencies:** 2.1

#### 2.2.1 Aave Strategy Implementation
- [x] Create `AaveLeveragedStrategy.sol`
  - [x] Inherit LeveragedStrategy
  - [x] Implement `_supply()` - Aave Pool.supply()
  - [x] Implement `_withdraw()` - Aave Pool.withdraw()
  - [x] Implement `_borrow()` - Aave Pool.borrow() with variable rate
  - [x] Implement `_repay()` - Aave Pool.repay()
  - [x] Implement `_getCollateralAsset()` / `_getDebtAsset()` - single asset accessors
  - [x] Implement `_getPositionAmounts()` - query Aave PoolDataProvider
  - [x] Implement `_calculateSafeWithdrawAmounts()` - Aave-specific health factor logic
  - [x] Single collateral + single debt asset support
- [x] Strategy-specific state
  - [x] Aave Pool address (immutable)
  - [x] Collateral asset address (immutable)
  - [x] Debt asset address (immutable)
  - [x] On-demand approval system (_approveIfNeeded)

#### 2.2.2 Aave Strategy Testing
- [x] Unit tests (471 lines)
  - [x] All abstract method implementations
  - [x] Command sequence execution
  - [x] Leverage mechanics
  - [x] Position querying via PoolDataProvider
- [x] Mock-based integration tests
  - [x] Full deposit cycle (with leverage)
  - [x] Full withdrawal cycle (deleverage)
  - [x] Rebalance operations
  - [x] Edge cases validation
- [ ] Fork tests (Aave mainnet fork) - Deferred

**Related Requirements:**
- FR-002.1: Multi-protocol support
- TR-003: Child strategy interface
- ADR-0008: LeveragedStrategy Architecture

### 2.3 Morpho Leveraged Strategy ✅
**Dependencies:** 2.1

#### 2.3.1 Morpho Strategy Implementation
- [x] Create `MorphoLeveragedStrategy.sol`
  - [x] Inherit LeveragedStrategy
  - [x] Implement `_supply()` - Morpho.supplyCollateral()
  - [x] Implement `_withdraw()` - Morpho.withdrawCollateral()
  - [x] Implement `_borrow()` - Morpho.borrow()
  - [x] Implement `_repay()` - Morpho.repay()
  - [x] Implement `_getCollateralAsset()` / `_getDebtAsset()` - single asset accessors
  - [x] Implement `_getPositionAmounts()` - query Morpho position with share-to-asset conversion
  - [x] Implement `_calculateSafeWithdrawAmounts()` - Morpho-specific health factor logic
  - [x] Market ID-based market identification
  - [x] Share-based debt accounting (similar to Aave V3)
- [x] Strategy-specific state
  - [x] Morpho Blue contract address (immutable)
  - [x] Market ID (immutable)
  - [x] Collateral asset address (immutable, extracted from market params)
  - [x] Debt asset address (immutable, extracted from market params)
  - [x] On-demand approval system (_approveIfNeeded)

#### 2.3.2 Morpho Strategy Testing
- [x] Unit tests (17 tests, all passing)
  - [x] All abstract method implementations
  - [x] Command sequence execution
  - [x] Leverage mechanics
  - [x] Position querying with share-to-asset conversion
  - [x] Share-based debt accounting
- [x] Mock-based integration tests
  - [x] Full deposit cycle (with leverage)
  - [x] Full withdrawal cycle (deleverage)
  - [x] Edge cases validation
- [ ] Fork tests (Morpho mainnet fork) - Deferred

**Related Requirements:**
- FR-002.1: Multi-protocol support
- ADR-0008: LeveragedStrategy Architecture

### 2.4 Euler Leveraged Strategy ✅
**Dependencies:** 2.1

#### 2.4.1 Euler Strategy Implementation
- [x] Create `EulerLeveragedStrategy.sol`
  - [x] Inherit LeveragedStrategy
  - [x] Implement `_supply()` - EVault.deposit()
  - [x] Implement `_withdraw()` - EVault.withdraw() via EVC
  - [x] Implement `_borrow()` - EVault.borrow() via EVC
  - [x] Implement `_repay()` - EVault.repay() via EVC
  - [x] Implement `_getCollateralAsset()` / `_getDebtAsset()` - single asset accessors
  - [x] Implement `_getPositionAmounts()` - query vault with share-to-asset conversion
  - [x] Implement `_calculateSafeWithdrawAmounts()` - Euler-specific health factor logic
  - [x] EVC (Ethereum Vault Connector) integration
  - [x] Share-based accounting for both collateral and debt
- [x] Strategy-specific state
  - [x] EVC contract address (immutable)
  - [x] Collateral vault address (immutable)
  - [x] Debt vault address (immutable)
  - [x] Collateral asset address (immutable, extracted from vault)
  - [x] Debt asset address (immutable, extracted from vault)
  - [x] On-demand approval system (_approveIfNeeded)

#### 2.4.2 Euler Strategy Testing
- [x] Unit tests (18 tests, all passing)
  - [x] All abstract method implementations
  - [x] Command sequence execution
  - [x] Leverage mechanics via EVC
  - [x] Position querying with share-to-asset conversion
  - [x] Share-based accounting for collateral and debt
- [x] Mock-based integration tests
  - [x] Full deposit cycle (with leverage)
  - [x] Full withdrawal cycle (deleverage)
  - [x] EVC call delegation
  - [x] Edge cases validation
- [ ] Fork tests (Euler mainnet fork) - Deferred

**Related Requirements:**
- FR-002.1: Multi-protocol support
- ADR-0008: LeveragedStrategy Architecture

### 2.5 Strategy Configuration & Parameters ⚪
**Dependencies:** 2.2, 2.3, 2.4

- [ ] Target leverage ratio configuration
- [ ] Liquidation threshold buffer
- [ ] Preferred borrow currencies
- [ ] Rebalancing thresholds
- [ ] Emergency de-leverage triggers

---

## Phase 3: Parent Vault 🔴

### 3.1 Vault Core ⚪
**Dependencies:** 2.2, 1.4

#### 3.1.1 Vault Storage & State
- [ ] Create `ParentVault.sol`
  - [ ] ERC4626 interface implementation
  - [ ] Epoch management
  - [ ] Child strategy registry
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
  - [ ] Asset distribution to selected children (manual strategy selection)
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

#### 3.4.1 Allocation Monitoring (View Functions)
- [ ] View functions for current allocations
  - [ ] Per-child NAV calculation
  - [ ] Per-child allocation percentage
  - [ ] Total portfolio NAV
  - [ ] Helper functions for manager decision-making
- [ ] Tests for allocation view functions

#### 3.4.2 Rebalancing Operations (Manual Mode)
- [ ] Implement `rebalance()` (manager-initiated)
  - [ ] Cross-child rebalancing (manual strategy selection)
  - [ ] Intra-child rebalancing (optimization)
  - [ ] Flash loan for liquidity
  - [ ] Multi-step coordination
  - [ ] NAV invariant checks (no weight invariants)
- [ ] Add `nonReentrant` guard
- [ ] Command-based execution
- [ ] Tests for rebalancing scenarios
- [ ] Keeper automation for delayed rebalancing when protocol caps lift

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
  - [ ] Deposit processing execution (manager selects strategies)
  - [ ] Withdrawal processing execution (manager selects strategies)
  - [ ] Stop-loss automation (keeper-controlled)
  - [ ] Take-profit automation (keeper-controlled)
  - [ ] Delayed rebalancing automation (execute when protocol caps lift)
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
  - [ ] Leverage limits
  - [ ] Slippage tolerances
  - [ ] Stop-loss/take-profit thresholds
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

1. ✅ **PriceOracle** (Completed - Phase 1.1)
2. ✅ **SwapHelper** (Completed - Phase 1.2)
3. ✅ **Architecture Documentation** (Completed - Phase 1.3)
4. ✅ **IChildStrategy Interface** (Completed - Phase 2.1.1)
5. ✅ **LeveragedStrategy Base** (Completed - Phase 2.1.2)
6. ✅ **AaveLeveragedStrategy** (Completed - Phase 2.2)
7. ✅ **MorphoLeveragedStrategy** (Completed - Phase 2.3)
8. ✅ **EulerLeveragedStrategy** (Completed - Phase 2.4)
9. **ParentVault Core** (Phase 3.1)
9. **Deposit Flow** (Phase 3.2)
10. **Withdrawal Flow** (Phase 3.3)
11. **Rebalancing** (Phase 3.4 - Manual mode)
12. **Command Integration** (Phase 3.5)
13. **Flash Loan Integration** (Phase 3.6)
14. **Internal Access Control** (Phase 1.4 - Ownable + keeper + pause)
15. **Basic UUPS** (Phase 4.1 - optional for MVP)
16. **Testing** (Phase 5.1)
17. **Testnet Deployment** (Phase 6.1)
18. **Keeper Backend** (Phase 6.2 - with stop-loss/take-profit)

**Deferred to Post-Launch (Production):**
- External governance contracts (TimelockController, voting)
- Multi-role RBAC (separate GOVERNANCE/EMERGENCY roles)
- DAO integration
- Complex fee distribution
- Public audit
- Mainnet deployment

---

## Next Steps

### Current Focus: Phase 3.1 - ParentVault Core Implementation
**Next Steps:**
1. Create `ParentVault.sol` contract with ERC4626 interface
2. Implement epoch management system
3. Implement child strategy registry
4. Implement NAV calculation (totalAssets)
5. Add share accounting logic
6. Write comprehensive unit tests

### Phase 1.4 & 3: ParentVault + Access Control
1. **Access Control in ParentVault**:
   - Ownable pattern (owner = hw wallet/multisig)
   - Keeper management (keeper address + onlyKeeper modifier)
   - Pause mechanism (paused state + pause/unpause functions)
2. **ParentVault Core**: ERC4626, epochs, child registry, NAV calculation
3. **Deposit/Withdrawal flows**: User interfaces + keeper processing (manual strategy selection)
4. **Rebalancing**: Manual strategy selection + allocation monitoring view functions
5. **Command Integration**: Prepare and pass commands to children
6. **Flash Loan Integration**: Morpho/Balancer/Aave providers

## Recent Updates

### 2025-01-27: Euler V2 Strategy Completed
- **Completed EulerLeveragedStrategy**: Full implementation with EVC integration
- **EVC (Ethereum Vault Connector)**: All borrow/repay/withdraw operations go through EVC
- **Share-based accounting**: Both collateral and debt use share-to-asset conversion
- **Comprehensive tests**: 18 unit tests covering all functionality
- **MockEVault and MockEVC**: Created for testing without mainnet fork
- **All 148 tests passing**: Aave (14), Morpho (17), Euler (18), LeveragedStrategy (53), PriceOracle (31), SwapHelper (15)

### 2025-01-27: Morpho Blue Strategy Completed
- **Completed MorphoLeveragedStrategy**: Full implementation with share-based debt accounting
- **Market ID-based identification**: Uses Morpho Blue's market ID system
- **Share-to-asset conversion**: Proper handling of borrow shares to assets conversion
- **Comprehensive tests**: 17 unit tests covering all functionality
- **MockMorpho contract**: Created for testing without mainnet fork
- **Updated initializer pattern**: Modified base contracts to support both direct deployment and upgradeable proxy pattern

### 2025-01-24: Architecture Changes - Manual Strategy Management
- **Removed automatic weight-based allocation**: Parent vault no longer enforces target weights or automatic distribution
- **Manual strategy selection**: Manager explicitly selects which child strategy for each deposit/withdrawal
- **Keeper responsibilities updated**:
  - Execute manager-selected strategies for deposits/withdrawals
  - Automated stop-loss execution when NAV drops below thresholds
  - Automated take-profit execution when profit targets reached
  - Delayed rebalancing automation (execute when protocol caps lift)
- **Documentation updated**: All ADRs, requirements, and roadmap reflect manual mode
- **Phase 2.2 Completed**: AaveLeveragedStrategy fully implemented with 471 lines of tests

### Progress Summary
- **Phase 1: Core Infrastructure** ✅ - Fully completed
- **Phase 2: Child Strategies** ✅ - All three protocols completed (Aave, Morpho, Euler)
- **Phase 3: Parent Vault** 🔴 - Not started
- **Next milestone**: ParentVault core implementation (Phase 3.1)

This roadmap should be updated as implementation progresses.

**Last Updated:** 2025-01-27
