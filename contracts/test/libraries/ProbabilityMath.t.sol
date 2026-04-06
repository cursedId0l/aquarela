// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProbabilityMath} from "../../src/libraries/ProbabilityMath.sol";

contract ProbabilityMathTest is Test {
    uint256 constant TOLERANCE = 1e10;

    // --- probabilityToSqrtPriceX96 tests ---

    function test_probToSqrt_atHalf() public pure {
        // p=0.5: price ratio = 1:1, sqrtPrice = 2^96
        uint160 result = ProbabilityMath.probabilityToSqrtPriceX96(0.5e18);
        assertApproxEqAbs(uint256(result), 2 ** 96, 1);
    }

    function test_probToSqrt_atQuarter() public pure {
        // p=0.25: price = 1/3, sqrtPrice = sqrt(1/3) * 2^96
        // Verify via roundtrip instead of hardcoded expected value
        uint160 result = ProbabilityMath.probabilityToSqrtPriceX96(0.25e18);
        assert(result > 0);
        assert(result < uint160(2 ** 96)); // less than 50% price
    }

    function test_probToSqrt_clampsLow() public pure {
        // p near 0 should clamp to MIN_SQRT_PRICE
        uint160 result = ProbabilityMath.probabilityToSqrtPriceX96(0);
        assertEq(uint256(result), 4295128739);
    }

    function test_probToSqrt_clampsHigh() public pure {
        // p = 1 should clamp to MAX_SQRT_PRICE
        uint160 result = ProbabilityMath.probabilityToSqrtPriceX96(1e18);
        assertEq(uint256(result), 1461446703485210103287273052203988822378723970342);
    }

    // --- sqrtPriceX96ToProbability tests ---

    function test_sqrtToProb_atOne() public pure {
        // sqrtPrice = 2^96 means price = 1:1, p = 0.5
        uint256 result = ProbabilityMath.sqrtPriceX96ToProbability(uint160(2 ** 96));
        assertApproxEqAbs(result, 0.5e18, TOLERANCE);
    }

    // --- roundtrip tests ---

    function test_roundtrip_half() public pure {
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(0.5e18);
        uint256 p = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(p, 0.5e18, TOLERANCE);
    }

    function test_roundtrip_quarter() public pure {
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(0.25e18);
        uint256 p = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(p, 0.25e18, TOLERANCE);
    }

    function test_roundtrip_threeQuarters() public pure {
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(0.75e18);
        uint256 p = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(p, 0.75e18, TOLERANCE);
    }

    function test_roundtrip_low() public pure {
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(0.05e18);
        uint256 p = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(p, 0.05e18, TOLERANCE);
    }

    function test_roundtrip_high() public pure {
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(0.95e18);
        uint256 p = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(p, 0.95e18, TOLERANCE);
    }

    // --- Fuzz tests ---

    function testFuzz_probToSqrt_neverReverts(uint256 pWad) public pure {
        pWad = bound(pWad, 0, 1e18);
        ProbabilityMath.probabilityToSqrtPriceX96(pWad);
    }

    function testFuzz_probToSqrt_monotonic(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1e18);
        b = bound(b, a, 1e18);
        assertLe(
            ProbabilityMath.probabilityToSqrtPriceX96(a),
            ProbabilityMath.probabilityToSqrtPriceX96(b)
        );
    }

    function testFuzz_roundtrip(uint256 pWad) public pure {
        pWad = bound(pWad, 0.01e18, 0.99e18);
        uint160 sqrt = ProbabilityMath.probabilityToSqrtPriceX96(pWad);
        uint256 recovered = ProbabilityMath.sqrtPriceX96ToProbability(sqrt);
        assertApproxEqAbs(recovered, pWad, 1e12);
    }
}
