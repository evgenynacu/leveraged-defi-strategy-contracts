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
    /// @param commands ABI-encoded command sequence for unwinding position
    /// @return assets Actual assets returned to parent
    /// @dev Does NOT calculate totalAssets (gas optimization)
    function withdraw(uint256 shares, bytes calldata commands)
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

### Withdrawal Logic (proportional, no NAV calculation)

```solidity
function withdraw(uint256 shares, bytes calldata commands)
    external
    onlyParent
    returns (uint256 assets)
{
    // Execute unwind commands (e.g., FlashLoan -> Repay -> Withdraw -> Swap -> Repay)
    assets = _executeCommands(commands);

    totalShares -= shares;

    emit ChildWithdraw(shares, assets);
    return assets;
}
```

**Key insight:** Withdraw does NOT call `totalAssets()` - massive gas savings. Parent withdraws proportionally based on shares.

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

## Consequences
- Easy integration of heterogeneous strategies.
- Parent can perform accurate proportional exits across children.

## Related ADRs
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Defines parent-child relationship and multi-child allocation
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - totalAssets contributes to parent NAV
- [ADR-0002: Command-Based Execution](0002-command-based-execution.md) - Data parameter may contain command sequences
