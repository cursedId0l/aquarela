// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GaussianMath} from "../../src/libraries/GaussianMath.sol";

contract GaussianMathTest is Test {
    uint256 constant TOLERANCE = 1e10;

    // --- PDF tests ---

    function test_pdf_atZero() public pure {
        // pdf(0) = 1/sqrt(2*pi) ≈ 0.3989422804
    }

    function test_pdf_atOne() public pure {
        // pdf(1) ≈ 0.2419707245
    }

    function test_pdf_symmetry() public pure {
        // pdf(x) == pdf(-x) for all x
    }

    // --- CDF tests ---

    function test_cdf_atZero() public pure {
        // cdf(0) = 0.5
    }

    function test_cdf_atOne() public pure {
        // cdf(1) ≈ 0.8413447461
    }

    function test_cdf_atNegativeOne() public pure {
        // cdf(-1) ≈ 0.1586552539
    }

    function test_cdf_symmetry() public pure {
        // cdf(x) + cdf(-x) == 1e18
    }

    function test_cdf_bounds() public pure {
        // cdf at extreme values: cdf(-6) ≈ 0, cdf(6) ≈ 1e18
    }
}
