// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Per-pool configuration for a dynamic pm-AMM pool.
/// @dev `sigma` is the base liquidity parameter (paper notation: `L_0`).
///      At runtime it gets scaled to `w = sigma * sqrt(T - t)` (paper: `L_t`).
///      Pools stop trading at `expiry`; LPs can withdraw reserves at any time.
///      Token-level redemption (winning YES/NO -> $1/$0) is handled by a
///      separate collateral vault, not this hook.
struct GaussianDynamicPoolConfig {
    uint128 sigma;
    uint64 expiry;
    uint128 totalLiquidity;
}
