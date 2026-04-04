<img width="1584" height="672" alt="image" src="https://github.com/user-attachments/assets/1ef64c75-da27-44eb-b766-221c83d3a1f3" />
Aquarela

Pluggable price curves and liquidity shaping for Uniswap v4

---

What

A v4 hook system with two layers of modularity:

1. Pricing Curves — Replace v4's swap math with custom invariants
2. LDFs — Shape liquidity distribution within a curve

One hook. Any curve. Any distribution. PCPartPicker for AMMs.

---

Architecture

Singleton hook pattern. One AquarelaHook deployed once, delegates to external curve and LDF contracts per pool. Pool creation lives on the hook — no separate factory.

```
AquarelaHook (singleton v4 hook — routing, LP management, fees)
    │
    ├── IPricingCurve (external contracts — pure swap math)
    │     ├── GaussianCurve (pm-AMM for prediction markets)
    │     └── PassthroughCurve (native v4 CPMM)
    │
    └── ILDF (external contracts — liquidity distribution)
          └── GeometricLDF (concentrates liquidity around current price)
```

Why singleton:
- Shared logic (validation, fees, LP, events) lives in one place
- Curves and LDFs are pure math — easy to add, test, audit independently
- Bytecode stays under 24KB limit — extract libraries as hook grows
- Proven at production scale by Bunni v2

If a future curve needs different v4 hook permissions, deploy it as its own hook. Curves are external contracts — they work with either the singleton or a dedicated hook. Same interface.

---

Contracts

Core:
- AquarelaHook — singleton v4 hook, curve-agnostic routing, pool creation
- IPricingCurve — interface all curves implement
- ILDF — interface all LDFs implement

MVP Curves:
- GaussianCurve — pm-AMM for prediction markets (Paradigm paper)
- PassthroughCurve — delegates to v4 native CPMM, supports LDF plugins

MVP LDF:
- GeometricLDF — concentrates liquidity around current price

Future:
- StableSwapCurve, more LDFs (uniform, buy-the-dip, etc.)
- Fee strategy contracts, oracle integrations as pluggable components

---

How Swaps Work

1. beforeSwap fires on AquarelaHook
2. Hook reads pool config (curve address, LDF address, params)
3. Hook calls the curve contract for swap math
4. Curve calls its LDF (if any) for liquidity distribution
5. Hook returns BeforeSwapDelta with computed amounts
6. v4 uses the delta, skips internal CPMM
7. v4 handles token accounting only

Uses BEFORE_SWAP_RETURNS_DELTA permission.

---

GaussianCurve Params

| Param  | Description                               |
| ------ | ----------------------------------------- |
| sigma  | Spread — how much trading moves the price |
| expiry | Resolution timestamp — market closes here |

Liquidity shrinks as expiry approaches: b(t) = sigma * sqrt(T - t)

---

Security Flags

- Rounding direction: always round AGAINST withdrawer (Bunni exploit)
- onlyPoolManager on all hook callbacks
- Pool key validation
- Pricing curve and LDF contracts must be stateless (pure math)
- Minimum withdrawal thresholds to block dust attacks

---

MVP Scope (10 weeks — UHI)

In:
- AquarelaHook (singleton)
- GaussianCurve
- PassthroughCurve + GeometricLDF
- Pool creation on the hook
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

v2: More LDFs, StableSwapCurve, fee strategy plugins, mainnet + audit

v3: am-AMM for LVR recapture, auto-rebalancing, multi-outcome markets, parlay contracts

---

Open Questions

1. Normal CDF in Solidity — polynomial approximation vs lookup table?
2. Mapping [0,1] probability to sqrtPriceX96 tick space?
3. Resolution mechanism — external oracle or trusted resolver for MVP?
