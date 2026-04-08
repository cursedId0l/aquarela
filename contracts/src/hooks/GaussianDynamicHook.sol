// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {GaussianInvariant} from "../libraries/gaussian/GaussianInvariant.sol";
import {ProbabilityMath} from "../libraries/ProbabilityMath.sol";
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
    error InsufficientLiquidity();
    error SwapExceedsReserves();
    error PoolAlreadyInitialized();
    error ExpiryInPast();
    error SigmaZero();
    error InvalidProbability();
    error WrongHook();

    event PoolCreated(
        PoolId indexed id,
        address indexed creator,
        uint128 sigma,
        uint64 expiry,
        uint256 initialProbabilityWad
    );

    mapping(PoolId => GaussianDynamicPoolConfig) public poolConfigs;
    // @dev keep track of reserves in the hook because liquidity decreases
    // over time to help protect LP bags
    mapping(PoolId => uint256) public reserve0; // NO token
    mapping(PoolId => uint256) public reserve1; // YES token

    constructor(IPoolManager _poolManager) BaseAquarelaHook(_poolManager) {}

    /// @notice Create a new pm-AMM prediction market pool.
    /// @param key The v4 PoolKey. `key.hooks` must point to this contract.
    /// @param sigma Base liquidity parameter (WAD). Paper notation: L_0.
    /// @param expiry Unix timestamp at which swaps stop.
    /// @param initialProbabilityWad Starting YES probability in WAD, must be in (0, 1e18).
    /// @return id The PoolId of the newly created pool.
    function createPool(
        PoolKey calldata key,
        uint128 sigma,
        uint64 expiry,
        uint256 initialProbabilityWad
    ) external returns (PoolId id) {
        // --- Validation ---
        if (address(key.hooks) != address(this)) revert WrongHook();
        if (sigma == 0) revert SigmaZero();
        if (expiry <= block.timestamp) revert ExpiryInPast();
        if (initialProbabilityWad == 0 || initialProbabilityWad >= 1e18) revert InvalidProbability();

        id = key.toId();
        if (poolConfigs[id].expiry != 0) revert PoolAlreadyInitialized();

        // --- Store config ---
        poolConfigs[id] = GaussianDynamicPoolConfig({
            sigma: sigma,
            expiry: expiry,
            totalLiquidity: 0
        });

        // --- Register with v4 ---
        // sqrtPriceX96 is stored in v4's slot0 at initialization and never
        // updated afterward (our beforeSwap nets the swap to zero). We set it
        // from the target probability so integrators reading v4 state at least
        // see the correct starting price.
        uint160 sqrtPriceX96 = ProbabilityMath.probabilityToSqrtPriceX96(initialProbabilityWad);
        poolManager.initialize(key, sqrtPriceX96);

        emit PoolCreated(id, msg.sender, sigma, expiry, initialProbabilityWad);
    }

    // TODO: addLiquidity() — takes tokens, updates reserves
    // TODO: removeLiquidity() — LPs withdraw their share; works before or after expiry

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
    ///      Reverts: PoolNotInitialized, PoolExpired, InsufficientLiquidity.
    function _loadValidPool(PoolId id) private view returns (uint256 x, uint256 y, uint256 wWad) {
        GaussianDynamicPoolConfig memory config = poolConfigs[id];

        if (config.expiry == 0) revert PoolNotInitialized();
        if (block.timestamp >= config.expiry) revert PoolExpired();

        x = reserve0[id];
        y = reserve1[id];
        if (x == 0 || y == 0) revert InsufficientLiquidity();

        wWad = GaussianInvariant.computeW(config.sigma, config.expiry);
    }
}
