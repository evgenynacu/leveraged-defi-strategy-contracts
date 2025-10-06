# Technical Requirements

## Overview
Technical requirements for the leveraged DeFi strategy system including architecture, upgradeability, and implementation constraints.

## TR-001: Contract Architecture

### TR-001.1: Upgradeable Components
- Parent vault logic must be upgradeable using OpenZeppelin transparent proxy pattern
- Child vault logic must be upgradeable independently
- Proxy contracts must be immutable
- Storage layout must support append-only changes (cannot reorder or remove variables)

### TR-001.2: Governance Structure
- System must support flexible governance evolution
- Initial deployment may use simple multisig
- Migration to full on-chain governance must be possible without architecture changes
- Upgrade authority and governance mechanisms to be implemented using OpenZeppelin Governor and TimelockController

## TR-002: NAV Calculation

### TR-002.1: Component-Based NAV
- NAV must be sum of well-defined components:
  - Cash balances (stablecoins at 1:1)
  - Collateral assets (protocol-specific pricing)
  - Debt obligations (with accrued interest)
  - Realizable rewards (only if realizable within current epoch)

### TR-002.2: Oracle Integration
- PT tokens must use Pendle Oracle with period=0 for spot pricing
- Yield-bearing assets must use external oracles
- Stablecoins must use external oracles for depeg detection
- Fixed-point math with 1e18 scale and explicit rounding rules
- Deterministic snapshots: NAV_before and NAV_after within one transaction

### TR-002.3: Entry and Exit Rules
- Entry: shares minted from deltaNAV only (`shares = deltaNAV / pricePerShare`)
- NAV_before excludes queued deposit assets (haven't entered strategies yet)
- NAV_after includes newly deployed assets in child strategies
- First deposit: `pricePerShare = 1e18` (1:1 ratio)
- Exit: pay realized asset units proportionally, not by NAV estimate

## TR-003: Child Strategy Interface

### TR-003.1: Core Interface Requirements
- Single caller restriction: only parent can call operations
- Synchronous operations: no user queues, no internal epochs
- Multi-token support: accept any token for deposit/withdraw, not just base asset
- No internal shares: parent owns all assets directly, no share minting in child

### TR-003.2: Function Signatures
```solidity
interface IChildStrategy {
    function deposit(
        address depositToken, uint256 depositAmount,
        address providedToken, uint256 providedAmount,
        address expectedToken, uint256 expectedAmount,
        bytes calldata data
    ) external;

    function withdraw(
        uint256 percentage,
        address outputToken,
        address providedToken, uint256 providedAmount,
        address expectedToken, uint256 expectedAmount,
        bytes calldata data
    ) external returns (uint256 actualWithdrawn);

    function rebalance(
        address providedToken, uint256 providedAmount,
        address expectedToken, uint256 expectedAmount,
        bytes calldata data
    ) external;

    function totalAssets() external view returns (uint256);
}
```

### TR-003.3: Proportional Exit Logic
- Withdrawal operations must use fixed proportional logic
- Calculate proportional amounts based on percentage parameter
- Execute proportional unwind using provided liquidity
- Approve parent to collect withdrawn assets and expected tokens

## TR-004: Command System Implementation

### TR-004.1: Data Structures
```solidity
enum Op { FlashLoan, LendingDeposit, LendingWithdraw, LendingBorrow, LendingRepay, Swap }
struct Cmd {
    Op op;
    bytes data; // ABI-encoded arguments for this operation
}
```

### TR-004.2: Security Constraints
- Transfer operation is NOT allowed in commands
- All assets must remain within vault contracts
- Transfers only executed by vault logic itself, never by keeper-provided commands
- Command validation for known attack patterns
- Reentrancy protection for command execution
- Slippage limits and deadlines for all swaps

### TR-004.3: Invariants
After executing any command sequence:
- All borrowed flash loan funds must be repaid
- All intermediate tokens must be converted to strategy assets
- No tokens should be sent to external addresses
- Vault's position must be internally consistent (collateral/debt ratios valid)

## TR-005: Rebalancing Architecture

### TR-005.1: Unified Rebalancing System
```solidity
enum RebalanceOp { Withdraw, Deposit, Internal }
struct RebalanceStep {
    uint256 childIndex;
    RebalanceOp operation;
    bytes data;
}
```

### TR-005.2: Rebalancing Function
- Single `rebalance()` function handles all rebalancing operations
- Step-based approach for flexible composition
- Single flash loan for entire rebalance sequence
- NAV invariant checks (NAV should not decrease significantly)
- Weight invariant checks after rebalance completion

## TR-006: Flash Loan Implementation

### TR-006.1: Flash Loan Provider
- Primary provider: Morpho (zero fee flash loans)
- Parent vault manages all flash loans
- Single flash loan for complex operations across children
- Support for different operation types through callback data

### TR-006.2: Operation Types
```solidity
enum OperationType {
    DEPOSIT,    // processDeposits - user deposits to children
    WITHDRAW,   // processWithdrawals - user withdrawals from children
    REBALANCE   // rebalance - move assets between children or optimize within single child
}
```

## TR-007: Error Handling and Atomicity

### TR-007.1: Atomic Execution
- All operations in `processDeposits()` must be atomic
- If any child deposit/withdrawal fails → entire epoch reverts
- No partial state changes allowed
- Keeper can retry with adjusted parameters

### TR-007.2: Idempotency
- Safe re-runs on transaction failure
- State should be consistent after failed transactions
- Clear separation between pending and processed states

## TR-008: Strategy Implementation Requirements

### TR-008.1: Leveraged Yield-Token Strategy Architecture
- Child strategies must implement leveraged yield-token acquisition pattern:
  ```
  1. Receive base token (USDC) + flash loan liquidity
  2. Swap total amount to yield-bearing token using optimal DEX routing
  3. Deposit yield token as collateral to lending protocol
  4. Borrow base token against collateral (creating leverage)
  5. Repay flash loan from borrowed amount
  ```
- Withdrawal must implement proportional deleveraging:
  ```
  1. Receive flash loan for debt repayment
  2. Repay proportional amount of debt
  3. Withdraw proportional collateral from lending protocol
  4. Swap yield token to base token
  5. Repay flash loan and return remaining to parent
  ```

### TR-008.2: Protocol Integration Requirements
- **Pendle Integration**: Must support PT token trading through PendleRouter
- **Odos Integration**: Must support swap execution through Odos API/contracts
- **KyberSwap Integration**: Must support MetaAggregationRouter for optimal routing
- **Aave Integration**: Must support supply/borrow/repay/withdraw through Pool interface
- **Morpho Integration**: Must support supply/borrow/repay/withdraw through MorphoBlue interface
- **Euler Integration**: Must support supply/borrow/repay/withdraw through EulerV2 interfaces (EVC and EVault)
