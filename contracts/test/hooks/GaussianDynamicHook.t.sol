// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {GaussianDynamicHookHarness} from "./GaussianDynamicHookHarness.sol";
import {GaussianDynamicHook} from "../../src/hooks/GaussianDynamicHook.sol";
import {GaussianDynamicPoolConfig} from "../../src/types/GaussianDynamicTypes.sol";

contract GaussianDynamicHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using FixedPointMathLib for uint256;

    GaussianDynamicHookHarness internal harness;
    PoolKey internal key;
    PoolId internal id;

    // pdf(0) in WAD ≈ 1 / sqrt(2π)
    uint256 internal constant PDF_ZERO_WAD = 0.3989422804e18;

    function setUp() public {
        // Dummy pool manager — getAmountOut/getAmountIn never touch it,
        // and createPool's poolManager.initialize call is mocked below.
        harness = new GaussianDynamicHookHarness(IPoolManager(address(0xDEAD)));
        key = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(harness))
        });
        id = key.toId();

        // Mock poolManager.initialize so createPool doesn't revert.
        // IPoolManager.initialize(PoolKey, uint160) returns (int24 tick).
        vm.mockCall(
            address(0xDEAD),
            abi.encodeWithSelector(IPoolManager.initialize.selector),
            abi.encode(int24(0))
        );
    }

    function _balancedReserve(uint256 w) internal pure returns (uint256) {
        return w.mulWad(PDF_ZERO_WAD);
    }

    function _computeWAtStart(uint128 sigma, uint64 duration) internal pure returns (uint256) {
        return uint256(sigma).mulWad((uint256(duration) * 1e18).sqrtWad());
    }

    function _setupPool(uint128 sigma, uint64 expiryOffset, uint256 r0, uint256 r1) internal {
        GaussianDynamicPoolConfig memory c = GaussianDynamicPoolConfig({
            sigma: sigma,
            expiry: uint64(block.timestamp) + expiryOffset,
            totalLiquidity: 0
        });
        harness.setConfig(id, c);
        harness.setReserves(id, r0, r1);
    }

    // ---------- createPool ----------

    function test_createPool_storesConfig() public {
        uint128 sigma = 1e18;
        uint64 expiry = uint64(block.timestamp) + 1 days;
        uint256 prob = 0.5e18;

        harness.createPool(key, sigma, expiry, prob);

        (uint128 storedSigma, uint64 storedExpiry, uint128 storedTotalLiquidity) = harness.poolConfigs(id);
        assertEq(storedSigma, sigma);
        assertEq(storedExpiry, expiry);
        assertEq(storedTotalLiquidity, 0);
    }

    function test_createPool_returnsCorrectId() public {
        uint128 sigma = 1e18;
        uint64 expiry = uint64(block.timestamp) + 1 days;
        PoolId returnedId = harness.createPool(key, sigma, expiry, 0.5e18);
        assertEq(PoolId.unwrap(returnedId), PoolId.unwrap(id));
    }

    function test_createPool_emitsEvent() public {
        uint128 sigma = 1e18;
        uint64 expiry = uint64(block.timestamp) + 1 days;
        uint256 prob = 0.7e18;

        vm.expectEmit(true, true, false, true, address(harness));
        emit GaussianDynamicHook.PoolCreated(id, address(this), sigma, expiry, prob);
        harness.createPool(key, sigma, expiry, prob);
    }

    function test_createPool_callsPoolManagerInitialize() public {
        uint64 expiry = uint64(block.timestamp) + 1 days;
        vm.expectCall(address(0xDEAD), abi.encodeWithSelector(IPoolManager.initialize.selector));
        harness.createPool(key, 1e18, expiry, 0.5e18);
    }

    function test_createPool_revertsWrongHook() public {
        PoolKey memory badKey = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0xBEEF))
        });
        vm.expectRevert(GaussianDynamicHook.WrongHook.selector);
        harness.createPool(badKey, 1e18, uint64(block.timestamp + 1 days), 0.5e18);
    }

    function test_createPool_revertsSigmaZero() public {
        vm.expectRevert(GaussianDynamicHook.SigmaZero.selector);
        harness.createPool(key, 0, uint64(block.timestamp + 1 days), 0.5e18);
    }

    function test_createPool_revertsExpiryInPast() public {
        vm.warp(1000);
        vm.expectRevert(GaussianDynamicHook.ExpiryInPast.selector);
        harness.createPool(key, 1e18, 500, 0.5e18);
    }

    function test_createPool_revertsExpiryEqualToNow() public {
        vm.warp(1000);
        vm.expectRevert(GaussianDynamicHook.ExpiryInPast.selector);
        harness.createPool(key, 1e18, 1000, 0.5e18);
    }

    function test_createPool_revertsProbabilityZero() public {
        vm.expectRevert(GaussianDynamicHook.InvalidProbability.selector);
        harness.createPool(key, 1e18, uint64(block.timestamp + 1 days), 0);
    }

    function test_createPool_revertsProbabilityOne() public {
        vm.expectRevert(GaussianDynamicHook.InvalidProbability.selector);
        harness.createPool(key, 1e18, uint64(block.timestamp + 1 days), 1e18);
    }

    function test_createPool_revertsProbabilityAboveOne() public {
        vm.expectRevert(GaussianDynamicHook.InvalidProbability.selector);
        harness.createPool(key, 1e18, uint64(block.timestamp + 1 days), 2e18);
    }

    function test_createPool_revertsAlreadyInitialized() public {
        uint64 expiry = uint64(block.timestamp) + 1 days;
        harness.createPool(key, 1e18, expiry, 0.5e18);

        vm.expectRevert(GaussianDynamicHook.PoolAlreadyInitialized.selector);
        harness.createPool(key, 1e18, expiry, 0.5e18);
    }

    // ---------- getAmountOut happy paths ----------

    function test_getAmountOut_zeroForOne_atBalance() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = r / 100; // 1% of reserves
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);

        assertGt(amountOut, 0);
        // In a prediction market, output is less than input (curve penalty)
        assertLt(amountOut, amountIn);
    }

    function test_getAmountOut_oneForZero_atBalance() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = r / 100;
        uint256 amountOutForward = harness.exposed_getAmountOut(key, amountIn, true);

        // Reset state and swap in the other direction — at balance the output should match
        _setupPool(sigma, duration, r, r);
        uint256 amountOutReverse = harness.exposed_getAmountOut(key, amountIn, false);

        assertApproxEqAbs(amountOutForward, amountOutReverse, 1e10);
    }

    function test_getAmountOut_updatesReserves() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = r / 50;
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);

        assertEq(harness.reserve0(id), r + amountIn);
        assertEq(harness.reserve1(id), r - amountOut);
    }

    function test_getAmountOut_skewedReserves_zeroForOne() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        // Skew toward y being larger (price favors NO)
        _setupPool(sigma, duration, r, r * 2);

        uint256 amountIn = r / 100;
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);
        assertGt(amountOut, 0);
    }

    function test_getAmountOut_timeDecay() public {
        uint128 sigma = 1e18;
        uint64 duration = 10 days;
        uint256 wStart = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(wStart);
        uint64 startTs = uint64(block.timestamp);

        _setupPool(sigma, duration, r, r);
        uint256 amountIn = r / 200;
        uint256 outStart = harness.exposed_getAmountOut(key, amountIn, true);

        // Reset reserves, warp 9 days (1 day remaining), same trade
        vm.warp(startTs + 9 days);
        harness.setReserves(id, r, r);
        uint256 outLate = harness.exposed_getAmountOut(key, amountIn, true);

        // The two outputs should differ — w shrank by ~sqrt(10)
        assertTrue(outStart != outLate);
    }

    // ---------- getAmountOut reverts ----------

    function test_getAmountOut_revertsUninitialized() public {
        vm.expectRevert(GaussianDynamicHook.PoolNotInitialized.selector);
        harness.exposed_getAmountOut(key, 1e15, true);
    }

    function test_getAmountOut_revertsExpired() public {
        _setupPool(1e18, 1 days, 1e18, 1e18);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(GaussianDynamicHook.PoolExpired.selector);
        harness.exposed_getAmountOut(key, 1e15, true);
    }

    function test_getAmountOut_revertsZeroReserve0() public {
        _setupPool(1e18, 1 days, 0, 1e18);
        vm.expectRevert(GaussianDynamicHook.InsufficientLiquidity.selector);
        harness.exposed_getAmountOut(key, 1e15, true);
    }

    function test_getAmountOut_revertsZeroReserve1() public {
        _setupPool(1e18, 1 days, 1e18, 0);
        vm.expectRevert(GaussianDynamicHook.InsufficientLiquidity.selector);
        harness.exposed_getAmountOut(key, 1e15, true);
    }

    // ---------- getAmountIn happy paths ----------

    function test_getAmountIn_zeroForOne_atBalance() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountOut = r / 100;
        uint256 amountIn = harness.exposed_getAmountIn(key, amountOut, true);

        assertGt(amountIn, amountOut); // curve penalty
    }

    function test_getAmountIn_updatesReserves() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountOut = r / 50;
        uint256 amountIn = harness.exposed_getAmountIn(key, amountOut, true);

        assertEq(harness.reserve0(id), r + amountIn);
        assertEq(harness.reserve1(id), r - amountOut);
    }

    // ---------- getAmountIn reverts ----------

    function test_getAmountIn_revertsUninitialized() public {
        vm.expectRevert(GaussianDynamicHook.PoolNotInitialized.selector);
        harness.exposed_getAmountIn(key, 1e15, true);
    }

    function test_getAmountIn_revertsAmountOutExceedsReserveY() public {
        _setupPool(1e18, 1 days, 1e18, 1e18);
        vm.expectRevert(GaussianDynamicHook.SwapExceedsReserves.selector);
        harness.exposed_getAmountIn(key, 2e18, true);
    }

    function test_getAmountIn_revertsAmountOutExceedsReserveX() public {
        _setupPool(1e18, 1 days, 1e18, 1e18);
        vm.expectRevert(GaussianDynamicHook.SwapExceedsReserves.selector);
        harness.exposed_getAmountIn(key, 2e18, false);
    }

    // ---------- Roundtrip ----------

    function test_roundtrip_exactInExactOut_zeroForOne() public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);

        _setupPool(sigma, duration, r, r);
        uint256 amountIn = r / 100;
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);

        // Reset and try exact-out for the amount we just received
        _setupPool(sigma, duration, r, r);
        uint256 recoveredIn = harness.exposed_getAmountIn(key, amountOut, true);

        assertApproxEqAbs(recoveredIn, amountIn, 1e12);
    }

    // ---------- Fuzz tests ----------

    function testFuzz_getAmountOut_outputBoundedByReserve(uint256 amountInSeed) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = bound(amountInSeed, 1, r * 3);
        try harness.exposed_getAmountOut(key, amountIn, true) returns (uint256 amountOut) {
            assertLt(amountOut, r); // output must be strictly less than the reserve before the swap
        } catch {
            // Revert is acceptable (SwapExceedsReserves etc.)
        }
    }

    function testFuzz_getAmountOut_monotonicInAmountIn(uint256 a1Seed, uint256 a2Seed) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);

        uint256 a1 = bound(a1Seed, 1e12, r / 2);
        uint256 a2 = bound(a2Seed, a1 + 1e12, r);

        _setupPool(sigma, duration, r, r);
        uint256 out1 = harness.exposed_getAmountOut(key, a1, true);

        _setupPool(sigma, duration, r, r);
        uint256 out2 = harness.exposed_getAmountOut(key, a2, true);

        assertGe(out2, out1); // larger input → larger output
    }

    function testFuzz_getAmountOut_priceDirection(uint256 amountInSeed, bool zeroForOne) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = bound(amountInSeed, 1e12, r / 2);
        uint256 r0Before = harness.reserve0(id);
        uint256 r1Before = harness.reserve1(id);

        harness.exposed_getAmountOut(key, amountIn, zeroForOne);

        if (zeroForOne) {
            assertGt(harness.reserve0(id), r0Before); // x grew
            assertLt(harness.reserve1(id), r1Before); // y shrank
        } else {
            assertLt(harness.reserve0(id), r0Before); // x shrank
            assertGt(harness.reserve1(id), r1Before); // y grew
        }
    }

    function testFuzz_roundtrip_exactIn_then_exactOut(uint256 amountInSeed) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);

        uint256 amountIn = bound(amountInSeed, 1e12, r / 4);

        _setupPool(sigma, duration, r, r);
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);

        _setupPool(sigma, duration, r, r);
        uint256 recoveredIn = harness.exposed_getAmountIn(key, amountOut, true);

        // Roundtrip should return approximately the original amount
        uint256 diff = recoveredIn > amountIn ? recoveredIn - amountIn : amountIn - recoveredIn;
        assertLt(diff, r / 1e6 + 1e12);
    }

    function testFuzz_getAmountIn_monotonicInAmountOut(uint256 o1Seed, uint256 o2Seed) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);

        uint256 o1 = bound(o1Seed, 1e12, r / 3);
        uint256 o2 = bound(o2Seed, o1 + 1e12, r / 2);

        _setupPool(sigma, duration, r, r);
        uint256 in1 = harness.exposed_getAmountIn(key, o1, true);

        _setupPool(sigma, duration, r, r);
        uint256 in2 = harness.exposed_getAmountIn(key, o2, true);

        assertGe(in2, in1); // larger desired output → larger required input
    }

    function testFuzz_noFreeTokens(uint256 amountInSeed) public {
        uint128 sigma = 1e18;
        uint64 duration = 1 days;
        uint256 w = _computeWAtStart(sigma, duration);
        uint256 r = _balancedReserve(w);
        _setupPool(sigma, duration, r, r);

        uint256 amountIn = bound(amountInSeed, 1e12, r / 10);
        uint256 amountOut = harness.exposed_getAmountOut(key, amountIn, true);

        // Near balance, output should not exceed input (prediction market: token prices sum to 1)
        assertLe(amountOut, amountIn);
    }
}
