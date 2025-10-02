# ADR-0006: Child Vault Interface

## Status
Accepted

## Date
2024-10-01

## Context
Children are single-owner strategy adapters with synchronous I/O and PnL-based accounting.

## Requirements
- **Single caller:** only parent can deposit/withdraw.
- **Sync operations:** no user queues, no internal epochs.
- **Stable interface:** minimal, consistent across strategies.
- **PnL-based totalAssets:** avoid external oracle spot where possible.
- **Share semantics:** maintain internal shares for proportional math; ERC20 not required.

## Decision

### Solidity Interface

```solidity
interface IChildVault {
    // ============ View Functions ============

    /// @notice Total internal shares (cheap storage read)
    function totalShares() external view returns (uint256);

    /// @notice Current position value (expensive: calls lending protocols, oracles)
    /// @dev Use sparingly - prefer navBefore/navAfter from deposit()
    function totalAssets() external view returns (uint256);

    /// @notice Price per share for analytics/reporting
    /// @return Price scaled to 1e18 (e.g., 1.05e18 = 5% profit)
    function pricePerShare() external view returns (uint256);

    // ============ Mutating Functions (onlyParent) ============

    /// @notice Deposit assets and execute strategy commands
    /// @param assets Amount of underlying to deposit (e.g., USDC)
    /// @param flashLoanRepay Amount to approve parent for flash loan repayment
    /// @param commands ABI-encoded command sequence (ADR-0002)
    /// @return shares Minted shares based on deltaNAV
    /// @return navBefore Total assets before executing commands
    /// @return navAfter Total assets after executing commands
    /// @dev Parent uses navBefore/navAfter to avoid recalculating totalAssets
    function deposit(uint256 assets, uint256 flashLoanRepay, bytes calldata commands)
        external
        returns (uint256 shares, uint256 navBefore, uint256 navAfter);

    /// @notice Withdraw assets by burning shares (proportional unwind)
    /// @param shares Amount of shares to burn
    /// @param flashLoanRepay Amount to approve parent for flash loan repayment
    /// @param params Strategy-specific parameters (e.g., swap routes, flash loan providers)
    /// @return assets Actual assets returned to parent
    /// @dev Uses FIXED proportional logic defined by strategy, NOT arbitrary commands
    function withdraw(uint256 shares, uint256 flashLoanRepay, bytes calldata params)
        external
        returns (uint256 assets);

    /// @notice Execute internal rebalancing operations
    /// @param flashLoanRepay Amount to approve parent for flash loan repayment
    /// @param commands ABI-encoded command sequence (ADR-0002)
    /// @dev Uses arbitrary commands with NAV invariant checks
    function rebalance(uint256 flashLoanRepay, bytes calldata commands) external;
}
```

### Share Minting Logic (deltaNAV method)

Child vaults use the **same deltaNAV approach as parent** (ADR-0004, ADR-0005):

```solidity
function deposit(uint256 assets, uint256 flashLoanRepay, bytes calldata commands)
    external
    onlyParent
    returns (uint256 shares, uint256 navBefore, uint256 navAfter)
{
    // 1. Snapshot NAV before deploying capital
    navBefore = _calculateTotalAssets(); // expensive call

    // 2. Execute strategy commands (e.g., Swap -> Deposit -> Borrow)
    _executeCommands(commands);

    // 3. Snapshot NAV after deploying capital
    navAfter = _calculateTotalAssets(); // expensive call

    // 4. Mint shares from deltaNAV
    uint256 deltaNAV = navAfter - navBefore;

    if (totalShares == 0) {
        // First deposit: mint shares at 1e18 scale
        // shares = deltaNAV * 1e18 / (10 ** underlyingDecimals)
        // Example: deltaNAV = 1000 USDC (1000e6) → shares = 1000e6 * 1e18 / 1e6 = 1000e18
        shares = (deltaNAV * 1e18) / (10 ** underlyingDecimals);
    } else {
        // shares = deltaNAV / pricePerShare
        // pricePerShare = navBefore / totalShares
        shares = (deltaNAV * totalShares) / navBefore;
    }

    totalShares += shares;

    // 5. Approve parent to collect flash loan repayment
    underlyingToken.approve(parent, flashLoanRepay);

    emit ChildDeposit(assets, navBefore, navAfter, shares);
    return (shares, navBefore, navAfter);
}
```

### Withdrawal Logic (fixed proportional unwind)

**Security Design:** Withdrawal uses **fixed on-chain logic** to ensure proportional unwind and prevent keeper manipulation.

