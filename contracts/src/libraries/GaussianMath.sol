// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title Gaussian math for the pm-AMM invariant
/// @notice Standard normal PDF and CDF in WAD (1e18) fixed-point
/// @dev CDF/erfc adapted from primitivefinance/solstat (Gaussian.sol)
///      Uses Abramowitz & Stegun / Numerical Recipes erfc approximation.
///      Original: https://github.com/primitivefinance/solstat/blob/main/src/Gaussian.sol
library GaussianMath {
    using FixedPointMathLib for int256;
    using FixedPointMathLib for uint256;

    int256 private constant WAD = 1e18;
    int256 private constant TWO = 2e18;
    int256 private constant SQRT2 = 1_414213562373095048;
    int256 private constant SQRT_2PI = 2_506628274631000502;

    // erfc domain bounds — beyond these, returns 0 or 2
    int256 private constant ERFC_DOMAIN_UPPER = 6.24e18;
    int256 private constant ERFC_DOMAIN_LOWER = -6.24e18;

    // Abramowitz & Stegun erfc coefficients
    int256 private constant ERFC_A = 1_265512230000000000;
    int256 private constant ERFC_B = 1_000023680000000000;
    int256 private constant ERFC_C = 374091960000000000;
    int256 private constant ERFC_D = 96784180000000000;
    int256 private constant ERFC_E = -186288060000000000;
    int256 private constant ERFC_F = 278868070000000000;
    int256 private constant ERFC_G = -1_135203980000000000;
    int256 private constant ERFC_H = 1_488515870000000000;
    int256 private constant ERFC_I = -822152230000000000;
    int256 private constant ERFC_J = 170872770000000000;

    // PDF gives the height of the bell curve at point x
    // Formula: pdf(x) = e^(-x²/2) / √(2π)
    function pdf(int256 x) internal pure returns (int256) {
        int256 e = (-x * x) / TWO;
        e = e.expWad();
        return (e * WAD) / SQRT_2PI;
    }

    // Complementary error function: erfc(x) = 1 - erf(x)
    // erfc(0) = 1, erfc(∞) = 0, erfc(-∞) = 2
    function erfc(int256 input) internal pure returns (int256 output) {
        if (input == 0) return WAD;
        if (input >= ERFC_DOMAIN_UPPER) return 0;
        if (input <= ERFC_DOMAIN_LOWER) return TWO;

        uint256 z = _abs(input);
        int256 t = (WAD * WAD) / (WAD + int256(z.divWad(2e18)));

        int256 step;
        {
            step = ERFC_F + _mul(t, ERFC_G + _mul(t, ERFC_H + _mul(t, ERFC_I + _mul(t, ERFC_J))));
        }

        int256 k;
        {
            step = _mul(t, ERFC_B + _mul(t, ERFC_C + _mul(t, ERFC_D + _mul(t, ERFC_E + _mul(t, step)))));
            k = (-1 * _mul(int256(z), int256(z))) - ERFC_A + step;
        }

        int256 exp = k.expWad();
        int256 r = _mul(t, exp);
        output = (input < 0) ? TWO - r : r;
    }

    // CDF gives the probability that a value falls below x, range [0, 1e18]
    // Formula: cdf(x) = 0.5 * erfc(-x / √2)
    function cdf(int256 x) internal pure returns (int256) {
        int256 input = (x * WAD) / SQRT2;
        int256 _erfc = erfc(-input);
        return (_erfc * WAD) / TWO;
    }

    // WAD-scaled signed multiply: (a * b) / 1e18
    function _mul(int256 a, int256 b) private pure returns (int256) {
        return (a * b) / WAD;
    }

    // Absolute value
    function _abs(int256 x) private pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }
}
