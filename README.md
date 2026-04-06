<img width="1584" height="672" alt="image" src="https://github.com/user-attachments/assets/1ef64c75-da27-44eb-b766-221c83d3a1f3" />
Aquarela

Pluggable price curves and liquidity shaping for Uniswap v4

---

What

A v4 hook system with two layers of modularity:

1. Curve Hooks — Each curve type is its own v4 hook, replacing swap math entirely
2. LDFs — Shape liquidity distribution within a curve hook

Any curve. Any distribution. PCPartPicker for AMMs.

---

Architecture

Curve-as-hook pattern. Each curve type is its own v4 hook contract with its own state, config, and permissions. Shared logic lives in a base contract and libraries. LDFs are external contracts called by hooks that support them.

```
BaseAquarelaHook (shared logic — validation, fees)
    │
    ├── GaussianHook (pm-AMM for prediction markets)
    │     └── owns: sigma, expiry, resolver, totalLiquidity
    │
    └── PassthroughHook (native v4 CPMM + LDF)
          ├── owns: ldf address, ldfParams, totalLiquidity
          └── ILDF (external contracts — liquidity distribution)
                └── GeometricLDF (concentrates liquidity around current price)
```

Why curve-as-hook:
- Each hook owns its own config struct — no shared struct gymnastics
- Different curves can use different v4 hook permissions
- Clean separation — prediction market logic stays in GaussianHook, CPMM logic stays in PassthroughHook
- Shared logic (validation, fees) lives in BaseAquarelaHook base contract
- Shared math lives in libraries (GaussianMath, ProbabilityMath)

---

Contracts

Core:
- BaseAquarelaHook — shared hook base (onlyPoolManager, common logic)
- ILDF — interface all LDFs implement

MVP Hooks:
- GaussianHook — pm-AMM for prediction markets (Paradigm paper)
- PassthroughHook — native v4 CPMM with LDF plugins

MVP LDF:
- GeometricLDF — concentrates liquidity around current price

Future:
- StableSwapHook, more LDFs (uniform, buy-the-dip, etc.)
- Fee strategy contracts, oracle integrations

---

How Swaps Work

1. beforeSwap fires on the pool's hook (GaussianHook or PassthroughHook)
2. Hook computes swap math using its own invariant and state
3. For PassthroughHook: queries LDF for liquidity distribution
4. Hook returns BeforeSwapDelta with computed amounts
5. v4 uses the delta, skips internal CPMM
6. v4 handles token accounting only

Uses BEFORE_SWAP_RETURNS_DELTA permission.

---

GaussianHook Params

| Param    | Description                               |
| -------- | ----------------------------------------- |
| sigma    | Spread — how much trading moves the price |
| expiry   | Resolution timestamp — market closes here |
| resolver | Address authorized to resolve the market  |

Liquidity shrinks as expiry approaches: b(t) = sigma * sqrt(T - t)

---

Security Flags

- Rounding direction: always round AGAINST withdrawer (Bunni exploit)
- onlyPoolManager on all hook callbacks
- Pool key validation
- LDF contracts must be stateless (pure math)
- Minimum withdrawal thresholds to block dust attacks

---

MVP Scope (10 weeks — UHI)

In:
- GaussianHook
- PassthroughHook + GeometricLDF
- BaseAquarelaHook
- Basic frontend (Next.js + wagmi)
- Testnet deployment

Out:
- Audit
- Mainnet
- Auto-rebalancing
- am-AMM
- Multi-outcome markets

---

Roadmap

v2: More LDFs, StableSwapHook, fee strategy plugins, mainnet + audit

v3: am-AMM for LVR recapture, auto-rebalancing, multi-outcome markets, parlay contracts

---

Open Questions

1. Normal CDF in Solidity — polynomial approximation (Abramowitz & Stegun)
2. Mapping [0,1] probability to sqrtPriceX96 tick space — sqrt(p/(1-p)) * 2^96
3. Resolution mechanism — trusted resolver for MVP, oracle integration in v2
