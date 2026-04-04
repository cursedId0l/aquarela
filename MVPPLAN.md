# Aquarela MVP Build Plan

## Context

Aquarela is a Uniswap v4 hook system with pluggable pricing curves and LDFs. The codebase is a blank slate — fresh Foundry template + Next.js scaffold. No v4 deps, no contracts, no tests. This plan covers the full MVP build from zero.

## Architecture (Decided)

- Singleton AquarelaHook — one deployment, delegates to external curve/LDF contracts per pool
- Pool creation on the hook (no separate factory)
- Curves implement `IPricingCurve`, LDFs implement `ILDF` — both stateless view contracts
- Libraries for shared/heavy logic (size management)
- If a future curve needs different hook permissions, deploy it as its own hook

## Open Questions — Recommendations

1. **Normal CDF in Solidity**: Abramowitz & Stegun polynomial approximation (|error| < 7.5e-8). Pure math, no storage, fuzz-testable.
2. **Probability to sqrtPriceX96**: `sqrtPriceX96 = sqrt(p / (1-p)) * 2^96`. Reverse: `p = sqrtPrice^2 / (2^192 + sqrtPrice^2)`.
3. **Resolution mechanism**: Trusted resolver address per pool for MVP. Oracle integration in v2.

## Implementation Phases

### Phase 0: Foundation
- [ ] Install v4-core, v4-periphery, solady via forge
- [ ] Configure foundry.toml (solc 0.8.26, cancun EVM, remappings)
- [ ] Create directory structure (src/, interfaces/, curves/, ldfs/, libraries/, types/, test/)
- [ ] Delete Counter placeholder
- **Gate**: `forge build` compiles

### Phase 1: Types + Interfaces
- [ ] `AquarelaTypes.sol` — PoolConfig struct
- [ ] `IPricingCurve.sol` — computeSwap(), usesLDF(), name()
- [ ] `ILDF.sol` — liquidityDensity(), cumulativeLiquidity(), name()
- [ ] `IAquarelaHook.sol` — createPool(), resolvePool(), getPoolConfig(), events
- **Gate**: `forge build` compiles

### Phase 2: Math Libraries
- [ ] `GaussianMath.sol` — cdf(), pdf(), inverseCdf() in WAD fixed-point
- [ ] `ProbabilityMath.sol` — probabilityToSqrtPriceX96(), sqrtPriceX96ToProbability()
- [ ] Tests: known values, symmetry, monotonicity, roundtrip, fuzz
- **Gate**: `forge test --match-path "test/libraries/*"` passes

### Phase 3: AquarelaHook Skeleton
- [ ] Singleton hook inheriting BaseHook
- [ ] Permissions: beforeInitialize, beforeAddLiquidity, beforeRemoveLiquidity, beforeSwap, beforeSwapReturnDelta
- [ ] createPool() stores config + calls poolManager.initialize()
- [ ] beforeSwap delegates to IPricingCurve.computeSwap(), returns BeforeSwapDelta
- [ ] AquarelaHookLogic library for heavy logic (size management)
- [ ] Tests with mock curve: pool creation, swap delegation, resolution
- **Gate**: `forge test --match-contract AquarelaHookTest` passes

### Phase 4: GaussianCurve (pm-AMM)
- [ ] Implements IPricingCurve
- [ ] pm-AMM invariant: (y-x)Phi((y-x)/(L*b)) + L*b*phi((y-x)/(L*b)) - y = 0
- [ ] Dynamic liquidity: b = sigma * sqrt(T - t)
- [ ] Newton's method solver for invariant (3-5 iterations)
- [ ] curveParams: sigma (uint128) + expiry (uint64) packed in bytes32
- [ ] Tests: invariant preservation, price direction, time decay, boundary, fuzz
- **Gate**: `forge test --match-contract GaussianCurveTest` passes

### Phase 5: GeometricLDF
- [ ] Implements ILDF
- [ ] Geometric density: (1-alpha) * alpha^|tick - currentTick|
- [ ] Closed-form cumulative via geometric series
- [ ] ldfParams: alpha (uint128 WAD) packed in bytes32
- [ ] Tests: normalization, peak at current price, symmetry, alpha sensitivity, fuzz
- **Gate**: `forge test --match-contract GeometricLDFTest` passes

