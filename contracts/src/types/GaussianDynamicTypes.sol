// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct GaussianDynamicPoolConfig {
    uint128 sigma;
    uint64 expiry;
    address resolver;
    bool resolved;
    uint8 outcome;
    uint128 totalLiquidity;
}
