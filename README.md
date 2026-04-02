<img width="1584" height="672" alt="image" src="https://github.com/user-attachments/assets/1ef64c75-da27-44eb-b766-221c83d3a1f3" />

Pluggable price curves for Uniswap v4.

## What

A v4 hook system with two layers of modularity:

1. **Curves**: replace v4's swap math entirely (e.g. pm-AMM Gaussian curve, StableSwap)
2. **LDFs**:  shape liquidity distribution within standard CPMM (à la Bunni)

One hook. Any curve. Any distribution. Deploy via factory.

## MVP

- `AquarelaHook`: curve-agnostic v4 hook
- `GaussianCurve`: pm-AMM for prediction markets (Paradigm, Nov 2024)
- `GeometricLDF`: standard CPMM with shaped liquidity
- `CurveFactory`: pick curve, pick LDF, set params, deploy

## Why

PCPartPicker for AMMs.
