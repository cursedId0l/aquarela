// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {GaussianMath} from "./GaussianMath.sol";

/// @title Gaussian Invariant Library
/// @notice Pure math for the pm-AMM invariant and its Newton's method solvers.
/// @dev Invariant: (y - x) * cdf((y - x) / w) + w * pdf((y - x) / w) - y = 0
///      where w = sigma * sqrt(T - t) is the dynamic liquidity parameter.
///
///      Naming note: the Paradigm pm-AMM paper writes this as `L_t = L_0 * sqrt(T - t)`.
///      We use the shorter aliases `w` (width / effective liquidity at current time)
///      and `sigma` (base liquidity parameter) for readability in code.
///      Mapping: paper `L_0` == code `sigma`, paper `L_t` == code `w`.
///
///      ASCII-only convention: comments use `cdf` / `pdf` / `*` in place of the
///      paper's `Phi` / `phi` / `·`. This keeps the codebase grep-friendly and
///      matches the function names in GaussianMath. See docs/pm-amm-math.md.
library GaussianInvariant {
    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    /// @dev Newton's method converges quadratically; 8 iterations is plenty for WAD precision
    uint256 internal constant NEWTON_ITERATIONS = 8;
    /// @dev Tolerance for invariant residual in WAD (1e-9)
    int256 internal constant NEWTON_TOLERANCE = 1e9;

    /// @notice Compute dynamic liquidity parameter w = sigma * sqrt(T - t) in WAD.
    /// @dev Paper notation: L_t = L_0 * sqrt(T - t).
    function computeW(uint128 sigma, uint64 expiry) internal view returns (uint256 wWad) {
        uint256 timeRemaining = uint256(expiry) - block.timestamp;
        // timeRemaining is in seconds (unitless integer). Scale to WAD and take sqrt.
        uint256 sqrtTimeWad = (timeRemaining * 1e18).sqrtWad();
        wWad = uint256(sigma).mulWad(sqrtTimeWad);
    }

    /// @dev Evaluate the invariant residual f and return it alongside cdf(u).
    ///      The Newton step reuses cdfU to compute f' without a second CDF call.
    ///      Shared by solveForY and solveForX — one place to change the math.
    function _evalF(int256 x, int256 y, int256 w) private pure returns (int256 f, int256 cdfU) {
        int256 delta = y - x;
        int256 u = (delta * 1e18) / w;
        cdfU = GaussianMath.cdf(u);
        int256 pdfU = GaussianMath.pdf(u);
        f = (delta * cdfU) / 1e18 + (w * pdfU) / 1e18 - y;
    }

    /// @notice Newton's method: given new x, solve the invariant for y.
    /// @dev f(y) = (y - x) * cdf((y - x) / w) + w * pdf((y - x) / w) - y
    ///      f'(y) = cdf((y - x) / w) - 1   (derived analytically; PDF terms cancel)
    function solveForY(uint256 xReserve, uint256 yInitial, uint256 wWad) internal pure returns (uint256) {
        int256 x = xReserve.toInt256();
        int256 w = wWad.toInt256();
        int256 y = yInitial.toInt256();

        for (uint256 i = 0; i < NEWTON_ITERATIONS; i++) {
            (int256 f, int256 cdfU) = _evalF(x, y, w);

            if (f >= -NEWTON_TOLERANCE && f <= NEWTON_TOLERANCE) break;

            // f'(y) = cdf(u) - 1  (always in [-1, 0])
            int256 fPrime = cdfU - 1e18;
            if (fPrime == 0) break;

            y = y - (f * 1e18) / fPrime;
            if (y < 0) y = 0;
        }

        // safe: y was clamped to non-negative inside the loop
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(y);
    }

    /// @notice Newton's method: given new y, solve the invariant for x.
    /// @dev f(x) = (y - x) * cdf((y - x) / w) + w * pdf((y - x) / w) - y
    ///      f'(x) = -cdf((y - x) / w)   (derived analytically; PDF terms cancel)
    function solveForX(uint256 yReserve, uint256 xInitial, uint256 wWad) internal pure returns (uint256) {
        int256 y = yReserve.toInt256();
        int256 w = wWad.toInt256();
        int256 x = xInitial.toInt256();

        for (uint256 i = 0; i < NEWTON_ITERATIONS; i++) {
            (int256 f, int256 cdfU) = _evalF(x, y, w);

            if (f >= -NEWTON_TOLERANCE && f <= NEWTON_TOLERANCE) break;

            // f'(x) = -cdf(u)
            int256 fPrime = -cdfU;
            if (fPrime == 0) break;

            x = x - (f * 1e18) / fPrime;
            if (x < 0) x = 0;
        }

        // safe: x was clamped to non-negative inside the loop
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(x);
    }
}
