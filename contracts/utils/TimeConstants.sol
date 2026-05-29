// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TimeConstants {
    uint256 internal constant MIN_WINDOW = 5 minutes;

    uint256 internal constant EPOCH_GRANULARITY =
        1 minutes;
}