```solidity
function withdraw(uint256 shares, uint256 flashLoanRepay, bytes calldata params)
    external
    onlyParent
    returns (uint256 assets)
{
    // FIXED: proportional calculation controlled on-chain
    // FIXED: unwind sequence defined by strategy implementation
    // Keeper can only provide execution parameters (swap routes, etc.)
    // that cannot be computed on-chain

    // 1. Calculate proportional amounts (on-chain, fixed logic)
    uint256 collateralToWithdraw = (totalCollateral * shares) / totalShares;
    uint256 debtToRepay = (totalDebt * shares) / totalShares;

    // 2. Repay debt using flash loan (received via transfer from parent)
    _repayDebt(debtToRepay);  // uses flashLoanRepay tokens

    // 3. Withdraw collateral (now possible since debt is reduced)
    _withdrawCollateral(collateralToWithdraw);  // get PT tokens

    // 4. Swap collateral to underlying (using params for route)
    uint256 swapOut = _swap(collateralToWithdraw, params);  // PT → USDC

    // 5. Calculate net assets for user
    // assets = everything received from swap - flash loan to be repaid
    assets = swapOut - flashLoanRepay;

    totalShares -= shares;

    // 6. Approve parent to collect flash loan repayment + withdrawn assets
    underlyingToken.approve(parent, flashLoanRepay + assets);

    emit ChildWithdraw(shares, assets);
    return assets;
}
```

**Example withdrawal flow:**

Initial state:
- Total collateral: 3000 PT tokens
- Total debt: 2000 USDC
- Total shares: 1000

Withdrawing 100 shares (10%):
```
1. Calculate proportional amounts:
   collateralToWithdraw = 3000 * 100/1000 = 300 PT
   debtToRepay = 2000 * 100/1000 = 200 USDC

2. Parent sends flashLoanRepay = 200 USDC (via transfer)

3. Repay debt: 200 USDC (child balance now 0 USDC)

4. Withdraw collateral: 300 PT (child balance now 300 PT)

5. Swap: 300 PT → 310 USDC (price includes PT premium/discount)

6. Calculate assets: 310 - 200 = 110 USDC

7. Approve parent: 200 + 110 = 310 USDC total
   - 200 USDC returns to parent for flash loan repayment
   - 110 USDC goes to user as withdrawn assets
```

**Key insight:** `swapOut` can be greater than the proportional value due to PT trading at premium/discount. The formula `assets = swapOut - flashLoanRepay` ensures users get the actual realized value, not theoretical NAV.

### Multi-Currency Debt Support

Child vaults can hold debt denominated in **different stablecoins** than the base token to optimize borrow rates.

**Example:** Base token = USDC, Debt = USDT

**Deposit flow with USDT debt:**
```solidity
commands = [
  { op: Swap, data: encode(1500 USDC → 1500 PT) },
  { op: LendingDeposit, data: encode(PT, 1500) },
  { op: LendingBorrow, data: encode(USDT, 1002) },  // borrow USDT instead of USDC
  { op: Swap, data: encode(1002 USDT → 1001 USDC) }, // convert to base for flash loan repay
]

Result: 1500 PT collateral, 1002 USDT debt, ~1 USDC dust
```

**Withdrawal flow with USDT debt:**
```solidity
// Proportional calculations:
collateralToWithdraw = 150 PT (10%)
debtToRepay = 100.2 USDT (10% of 1002 USDT)

// Parent sends flashLoan in USDC, child converts:
1. Swap 101.2 USDC → 101 USDT (with buffer for slippage)
2. Repay 100.2 USDT debt (0.8 USDT dust remains)
3. Withdraw 150 PT collateral
4. Swap 150 PT → 155 USDC
5. assets = 155 - 101.2 = 53.8 USDC
```

**NAV calculation with multi-currency debt:**
```solidity
function _calculateTotalAssets() returns (uint256) {
    // Collateral value (in base token terms)
    uint256 collateralValue = pendleOracle.getPtToAssetRate(market) * collateralAmount;

    // Debt value (convert to base token using oracle)
    uint256 debtValue = oracle.convert(debtAmount, debtToken, baseToken);

    // Dust (ignored if < threshold, e.g., 10 USDC)
    uint256 cash = dustAmount < DUST_THRESHOLD ? 0 : dustAmount;

    return collateralValue - debtValue + cash;
}
```

**Design decisions:**

