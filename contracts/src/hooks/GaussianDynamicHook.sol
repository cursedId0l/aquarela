// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {GaussianMath} from "../libraries/GaussianMath.sol";
import {ProbabilityMath} from "../libraries/ProbabilityMath.sol";
import {GaussianDynamicPoolConfig} from "../types/GaussianDynamicTypes.sol";
import {BaseAquarelaHook} from "./BaseAquarelaHook.sol";

contract GaussianDynamicHook is BaseAquarelaHook {
    using PoolIdLibrary for PoolKey;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    error PoolNotInitialized();
    error PoolExpired();

    // Per-pool config
    mapping(PoolId => GaussianDynamicPoolConfig) public poolConfigs;

    // Per-pool reserves (tracked by the hook, not v4)
    mapping(PoolId => uint256) public reserve0; // NO token
    mapping(PoolId => uint256) public reserve1; // YES token

    constructor(IPoolManager _poolManager) BaseAquarelaHook(_poolManager) {}

    // TODO: createPool() — stores config, calls poolManager.initialize()
    // TODO: addLiquidity() — takes tokens, updates reserves
    // TODO: resolvePool() — trusted resolver sets outcome

    function getAmountOut(uint256 amountIn, Currency, Currency, bool zeroForOne)
        internal
        override
        returns (uint256 amountOut)
    {
        // TODO: implement pm-AMM swap
        // 1. Load pool reserves (x, y) and config (sigma, expiry)
        // 2. Compute b = sigma * sqrt(expiry - block.timestamp)
        // 3. New x' = x + amountIn (or y' = y + amountIn depending on direction)
        // 4. Solve invariant for the other reserve using Newton's method
        // 5. amountOut = old reserve - new reserve
    }

    function getAmountIn(uint256 amountOut, Currency, Currency, bool zeroForOne)
        internal
        override
        returns (uint256 amountIn)
    {
        // TODO: implement reverse swap (exact output)
    }
}
