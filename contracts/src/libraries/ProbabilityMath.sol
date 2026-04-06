// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

library ProbabilityMath {
    using FixedPointMathLib for uint256;

    uint256 private constant Q96 = 2 ** 96;

    //  sqrt(p / (1-p)) * 2^96, clamped to v4 tick bounds
    function probabilityToSqrtPriceX96(uint256 pWad) internal pure returns (uint160 sqrtPriceX96) {
        uint256 ratio = pWad.divWad(1e18 - pWad).sqrtWad();
        uint256 raw = ratio * Q96 / 1e18;

        if (raw < TickMath.MIN_SQRT_PRICE) return TickMath.MIN_SQRT_PRICE;
        if (raw > TickMath.MAX_SQRT_PRICE) return TickMath.MAX_SQRT_PRICE;
        // safe: clamped to [MIN_SQRT_PRICE, MAX_SQRT_PRICE] above
        return uint160(raw);
    }

    //  sqrtPrice^2 / (2^192 + sqrtPrice^2)
    function sqrtPriceX96ToProbability(uint160 sqrtPriceX96) internal pure returns (uint256 pWad) {
        uint256 priceX96 = uint256(sqrtPriceX96).mulDiv(uint256(sqrtPriceX96), Q96);
        return priceX96.mulDiv(1e18, 2 ** 192 + priceX96);
    }
}
