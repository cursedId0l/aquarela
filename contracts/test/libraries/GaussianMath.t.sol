// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GaussianMath} from "../../src/libraries/gaussian/GaussianMath.sol";

contract GaussianMathTest is Test {
    uint256 constant TOLERANCE = 1e10;

    // --- PDF tests ---

    function test_pdf_atZero() public pure {
        int256 result = GaussianMath.pdf(0);
        assertApproxEqAbs(result, 0.3989422804e18, TOLERANCE);
    }

    function test_pdf_atOne() public pure {
        int256 result = GaussianMath.pdf(1e18);
        assertApproxEqAbs(result, 0.2419707245e18, TOLERANCE);
    }

    function test_pdf_atTwo() public pure {
        int256 result = GaussianMath.pdf(2e18);
        assertApproxEqAbs(result, 0.0539909665e18, TOLERANCE);
    }

    function test_pdf_symmetry() public pure {
        int256 pos1 = GaussianMath.pdf(1e18);
        int256 neg1 = GaussianMath.pdf(-1e18);
        assertEq(pos1, neg1);

        int256 pos2 = GaussianMath.pdf(2.5e18);
        int256 neg2 = GaussianMath.pdf(-2.5e18);
        assertEq(pos2, neg2);
    }

    // --- CDF tests ---

    function test_cdf_atZero() public pure {
        int256 result = GaussianMath.cdf(0);
        assertApproxEqAbs(result, 0.5e18, TOLERANCE);
    }

    function test_cdf_atOne() public pure {
        int256 result = GaussianMath.cdf(1e18);
        assertApproxEqAbs(result, 0.8413447461e18, TOLERANCE);
    }

    function test_cdf_atNegativeOne() public pure {
        int256 result = GaussianMath.cdf(-1e18);
        assertApproxEqAbs(result, 0.1586552539e18, TOLERANCE);
    }

    function test_cdf_atTwo() public pure {
        int256 result = GaussianMath.cdf(2e18);
        assertApproxEqAbs(result, 0.9772498681e18, TOLERANCE);
    }

    function test_cdf_symmetry() public pure {
        int256 pos = GaussianMath.cdf(1e18);
        int256 neg = GaussianMath.cdf(-1e18);
        assertApproxEqAbs(pos + neg, 1e18, TOLERANCE);

        int256 pos2 = GaussianMath.cdf(2.5e18);
        int256 neg2 = GaussianMath.cdf(-2.5e18);
        assertApproxEqAbs(pos2 + neg2, 1e18, TOLERANCE);
    }

    function test_cdf_bounds() public pure {
        int256 low = GaussianMath.cdf(-6e18);
        int256 high = GaussianMath.cdf(6e18);
        assertApproxEqAbs(low, 0, 1e12);
        assertApproxEqAbs(high, 1e18, 1e12);
    }

    // --- Fuzz tests ---

    function testFuzz_pdf_nonNegative(int256 x) public pure {
        x = bound(x, -6e18, 6e18);
        int256 result = GaussianMath.pdf(x);
        assertGe(result, 0);
    }

    function testFuzz_pdf_symmetry(int256 x) public pure {
        x = bound(x, -6e18, 6e18);
        assertEq(GaussianMath.pdf(x), GaussianMath.pdf(-x));
    }

    function testFuzz_pdf_peakAtZero(int256 x) public pure {
        x = bound(x, 0.01e18, 6e18);
        assertGe(GaussianMath.pdf(0), GaussianMath.pdf(x));
    }

    function testFuzz_cdf_inRange(int256 x) public pure {
        x = bound(x, -6e18, 6e18);
        int256 result = GaussianMath.cdf(x);
        assertGe(result, 0);
        assertLe(result, 1e18);
    }

    function testFuzz_cdf_symmetry(int256 x) public pure {
        x = bound(x, -6e18, 6e18);
        int256 sum = GaussianMath.cdf(x) + GaussianMath.cdf(-x);
        assertApproxEqAbs(sum, 1e18, TOLERANCE);
    }

    function testFuzz_cdf_monotonic(int256 a, int256 b) public pure {
        a = bound(a, -6e18, 6e18);
        b = bound(b, a, 6e18);
        // Allow for erfc approximation error (1.2e-7)
        assertGe(GaussianMath.cdf(b) + 1e11, GaussianMath.cdf(a));
    }
}
