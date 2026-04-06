# Aquarela MVP Build Plan

## Architecture

- Curve-as-hook — each curve type is its own v4 hook contract
- GaussianHook for prediction markets, PassthroughHook for standard CPMM + LDF
- BaseAquarelaHook base contract for shared logic (validation, fee handling)
- Shared math/utility libraries (GaussianMath, ProbabilityMath, etc.)
- LDFs are external contracts implementing `ILDF`, called by hooks that support them
- Each hook owns its own per-pool config struct, state, and permissions

## Open Questions — Recommendations

1. **Normal CDF in Solidity**: Abramowitz & Stegun polynomial approximation (|error| < 7.5e-8). Pure math, no storage, fuzz-testable.
2. **Probability to sqrtPriceX96**: `sqrtPriceX96 = sqrt(p / (1-p)) * 2^96`. Reverse: `p = sqrtPrice^2 / (2^192 + sqrtPrice^2)`.
3. **Resolution mechanism**: Trusted resolver address per pool for MVP. Oracle integration in v2.

## Implementation Phases

### Phase 0: Foundation [DONE]
- [x] Install v4-core, v4-periphery, solady via forge
- [x] Configure foundry.toml (solc 0.8.26, cancun EVM, remappings)
- [x] Create directory structure
- [x] Delete Counter placeholder
- **Gate**: `forge build` compiles

### Phase 1: Types + Interfaces
- [ ] `ILDF.sol` — liquidityDensity(), cumulativeLiquidity(), name()
- [ ] `BaseAquarelaHook.sol` — shared hook base (onlyPoolManager, common LP logic)
- [ ] GaussianHook config struct (sigma, expiry, resolver, totalLiquidity, etc.)
- [ ] PassthroughHook config struct (ldf address, ldfParams, totalLiquidity, etc.)
- **Gate**: `forge build` compiles

### Phase 2: Math Libraries
- [ ] `GaussianMath.sol` — cdf(), pdf(), inverseCdf() in WAD fixed-point
- [ ] `ProbabilityMath.sol` — probabilityToSqrtPriceX96(), sqrtPriceX96ToProbability()
- [ ] Tests: known values, symmetry, monotonicity, roundtrip, fuzz
- **Gate**: `forge test --match-path "test/libraries/*"` passes

### Phase 3: GaussianHook (pm-AMM)
- [ ] Inherits BaseAquarelaHook
- [ ] Own per-pool config: sigma, expiry, resolver, resolved, outcome, totalLiquidity
- [ ] createPool() stores config + calls poolManager.initialize()
- [ ] beforeSwap implements pm-AMM invariant directly
- [ ] pm-AMM invariant: (y-x)Phi((y-x)/(L*b)) + L*b*phi((y-x)/(L*b)) - y = 0
- [ ] Dynamic liquidity: b = sigma * sqrt(T - t)
- [ ] Newton's method solver (3-5 iterations)
- [ ] resolvePool() — trusted resolver sets outcome
- [ ] addLiquidity() / removeLiquidity() / withdrawResolved()
- [ ] Tests: invariant preservation, price direction, time decay, resolution, LP lifecycle, fuzz
- **Gate**: `forge test --match-contract GaussianHookTest` passes

### Phase 4: GeometricLDF
- [ ] Implements ILDF
- [ ] Geometric density: (1-alpha) * alpha^|tick - currentTick|
- [ ] Closed-form cumulative via geometric series
- [ ] ldfParams: alpha (uint128 WAD) packed in bytes32
- [ ] Tests: normalization, peak at current price, symmetry, alpha sensitivity, fuzz
- **Gate**: `forge test --match-contract GeometricLDFTest` passes

### Phase 5: PassthroughHook (CPMM + LDF)
- [ ] Inherits BaseAquarelaHook
- [ ] Own per-pool config: ldf address, ldfParams, totalLiquidity
- [ ] createPool() stores config + calls poolManager.initialize()
- [ ] beforeSwap uses standard x*y=k math weighted by LDF density
- [ ] Steps through price ranges where LDF density changes
- [ ] addLiquidity() / removeLiquidity()
- [ ] Tests: matches CPMM with uniform LDF, more impact with concentrated LDF, conservation, LP lifecycle
- **Gate**: `forge test --match-contract PassthroughHookTest` passes

### Phase 6: Integration + Fuzz Tests
- [ ] End-to-end: create pool -> add liquidity -> swap -> verify balances (both hook types)
- [ ] Multi-swap sequences
- [ ] Resolve prediction market -> LP withdrawal at outcome price
- [ ] Fuzz: all math functions, swap conservation, LP accounting
- **Gate**: `forge test` all pass, `forge test --fuzz-runs 10000` clean

### Phase 7: Deploy Scripts
- [ ] DeployAquarela.s.sol: deploy both hooks (mine addresses for correct flag bits), deploy GeometricLDF
- [ ] CreatePool.s.sol: example pool creation for both hook types
- [ ] Target: Sepolia or Base Sepolia
- **Gate**: `forge script --dry-run` succeeds

### Phase 8: Frontend
- [ ] Install wagmi, viem, @tanstack/react-query
- [ ] Web3 provider setup (WagmiProvider, chain config)
- [ ] Pool creation page: hook type selector, LDF selector (for Passthrough), params, deploy
- [ ] Swap page: pool selector, token amounts, quote, execute
- [ ] Pool detail page: config, price, LP positions, resolve/withdraw
- **Gate**: `pnpm build` succeeds, pages render

### Phase 9: Testnet Deploy + Verify
- [ ] Deploy contracts to testnet
- [ ] Verify on block explorer
- [ ] Create test pools (both types)
- [ ] Execute test swaps through frontend
- [ ] Update frontend with deployed addresses

## Dependency Graph

```
Phase 0 -> Phase 1 -> Phase 2
                         |
                   +-----+-----+
                   |           |
                Phase 3     Phase 4 -> Phase 5
                   |           |
                   +-----+-----+
                         |
                      Phase 6
                         |
                    Phase 7 + 8 (parallel)
                         |
                      Phase 9
```

## Key Files

- `contracts/src/hooks/BaseAquarelaHook.sol` — shared hook base
- `contracts/src/hooks/GaussianHook.sol` — pm-AMM prediction market hook
- `contracts/src/hooks/PassthroughHook.sol` — CPMM + LDF hook
- `contracts/src/interfaces/ILDF.sol` — LDF interface
- `contracts/src/libraries/GaussianMath.sol` — CDF/PDF approximation
- `contracts/src/libraries/ProbabilityMath.sol` — probability <-> sqrtPriceX96
- `contracts/src/ldfs/GeometricLDF.sol` — geometric liquidity distribution

## Risk Areas

1. **Contract size**: Monitor with `forge build --sizes`. Extract heavy logic to libraries if needed.
2. **Hook address mining**: v4 requires specific address bits per hook. Use HookMiner for tests, CREATE2 salt mining for deploy. Need to mine separately for each hook.
3. **GaussianMath precision**: CDF approx has ~75 wei error in WAD. Newton solver tolerance at 1e12.
4. **v4 API stability**: Pin v4-core/periphery to specific commits.
5. **PassthroughHook stepping**: Coarse grid (100-tick steps) for MVP, optimize later.

## Verification

1. `forge build` — compiles clean
2. `forge test` — all unit + integration tests pass
3. `forge test --fuzz-runs 10000` — fuzz tests clean
4. `forge build --sizes` — no contract exceeds 24KB
5. `forge script --dry-run` — deploy scripts succeed
6. `pnpm build` (frontend) — builds clean
7. Manual testnet testing through frontend
