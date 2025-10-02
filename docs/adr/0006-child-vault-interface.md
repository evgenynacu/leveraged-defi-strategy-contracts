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
    /// @param commands ABI-encoded command sequence (ADR-0002)
    /// @return shares Minted shares based on deltaNAV
    /// @return navBefore Total assets before executing commands
    /// @return navAfter Total assets after executing commands
    /// @dev Parent uses navBefore/navAfter to avoid recalculating totalAssets
    function deposit(uint256 assets, bytes calldata commands)
        external
        returns (uint256 shares, uint256 navBefore, uint256 navAfter);

    /// @notice Withdraw assets by burning shares (proportional unwind)
    /// @param shares Amount of shares to burn
    /// @param params Strategy-specific parameters (e.g., swap routes, flash loan providers)
    /// @return assets Actual assets returned to parent
    /// @dev Uses FIXED proportional logic defined by strategy, NOT arbitrary commands
    function withdraw(uint256 shares, bytes calldata params)
        external
        returns (uint256 assets);
}
```

### Share Minting Logic (deltaNAV method)

Child vaults use the **same deltaNAV approach as parent** (ADR-0004, ADR-0005):

```solidity
function deposit(uint256 assets, bytes calldata commands)
    external
    onlyParent
    returns (uint256 shares, uint256 navBefore, uint256 navAfter)
{
    // 1. Snapshot NAV before deploying capital
    navBefore = _calculateTotalAssets(); // expensive call

    // 2. Execute strategy commands (e.g., FlashLoan -> Swap -> Deposit -> Borrow -> Repay)
    _executeCommands(commands);

    // 3. Snapshot NAV after deploying capital
    navAfter = _calculateTotalAssets(); // expensive call

    // 4. Mint shares from deltaNAV
    uint256 deltaNAV = navAfter - navBefore;

    if (totalShares == 0) {
        shares = assets; // first deposit: 1:1 ratio
    } else {
        // shares = deltaNAV / pricePerShare
        // pricePerShare = navBefore / totalShares
        shares = (deltaNAV * totalShares) / navBefore;
    }

    totalShares += shares;

    emit ChildDeposit(assets, navBefore, navAfter, shares);
    return (shares, navBefore, navAfter);
}
```

### Withdrawal Logic (fixed proportional unwind)

**Security Design:** Withdrawal uses **fixed on-chain logic** to ensure proportional unwind and prevent keeper manipulation.

```solidity
function withdraw(uint256 shares, bytes calldata params)
    external
    onlyParent
    returns (uint256 assets)
{
    // FIXED: proportional calculation controlled on-chain
    // FIXED: unwind sequence defined by strategy implementation
    // Keeper can only provide execution parameters (swap routes, etc.)
    // that cannot be computed on-chain

    totalShares -= shares;
    emit ChildWithdraw(shares, assets);
    return assets;
}
```

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

### Rounding
- Round down on share minting to avoid over-issuance
- Round down on asset withdrawal to protect vault

### Rebalance Operations (arbitrary commands with invariants)

Child vaults may implement a `rebalance()` function for keeper-initiated optimizations:

```solidity
function rebalance(bytes calldata commands) external onlyKeeper {
    uint256 navBefore = _calculateTotalAssets();

    // Execute arbitrary commands (ADR-0002)
    _executeCommands(commands);

    uint256 navAfter = _calculateTotalAssets();

    // INVARIANT: NAV should not decrease significantly
    require(navAfter >= navBefore * threshold / 100, "NAV decreased");
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