1. **Separate strategies for different debt currencies:**
   - Child A: USDC debt (Morpho)
   - Child B: USDT debt (Aave)
   - Child C: DAI debt (Compound)
   - Rebalancing between them = migration flow (withdraw from A, deposit to B)

2. **Keeper responsibilities:**
   - Calculate exact borrow amounts off-chain
   - Include sufficient buffer for slippage
   - Monitor debt accrual and update calculations

3. **Dust management:**
   - Ignored in NAV if below threshold (e.g., 10 USDC equivalent)
   - Cleaned up during rebalance operations
   - Can swap dust → base token or → yield-bearing token
   - Max dust per child: 50 USDC equivalent (governance parameter)

4. **Oracle requirements:**
   - Chainlink price feeds for stablecoin pairs (USDT/USD, USDC/USD, DAI/USD)
   - Staleness check: max 1 hour
   - Deviation threshold: ±2% (revert if exceeded)

5. **Benefits:**
   - 1-2% difference in borrow rates → 5-10% difference in equity returns (with 5x leverage)
   - Access to deeper liquidity markets
   - Flexibility when specific stablecoin markets are unavailable

**Key security properties:**
- ✅ Proportional amounts calculated **on-chain** (keeper cannot manipulate)
- ✅ Unwind sequence is **fixed by strategy implementation**
- ✅ Keeper only provides **off-chain parameters** (e.g., swap routes, flash loan providers)
- ✅ No arbitrary commands allowed (unlike deposit/rebalance)
- ✅ No expensive `totalAssets()` calls needed

### Gas Optimization

**Deposit epoch (2 children):**
- Each child: 2 calls to `_calculateTotalAssets()` (pre/post)
- Parent: 0 additional calls (uses returned navBefore/navAfter)
- **Total: 4 expensive calls** (minimum necessary)

**Withdraw epoch:**
- Parent: proportional withdrawal by shares
- Children: execute commands, no NAV calculation
- **Total: 0 expensive calls** 🎉

### Share Scale Normalization

**All child vault shares are normalized to 1e18 scale** regardless of underlying token decimals:

- **First deposit:** `shares = (deltaNAV * 1e18) / (10 ** underlyingDecimals)`
  - USDC (6 decimals): 1000 USDC (1000e6) → 1000e18 shares
  - DAI (18 decimals): 1000 DAI (1000e18) → 1000e18 shares
  - WBTC (8 decimals): 1 WBTC (1e8) → 1e18 shares

- **Subsequent deposits:** `shares = (deltaNAV * totalShares) / navBefore`
  - Naturally maintains 1e18 scale since totalShares is already 1e18 scaled

- **Benefits:**
  - Consistent `pricePerShare` calculation across all tokens
  - Avoids precision loss for low-decimal tokens
  - Simplifies cross-child accounting in parent vault
  - Compatible with ERC4626 standard (if needed in future)

### Rounding
- Round down on share minting to avoid over-issuance
- Round down on asset withdrawal to protect vault

### Rebalance Operations (arbitrary commands with invariants)

Child vaults may implement a `rebalance()` function for keeper-initiated optimizations:

```solidity
function rebalance(uint256 flashLoanRepay, bytes calldata commands) external onlyParent {
    uint256 navBefore = _calculateTotalAssets();

    // Execute arbitrary commands (ADR-0002)
    // Examples: refinance debt, adjust leverage, migrate protocols, compound rewards
    _executeCommands(commands);

    uint256 navAfter = _calculateTotalAssets();

    // INVARIANT: NAV should not decrease significantly
    require(navAfter >= navBefore * 99 / 100, "NAV decreased");

    // Approve parent to collect flash loan repayment
    underlyingToken.approve(parent, flashLoanRepay);
}
```

**Use cases:** refinance debt, adjust leverage, migrate protocols, compound rewards.

## Summary: Command Usage by Operation

| Operation | Commands Type | Security Model |
|-----------|---------------|----------------|
| **Deposit** | Arbitrary (ADR-0002) | deltaNAV accounting prevents dilution |
| **Withdraw** | **FIXED logic** | Proportional calculation on-chain |
| **Rebalance** | Arbitrary (ADR-0002) | NAV invariant checks |

## Consequences
- Easy integration of heterogeneous strategies
- Parent can perform accurate proportional exits across children
- Withdrawal security through fixed proportional logic (no keeper manipulation possible)
- Flexibility for deposits and rebalancing with proper invariant checks

## Related ADRs
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Defines parent-child relationship and multi-child allocation
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - totalAssets contributes to parent NAV
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Data parameter may contain command sequences
