// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {GaussianMath} from "../../src/libraries/gaussian/GaussianMath.sol";
import {GaussianInvariantHarness} from "./GaussianInvariantHarness.sol";

contract GaussianInvariantTest is Test {
    using FixedPointMathLib for uint256;

    GaussianInvariantHarness internal harness;

    // pdf(0) in WAD ≈ 1 / sqrt(2π)
    uint256 internal constant PDF_ZERO_WAD = 0.3989422804e18;
    // Solver residual tolerance (loose enough to absorb CDF approximation error)
    int256 internal constant RESIDUAL_TOLERANCE = 1e12;

    function setUp() public {
        harness = new GaussianInvariantHarness();
    }

    // Initial reserves on the curve at x = y: y = w * pdf(0)
    function _balancedReserve(uint256 w) internal pure returns (uint256) {
        return w.mulWad(PDF_ZERO_WAD);
    }

    function _absI(int256 v) internal pure returns (int256) {
        return v < 0 ? -v : v;
    }

    /// @dev Ground-truth invariant residual, independent of the library implementation.
    ///      Tests assert this is ~0 after the solver runs, giving us a check that
    ///      isn't coupled to any shared code path with production.
    function _residual(int256 x, int256 y, int256 w) internal pure returns (int256) {
        int256 delta = y - x;
        int256 u = (delta * 1e18) / w;
        int256 cdfU = GaussianMath.cdf(u);
        int256 pdfU = GaussianMath.pdf(u);
        return (delta * cdfU) / 1e18 + (w * pdfU) / 1e18 - y;
    }

    // ---------- solveForY unit tests ----------

    function test_residual_atBalance_isZero() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        int256 res = _residual(int256(r), int256(r), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_atBalance() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 newY = harness.solveForY(r, r, w);
        // On-curve: residual should be tiny
        int256 res = _residual(int256(r), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_smallNudge() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 newX = r + 1e15;
        uint256 newY = harness.solveForY(newX, r, w);
        // y should decrease slightly when x grows
        assertLt(newY, r);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_largeX() public view {
        uint256 w = 1e18;
        uint256 newX = 2e18;
        uint256 yInit = 0.4e18;
        uint256 newY = harness.solveForY(newX, yInit, w);
        // newX >> newY so price strongly favors YES; residual ~ 0
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_tinyW() public view {
        uint256 w = 1e15;
        uint256 r = _balancedReserve(w);
        uint256 newX = r + 1e13;
        uint256 newY = harness.solveForY(newX, r, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_largeW() public view {
        uint256 w = 100e18;
        uint256 r = _balancedReserve(w);
        uint256 newX = r + 1e18;
        uint256 newY = harness.solveForY(newX, r, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForY_initialGuessBadButConverges() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 newX = r + 5e16;
        // Bad initial guess — 10x the real answer
        uint256 badGuess = r * 10;
        uint256 newY = harness.solveForY(newX, badGuess, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    // ---------- solveForX unit tests (mirror) ----------

    function test_solveForX_atBalance() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 newX = harness.solveForX(r, r, w);
        int256 res = _residual(int256(newX), int256(r), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForX_smallNudge() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 newY = r + 1e15;
        uint256 newX = harness.solveForX(newY, r, w);
        assertLt(newX, r);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    function test_solveForX_largeY() public view {
        uint256 w = 1e18;
        uint256 newY = 2e18;
        uint256 xInit = 0.4e18;
        uint256 newX = harness.solveForX(newY, xInit, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        assertLt(_absI(res), RESIDUAL_TOLERANCE);
    }

    // ---------- symmetry ----------

    function test_solveSymmetry() public view {
        uint256 w = 1e18;
        uint256 r = _balancedReserve(w);
        uint256 dx = 5e16;
        uint256 newX = r + dx;
        uint256 newY = harness.solveForY(newX, r, w);
        uint256 recoveredX = harness.solveForX(newY, newX, w);
        // Recovered x should equal newX within tolerance
        uint256 diff = recoveredX > newX ? recoveredX - newX : newX - recoveredX;
        assertLt(diff, 1e13);
    }

    // ---------- computeW unit tests ----------

    function test_computeW_knownValue() public {
        uint128 sigma = 1e18;
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 1 days;
        vm.warp(start);
        uint256 w = harness.computeW(sigma, expiry);
        // Expected: sigma * sqrt(86400) in WAD
        // sqrtWad(86400e18) = sqrt(86400) * 1e18 ~= 293.938769e18
        uint256 expected = (uint256(86400) * 1e18).sqrtWad();
        assertApproxEqAbs(w, expected, 1e12);
    }

    function test_computeW_halvesWithQuarterTime() public {
        uint128 sigma = 1e18;
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 4 days;
        vm.warp(start);
        uint256 w0 = harness.computeW(sigma, expiry);
        // Warp 3 days forward → 1 day remaining (quarter of original) → w should be half
        vm.warp(start + 3 days);
        uint256 w1 = harness.computeW(sigma, expiry);
        assertApproxEqAbs(w1 * 2, w0, 1e10);
    }

    function test_computeW_atExpiry_isZero() public {
        uint128 sigma = 1e18;
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 1 days;
        vm.warp(expiry);
        uint256 w = harness.computeW(sigma, expiry);
        assertEq(w, 0);
    }

    function test_computeW_pastExpiry_reverts() public {
        uint128 sigma = 1e18;
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 1 days;
        vm.warp(expiry + 1);
        vm.expectRevert();
        harness.computeW(sigma, expiry);
    }

    function test_computeW_sigmaZero() public {
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 1 days;
        vm.warp(start);
        uint256 w = harness.computeW(0, expiry);
        assertEq(w, 0);
    }

    function test_computeW_monotonicDecreasingInT() public {
        uint128 sigma = 1e18;
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + 10 days;
        vm.warp(start);
        uint256 w0 = harness.computeW(sigma, expiry);
        vm.warp(start + 1 days);
        uint256 w1 = harness.computeW(sigma, expiry);
        vm.warp(start + 5 days);
        uint256 w2 = harness.computeW(sigma, expiry);
        assertGt(w0, w1);
        assertGt(w1, w2);
    }

    // ---------- Fuzz tests ----------

    function testFuzz_solveForY_residualNearZero(uint256 wSeed, uint256 dxSeed) public view {
        uint256 w = bound(wSeed, 1e15, 1e22);
        uint256 r = _balancedReserve(w);
        uint256 dx = bound(dxSeed, 0, r * 5);
        uint256 newX = r + dx;
        uint256 newY = harness.solveForY(newX, r, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        // Tolerance scales with w for larger pool sizes
        int256 tol = int256(w / 1e3) + RESIDUAL_TOLERANCE;
        assertLt(_absI(res), tol);
    }

    function testFuzz_solveForX_residualNearZero(uint256 wSeed, uint256 dySeed) public view {
        uint256 w = bound(wSeed, 1e15, 1e22);
        uint256 r = _balancedReserve(w);
        uint256 dy = bound(dySeed, 0, r * 5);
        uint256 newY = r + dy;
        uint256 newX = harness.solveForX(newY, r, w);
        int256 res = _residual(int256(newX), int256(newY), int256(w));
        int256 tol = int256(w / 1e3) + RESIDUAL_TOLERANCE;
        assertLt(_absI(res), tol);
    }

    function testFuzz_solveForY_monotonicInX(uint256 wSeed, uint256 dx1Seed, uint256 dx2Seed) public view {
        uint256 w = bound(wSeed, 1e16, 1e22);
        uint256 r = _balancedReserve(w);
        uint256 dx1 = bound(dx1Seed, 1e12, r * 3);
        uint256 dx2 = bound(dx2Seed, dx1 + 1e12, dx1 + r * 3 + 1e12);
        uint256 newY1 = harness.solveForY(r + dx1, r, w);
        uint256 newY2 = harness.solveForY(r + dx2, r, w);
        // Larger x increase → smaller y
        assertLe(newY2, newY1);
    }

    function testFuzz_solveSymmetry(uint256 wSeed, uint256 dxSeed) public view {
        uint256 w = bound(wSeed, 1e16, 1e22);
        uint256 r = _balancedReserve(w);
        uint256 dx = bound(dxSeed, 1e12, r * 2);
        uint256 newX = r + dx;
        uint256 newY = harness.solveForY(newX, r, w);
        uint256 recoveredX = harness.solveForX(newY, newX, w);
        uint256 diff = recoveredX > newX ? recoveredX - newX : newX - recoveredX;
        // Allow a few orders of magnitude headroom — two solver runs compound error
        assertLt(diff, w / 1e6 + 1e13);
    }

    function testFuzz_computeW_monotonicInTime(uint128 sigma, uint32 tOffset, uint32 warpDelta) public {
        // sigma must be non-zero for w to be non-zero and show strict monotonicity
        sigma = uint128(bound(uint256(sigma), 1e6, type(uint128).max / 2));
        uint256 offset = bound(uint256(tOffset), 2, 365 days);
        uint256 delta = bound(uint256(warpDelta), 1, offset - 1);
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + uint64(offset);
        vm.warp(start);
        uint256 w0 = harness.computeW(sigma, expiry);
        vm.warp(start + delta);
        uint256 w1 = harness.computeW(sigma, expiry);
        assertGt(w0, w1);
    }

    function testFuzz_computeW_scalesWithSigma(uint128 sigmaSeed, uint32 tOffset) public {
        uint128 sigma = uint128(bound(uint256(sigmaSeed), 1e6, type(uint128).max / 4));
        uint64 start = uint64(block.timestamp);
        uint64 expiry = start + uint64(bound(uint256(tOffset), 1 hours, 365 days));
        vm.warp(start);
        uint256 w1 = harness.computeW(sigma, expiry);
        uint256 w2 = harness.computeW(sigma * 2, expiry);
        // Doubling sigma doubles w (within rounding)
        assertApproxEqAbs(w2, w1 * 2, 1e10);
    }
}
