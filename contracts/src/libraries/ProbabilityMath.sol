// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

library ProbabilityMath {
    using FixedPointMathLib for uint256;

    uint256 private constant Q96 = 2 ** 96;
    uint256 private constant Q192 = 2 ** 192;

    //  sqrt(p / (1-p)) * 2^96, clamped to v4 tick bounds
    function probabilityToSqrtPriceX96(uint256 pWad) internal pure returns (uint160 sqrtPriceX96) {
        if (pWad == 0) return TickMath.MIN_SQRT_PRICE;
        if (pWad >= 1e18) return TickMath.MAX_SQRT_PRICE;

        uint256 ratio = pWad.divWad(1e18 - pWad).sqrtWad();
        uint256 raw = ratio * Q96 / 1e18;

        if (raw < TickMath.MIN_SQRT_PRICE) return TickMath.MIN_SQRT_PRICE;
        if (raw > TickMath.MAX_SQRT_PRICE) return TickMath.MAX_SQRT_PRICE;
        // safe: clamped to [MIN_SQRT_PRICE, MAX_SQRT_PRICE] above (both fit in uint160)
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(raw);
    }

    //  p = sqrtPrice^2 / (2^192 + sqrtPrice^2)
    function sqrtPriceX96ToProbability(uint160 sqrtPriceX96) internal pure returns (uint256 pWad) {
        // Compute price = sqrtPrice^2 / 2^192 in WAD to avoid overflow
        // price_wad = sqrtPrice * sqrtPrice * 1e18 / 2^192
        // Use mulDiv to avoid overflow: mulDiv(sqrtPrice, sqrtPrice * 1e18, 2^192)
        uint256 priceWad = uint256(sqrtPriceX96).mulDiv(uint256(sqrtPriceX96), Q192 / 1e18);
        // p = price / (1 + price) = priceWad / (1e18 + priceWad)
        return priceWad * 1e18 / (1e18 + priceWad);
    }
}
