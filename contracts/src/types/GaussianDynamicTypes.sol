// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Per-pool configuration for a dynamic pm-AMM pool.
/// @dev `sigma` is the base liquidity parameter (paper notation: `L_0`).
///      At runtime it gets scaled to `w = sigma * sqrt(T - t)` (paper: `L_t`).
struct GaussianDynamicPoolConfig {
    uint128 sigma;
    uint64 expiry;
    address resolver;
    bool resolved;
    uint8 outcome;
    uint128 totalLiquidity;
}
