// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ParticipationThresholdTypes
 * @notice Shared V2 types for participation threshold and confidence evaluation (V2-SC-014).
 */
library ParticipationThresholdTypes {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    enum RoundKind {
        FIRST,
        APPEAL
    }

    enum InconclusiveReason {
        NONE,
        ZERO_PARTICIPATION,
        INSUFFICIENT_VERIFIER_COUNT,
        INSUFFICIENT_TOTAL_WEIGHT,
        INSUFFICIENT_CONFIDENCE,
        TIE
    }

    enum ClaimOutcome {
        VERIFIED_TRUE,
        VERIFIED_FALSE,
        INCONCLUSIVE
    }

    /// @notice Threshold parameters frozen when a round opens.
    struct FrozenRoundConfig {
        uint256 configVersion;
        uint256 minVerifierCount;
        uint256 minTotalWeight;
        uint256 minConfidenceBps;
        uint256 appealMultiplierBps;
    }

    /// @notice Weight totals supplied by the deterministic aggregation engine (V2-SC-013).
    struct WeightTotals {
        uint256 trueWeight;
        uint256 falseWeight;
        uint256 verifierCount;
    }

    /// @notice Canonical threshold evaluation output for projection and settlement.
    struct ThresholdEvaluation {
        ClaimOutcome outcome;
        InconclusiveReason reason;
        uint256 trueWeight;
        uint256 falseWeight;
        uint256 totalWeight;
        uint256 confidenceBps;
        uint256 effectiveMinVerifierCount;
        uint256 effectiveMinTotalWeight;
        uint256 effectiveMinConfidenceBps;
    }
}
