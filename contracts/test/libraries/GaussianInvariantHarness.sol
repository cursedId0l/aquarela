// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {GaussianInvariant} from "../../src/libraries/gaussian/GaussianInvariant.sol";

/// @notice External wrapper so tests can call internal library functions.
contract GaussianInvariantHarness {
    function solveForY(uint256 x, uint256 y, uint256 w) external pure returns (uint256) {
        return GaussianInvariant.solveForY(x, y, w);
    }

    function solveForX(uint256 y, uint256 x, uint256 w) external pure returns (uint256) {
        return GaussianInvariant.solveForX(y, x, w);
    }

    function computeW(uint128 sigma, uint64 expiry) external view returns (uint256) {
        return GaussianInvariant.computeW(sigma, expiry);
    }
}
