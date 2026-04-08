// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {GaussianDynamicHook} from "../../src/hooks/GaussianDynamicHook.sol";
import {GaussianDynamicPoolConfig} from "../../src/types/GaussianDynamicTypes.sol";

/// @notice Subclass that exposes internal swap math and per-pool state setters for testing.
contract GaussianDynamicHookHarness is GaussianDynamicHook {
    constructor(IPoolManager pm) GaussianDynamicHook(pm) {}

    function exposed_getAmountOut(PoolKey calldata key, uint256 amountIn, bool zeroForOne)
        external
        returns (uint256)
    {
        return getAmountOut(key, amountIn, key.currency0, key.currency1, zeroForOne);
    }

    function exposed_getAmountIn(PoolKey calldata key, uint256 amountOut, bool zeroForOne)
        external
        returns (uint256)
    {
        return getAmountIn(key, amountOut, key.currency0, key.currency1, zeroForOne);
    }

    function setConfig(PoolId id, GaussianDynamicPoolConfig calldata c) external {
        poolConfigs[id] = c;
    }

    function setReserves(PoolId id, uint256 r0, uint256 r1) external {
        reserve0[id] = r0;
        reserve1[id] = r1;
    }
}
