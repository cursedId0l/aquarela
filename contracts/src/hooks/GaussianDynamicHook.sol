// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {GaussianInvariant} from "../libraries/gaussian/GaussianInvariant.sol";
import {GaussianDynamicPoolConfig} from "../types/GaussianDynamicTypes.sol";
import {BaseAquarelaHook} from "./BaseAquarelaHook.sol";

/// @title Gaussian Dynamic Hook
/// @notice pm-AMM for prediction markets with dynamic liquidity (Paradigm paper).
/// @dev Invariant: (y - x) * cdf((y - x) / w) + w * pdf((y - x) / w) - y = 0
///      where w = sigma * sqrt(T - t). Solved with Newton's method.
///      Paper notation mapping: `sigma` ↔ `L_0`, `w` ↔ `L_t`.
contract GaussianDynamicHook is BaseAquarelaHook {
    using PoolIdLibrary for PoolKey;

    error PoolNotInitialized();
    error PoolExpired();
    error PoolResolved();
    error InsufficientLiquidity();
    error SwapExceedsReserves();

    mapping(PoolId => GaussianDynamicPoolConfig) public poolConfigs;
    // @dev keep track of reserves in the hook because liquidity decreases
    // over time to help protect LP bags
    mapping(PoolId => uint256) public reserve0; // NO token
    mapping(PoolId => uint256) public reserve1; // YES token

    constructor(IPoolManager _poolManager) BaseAquarelaHook(_poolManager) {}

    // TODO: createPool() — stores config, calls poolManager.initialize()
    // TODO: addLiquidity() — takes tokens, updates reserves
    // TODO: resolvePool() — trusted resolver sets outcome

    /// @notice Compute output amount for an exact-input swap and update pool state.
    /// @dev Solves the pm-AMM invariant for the new reserve using Newton's method.
    function getAmountOut(PoolKey calldata key, uint256 amountIn, Currency, Currency, bool zeroForOne)
        internal
        override
        returns (uint256 amountOut)
    {
        PoolId id = key.toId();
        (uint256 x, uint256 y, uint256 wWad) = _loadValidPool(id);

        uint256 newX;
        uint256 newY;
        if (zeroForOne) {
            // User sells token0 (NO), buys token1 (YES) — x grows, y shrinks
            newX = x + amountIn;
            newY = GaussianInvariant.solveForY(newX, y, wWad);
            if (newY >= y) revert SwapExceedsReserves();
            amountOut = y - newY;
        } else {
            // User sells token1 (YES), buys token0 (NO) — y grows, x shrinks
            newY = y + amountIn;
            newX = GaussianInvariant.solveForX(newY, x, wWad);
            if (newX >= x) revert SwapExceedsReserves();
            amountOut = x - newX;
        }

        reserve0[id] = newX;
        reserve1[id] = newY;
    }

    /// @notice Compute input amount for an exact-output swap and update pool state.
    /// @dev Mirror of getAmountOut: we know the new reserve of the output token,
    ///      solve the invariant for the new reserve of the input token.
    function getAmountIn(PoolKey calldata key, uint256 amountOut, Currency, Currency, bool zeroForOne)
        internal
        override
        returns (uint256 amountIn)
    {
        PoolId id = key.toId();
        (uint256 x, uint256 y, uint256 wWad) = _loadValidPool(id);

        uint256 newX;
        uint256 newY;
        if (zeroForOne) {
            // User wants exact `amountOut` of token1; pays token0
            if (amountOut >= y) revert SwapExceedsReserves();
            newY = y - amountOut;
            newX = GaussianInvariant.solveForX(newY, x, wWad);
            if (newX <= x) revert SwapExceedsReserves();
            amountIn = newX - x;
        } else {
            // User wants exact `amountOut` of token0; pays token1
            if (amountOut >= x) revert SwapExceedsReserves();
            newX = x - amountOut;
            newY = GaussianInvariant.solveForY(newX, y, wWad);
            if (newY <= y) revert SwapExceedsReserves();
            amountIn = newY - y;
        }

        reserve0[id] = newX;
        reserve1[id] = newY;
    }

    /// @notice Load per-pool state and validate the pool can serve a swap.
    /// @dev Shared preamble for getAmountOut / getAmountIn.
    ///      Reverts: PoolNotInitialized, PoolResolved, PoolExpired, InsufficientLiquidity.
    function _loadValidPool(PoolId id) private view returns (uint256 x, uint256 y, uint256 wWad) {
        GaussianDynamicPoolConfig memory config = poolConfigs[id];

        if (config.expiry == 0) revert PoolNotInitialized();
        if (config.resolved) revert PoolResolved();
        if (block.timestamp >= config.expiry) revert PoolExpired();

        x = reserve0[id];
        y = reserve1[id];
        if (x == 0 || y == 0) revert InsufficientLiquidity();

        wWad = GaussianInvariant.computeW(config.sigma, config.expiry);
    }
}
