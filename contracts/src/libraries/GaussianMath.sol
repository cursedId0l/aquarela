// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title Gaussian math for the pm-AMM invariant
/// @notice Standard normal PDF and CDF in WAD (1e18) fixed-point
/// @dev CDF implementation adapted from marcuspang/paradigm-guassian
///      which uses the Dia (2023) approximation. Error rate < 1e-8.
///      Original: https://github.com/marcuspang/paradigm-guassian/blob/main/src/GaussianCorrectness.sol
library GaussianMath {
    using FixedPointMathLib for int256;

    int256 private constant WAD = 1e18;
    int256 private constant SQRT_2PI_WAD = 2_506628274631000502; // sqrt(2*pi) * 1e18

    // Dia (2023) CDF approximation coefficients
    int256 private constant B_0 = 2926786005158048154;
    int256 private constant B_1_1 = 8972806590468173504;
    int256 private constant B_1_2 = 10271570611713630789;
    int256 private constant B_1_3 = 12723232619077609280;
    int256 private constant B_1_4 = 16886395620079369078;
    int256 private constant B_1_5 = 24123337745724791104;
    int256 private constant B_2_1 = 5815825189335273905;
    int256 private constant B_2_2 = 5703479358980514367;
    int256 private constant B_2_3 = 5518624830257079631;
    int256 private constant B_2_4 = 5261842395796042073;
    int256 private constant B_2_5 = 4920813466328820329;
    int256 private constant C_1_1 = 11615112262606032471;
    int256 private constant C_1_2 = 18253232353473465248;
    int256 private constant C_1_3 = 18388712257739384869;
    int256 private constant C_1_4 = 18611933189717757950;
    int256 private constant C_1_5 = 24148040728127628211;
    int256 private constant C_2_1 = 3833629478001461794;
    int256 private constant C_2_2 = 7307562585536735411;
    int256 private constant C_2_3 = 8427423004580432404;
    int256 private constant C_2_4 = 5664795188784707648;
    int256 private constant C_2_5 = 4913960988952400752;

    // @issue need to check that the rounding here is ok for this math
    // PDF gives the height of the bell curve at point x
    // Formula: pdf(x) = e^(-x²/2) / √(2π)
    function pdf(int256 x) public pure returns (int256) {
        int256 xSquared = x.rawSMulWad(x);
        int256 exponent = -(xSquared / 2);
        int256 numerator = exponent.expWad();
        return numerator.sDivWad(SQRT_2PI_WAD);
    }

    // CDF gives the probability that a value falls below x, range [0, 1e18]
    // Uses Dia (2023) rational polynomial approximation via erfc
    // Formula: cdf(x) = 1 - erfc(x) / 2, with symmetry for x < 0
    function cdf(int256 x) public pure returns (int256) {
        if (x < 0) {
            return WAD - cdf(-x);
        }

        // Compute erfc approximation using rational polynomial
        int256 numerator = 0;
        int256 denominator = x + B_0;
        int256 xSquared = x.rawSMulWad(x);

        numerator += (C_2_1 * xSquared + C_1_1).rawSMulWad(x);
        denominator = denominator.rawSMulWad(xSquared + B_2_1 * x + B_1_1);
        numerator += (C_2_2 * xSquared + C_1_2).rawSMulWad(x);
        denominator = denominator.rawSMulWad(xSquared + B_2_2 * x + B_1_2);
        numerator += (C_2_3 * xSquared + C_1_3).rawSMulWad(x);
        denominator = denominator.rawSMulWad(xSquared + B_2_3 * x + B_1_3);
        numerator += (C_2_4 * xSquared + C_1_4).rawSMulWad(x);
        denominator = denominator.rawSMulWad(xSquared + B_2_4 * x + B_1_4);
        numerator += (C_2_5 * xSquared + C_1_5).rawSMulWad(x);
        denominator = denominator.rawSMulWad(xSquared + B_2_5 * x + B_1_5);

        int256 m = numerator.rawSDivWad(denominator);

        // erfc = sqrt(2*pi) * m * exp(-x^2/2)
        int256 expTerm = (-(xSquared / 2)).expWad();
        int256 erfc = (SQRT_2PI_WAD.rawSMulWad(m)).rawSMulWad(expTerm);

        return WAD - erfc / 2;
    }
}
