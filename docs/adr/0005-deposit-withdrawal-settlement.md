# ADR-0005: Deposit & Withdrawal Settlement

## Status
Accepted

## Date
2024-10-01

## Context
We need fair batching without oracle reliance, supporting multiple children and proportional exits.

## Requirements
- **Batched deposits:** users get receipts; no instant mint.
- **Atomic epoch:** one keeper tx executes allocation + mint/burn.
- **Entry fairness:** use deltaNAV; do not dilute existing holders.
- **Exit proportionality:** withdraw exact fraction f of every asset (incl. cash buffer).
- **No substitution:** cash buffer can only cover its proportional share.
- **Partial fills:** if some child is illiquid, deliver what’s realizable and queue the rest.
- **Idempotency:** safe re-runs on tx failure.

## Decision

### Deposit Flow

**User Submission:**
1. User calls `deposit(uint256 assets, uint256 minSharesOut)` with underlying token (e.g., USDC)
2. Assets are transferred to parent vault
3. Deposit request is stored in contract storage (not NFT):
   ```solidity
   struct DepositRequest {
       address user;
       uint256 assets;
       uint256 minSharesOut;  // slippage protection
   }
   ```
4. Users can make multiple deposits in same epoch (separate requests)
5. Users can cancel pending deposits before epoch processing

**Epoch Processing (`processEpoch()` called by keeper):**
1. Initialize `NAV_before` with parent's cash balance (excludes queued deposits)
2. Initialize `NAV_after` with parent's cash balance minus allocated amounts
3. Keeper determines allocation to children based on:
   - Available liquidity in protocols
   - Lending limits not exceeded
   - Target weights and thresholds (ADR-0003)
4. Keeper provides commands (ADR-0002) for each child vault deposit
5. Execute deposits to children, accumulate NAV values:
   ```solidity
   for each child:
       (shares, childNavBefore, childNavAfter) = child.deposit(allocation, commands)
       NAV_before += childNavBefore
       NAV_after += childNavAfter
   ```
   **Gas optimization:** Each child's `totalAssets()` called exactly 2 times (pre/post), no duplicates
6. Calculate minted shares:
   ```
   deltaNAV = NAV_after - NAV_before
   pricePerShare = (totalSupply == 0) ? 1e18 : (NAV_before / totalSupply)
   totalNewShares = deltaNAV / pricePerShare
   ```
7. Distribute shares pro-rata to deposit requests:
   ```
   userShares = (userAssets / totalQueuedAssets) × totalNewShares
   ```
8. Verify `userShares >= minSharesOut` for each request (revert if any fails)
9. Transfer shares to users, clear deposit queue

### Withdrawal Flow

**User Submission:**
1. User calls `requestWithdrawal(uint256 shares, uint256 minAssetsOut)`
2. Shares are locked (not burned yet)
3. Withdrawal request stored in contract storage:
   ```solidity
   struct WithdrawalRequest {
       address user;
       uint256 shares;
       uint256 minAssetsOut;  // slippage protection
   }
   ```
4. Users can make multiple withdrawal requests in same epoch
5. Users can cancel pending withdrawals before epoch processing

**Epoch Processing (`processWithdrawals()` called by keeper):**
1. Calculate total shares to withdraw from queue
2. Compute fraction: `f = totalWithdrawalShares / totalSupply`
3. Withdraw proportionally from each child vault:
   ```solidity
   for each child:
       childSharesToWithdraw = child.totalShares() × f
       assetsReceived = child.withdraw(childSharesToWithdraw, commands)
       totalAssetsReceived += assetsReceived
   ```
   **Gas optimization:** No `totalAssets()` calls needed (see ADR-0006)
4. Add parent's cash buffer: `totalAssetsReceived += cashBuffer × f`
5. Distribute assets proportionally to withdrawal requests:
   ```
   userAssets = (userShares / totalWithdrawalShares) × totalAssetsReceived
   ```
6. Verify `userAssets >= minAssetsOut` for each request (revert if any fails)
7. Burn shares from users
8. Transfer assets to users (or queue if partially filled)

**Partial Fills (illiquidity handling):**
- If child cannot withdraw full amount → delivers what's realizable
- Remainder stays in child, queued for future epochs
- Shares burned proportionally to delivered fraction
- User receives partial fulfillment, remainder stays queued

### Error Handling
- **Atomic execution:** All operations in `processEpoch()` are atomic
- If any child deposit/withdrawal fails → entire epoch reverts
- No partial state changes
- Keeper can retry with adjusted parameters (different allocation, different commands)

### Access Control
- **Keeper role:** Backend service that calls `processEpoch()` and `processWithdrawals()`
- Keeper decides when and where to allocate assets
- Keeper must respect on-chain invariants:
  - Target weight percentages and thresholds (ADR-0003)
  - Slippage protection (`minSharesOut` for deposits, `minAssetsOut` for withdrawals)
  - Single-owner constraint (only parent can call child vaults)
- Keeper provides optimized execution paths via commands (ADR-0002)

## Consequences
- No NAV-based over/underpayments.
- Predictable proportional exits, with transparent partial-fill queues.
- Atomic epoch processing ensures consistency (all-or-nothing).
- Keeper has flexibility within strict on-chain guardrails.

## Related ADRs
- [ADR-0003: Vault Architecture v2](0003-vault-architecture.md) - Defines overall epoch-based architecture and multi-child allocation
- [ADR-0004: NAV Calculation Method](0004-nav-calculation-method.md) - NAV snapshots used in processEpoch