### Phase 6: PassthroughCurve
- [ ] Implements IPricingCurve with usesLDF() = true
- [ ] Standard x*y=k math weighted by LDF density
- [ ] Steps through price ranges where LDF density changes
- [ ] Tests: matches CPMM with uniform LDF, more impact with concentrated LDF, conservation
- **Gate**: `forge test --match-contract PassthroughCurveTest` passes

### Phase 7: LP Management
- [ ] addLiquidity() / removeLiquidity() on the hook
- [ ] withdrawResolved() for prediction market outcomes
- [ ] Internal share accounting (mapping-based, no ERC20 for MVP)
- [ ] Interacts with v4 via unlock callback pattern
- [ ] Tests: full LP lifecycle, resolved market withdrawals
- **Gate**: LP tests pass

### Phase 8: Integration + Fuzz Tests
- [ ] End-to-end: create pool -> add liquidity -> swap -> verify balances (both curve types)
- [ ] Multi-swap sequences, multi-pool on same hook
- [ ] Resolve prediction market -> LP withdrawal at outcome price
- [ ] Fuzz: all math functions, swap conservation, LP accounting
- **Gate**: `forge test` all pass, `forge test --fuzz-runs 10000` clean

### Phase 9: Deploy Scripts
- [ ] DeployAquarela.s.sol: deploy curves, LDFs, mine hook address (CREATE2), deploy hook
- [ ] CreatePool.s.sol: example pool creation for both curve types
- [ ] Target: Sepolia or Base Sepolia
- **Gate**: `forge script --dry-run` succeeds

### Phase 10: Frontend
- [ ] Install wagmi, viem, @tanstack/react-query
- [ ] Web3 provider setup (WagmiProvider, chain config)
- [ ] Pool creation page: curve/LDF selector, params, deploy
- [ ] Swap page: pool selector, token amounts, quote, execute
- [ ] Pool detail page: config, price, LP positions, resolve/withdraw
- **Gate**: `pnpm build` succeeds, pages render

### Phase 11: Testnet Deploy + Verify
- [ ] Deploy contracts to testnet
- [ ] Verify on block explorer
- [ ] Create test pools (both types)
- [ ] Execute test swaps through frontend
- [ ] Update frontend with deployed addresses

## Dependency Graph

```
Phase 0 -> Phase 1 -> Phase 2 -> Phase 3
                                    |
                         +----------+----------+
                         |          |          |
                      Phase 4   Phase 5   Phase 6 (needs 5)
                         |          |          |
                         +----------+----------+
                                    |
                                 Phase 7
                                    |
                                 Phase 8
                                    |
                              Phase 9 + 10 (parallel)
                                    |
                                 Phase 11
```

## Key Files

- `contracts/src/AquarelaHook.sol` — singleton hook, central router
- `contracts/src/interfaces/IPricingCurve.sol` — curve interface
- `contracts/src/interfaces/ILDF.sol` — LDF interface
- `contracts/src/libraries/GaussianMath.sol` — CDF/PDF approximation
- `contracts/src/libraries/ProbabilityMath.sol` — probability <-> sqrtPriceX96
- `contracts/src/curves/GaussianCurve.sol` — pm-AMM implementation
- `contracts/src/curves/PassthroughCurve.sol` — CPMM + LDF
- `contracts/src/ldfs/GeometricLDF.sol` — geometric liquidity distribution

## Risk Areas

1. **Contract size**: Monitor with `forge build --sizes`. Extract to AquarelaHookLogic library early.
2. **Hook address mining**: v4 requires specific address bits. Use HookMiner for tests, CREATE2 salt mining for deploy.
3. **GaussianMath precision**: CDF approx has ~75 wei error in WAD. Newton solver tolerance at 1e12.
4. **v4 API stability**: Pin v4-core/periphery to specific commits.
5. **PassthroughCurve stepping**: Coarse grid (100-tick steps) for MVP, optimize later.

## Verification

1. `forge build` — compiles clean
2. `forge test` — all unit + integration tests pass
3. `forge test --fuzz-runs 10000` — fuzz tests clean
4. `forge build --sizes` — no contract exceeds 24KB
5. `forge script --dry-run` — deploy scripts succeed
6. `pnpm build` (frontend) — builds clean
7. Manual testnet testing through frontend
