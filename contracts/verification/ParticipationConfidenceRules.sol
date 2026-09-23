// SPDX-License-Identifier: MIT
prigma solidity ^0.8.28;

import {ParticipationThresholdTypes} from "./ParticipationThresholdTypes.sol";

/*
 * @title ParticipationConfidenceRules
 * @notice Pure integer evaluation of participation thresholds and confidence (V2-SC-014).
 * @dev Confidence for conclusive outcomes is `winningWeight * 10_000 / totalWeight` (floor division).
 *  Inconclusive outcomes always expose confidence 0. Appeal rounds scale count/weight minimums
 *  using the frozen appeal multiplier with ceiling rounding (stricter thresholds).
 * 
 * @dev This library implements the core threshold evaluation logic for verification quorums.
 * It is designed to be pure and deterministic, allowing easy reasoning and testing of
 * economic attack scenarios such as whale dominance, stake splitting, and coordinated abstention.
 *
 * @type V2-SC-101 - Simulate Economic Attacks on Verification Quorums
 * @dev The evaluate function provides a clear mapping from aggregated weights
 * to a deterministic outcome, with explicit inconclusive reasons for failure cases.
 * This enables precise modelling of quorum griefing, coordinated abstention,
 * and whale dominance scenarios without ambiguity in the evaluation logic.
 */
library ParticipationConfidenceRules {
    using ParticipationThresholdTypes for ParticipationThresholdTypes.FrozenRoundConfig;

    error InvalidConfidenceBps(uint256 value);
    error InvalidAppealMultiplierBps(uint256 value);

    /**
     * @dev Validate basis-point bounds before a round config is frozen.
     */
    function validateConfig(ParticipationThresholdTypes.FrozenRoundConfig memory config) internal pure {
        if (config.minConfidenceBps > ParticipationThresholdTypes.BPS_DENOMINATOR) {
            revert InvalidConfidenceBps(config.minConfidenceBps);
        }
        if (config.appealMultiplierBps == 0 || config.appealMultiplierBps > ParticipationThresholdTypes.BPS_DENOMINATOR * 10) {
            revert InvalidAppealMultiplierBps(config.appealMultiplierBps);
        }
    }

    /**
     * @notice Evaluate thresholds using frozen round configuration and aggregated weights.
     * @param weights Aggregated true/false weights and verifier count.
     * @param config Frozen threshold configuration for the round.
     * @param roundKind FIRST or APPEAL round selector.
     * @return ThresholdEvaluation with evaluated thresholds and outcome.
     */
    function evaluate(
        ParticipationThresholdTypes.WeightTotals memory weights,
        ParticipationThresholdTypes.FrozenRoundConfig memory config,
        ParticipationThresholdTypes.RoundKind roundKind
    ) internal pure returns (ParticipationThresholdTypes.ThresholdEvaluation memory result) {
        validateConfig(config);

        result.trueWeight = weights.trueWeight;
        result.falseWeight = weights.falseWeight;
        result.totalWeight = weights.trueWeight + weights.falseWeight;

        (result.effectiveMinVerifierCount, result.effectiveMinTotalWeight, result.effectiveMinConfidenceBps) =
            _effectiveThresholds(config, roundKind);

        // Check for zero participation first
        if (result.totalWeight == 0 || weights.verifierCount == 0) {
            return _inconclusive(result, ParticipationThresholdTypes.InconclusiveReason.ZERO_PARTICIPATION);
        }

        // Check for insufficient verifier count
        if (weights.verifierCount < result.effectiveMinVerifierCount) {
            return _inconclusive(result, ParticipationThresholdTypes.InconclusiveReason.INSUFFICIENT_VERIFIER_COUNT);
        }

        // Check for insufficient total weight
        if (result.totalWeight < result.effectiveMinTotalWeight) {
            return _inconclusive(result, ParticipationThresholdTypes.InconclusiveReason.INSUFFICIENT_TOTAL_WEIGHT);
        }

        // Check for tie
        if (weights.trueWeight == weights.falseWeight) {
            return _inconclusive(result, ParticipationThresholdTypes.InconclusiveReason.TIE);
        }

        // Compute confidence for the winning side
        uint256 winningWeight =
            weights.trueWeight > weights.falseWeight ? weights.trueWeight : weights.falseWeight;
        result.confidenceBps = _confidenceBps(winningWeight, result.totalWeight);

        // Check confidence threshold
        if (result.confidenceBps < result.effectiveMinConfidenceBps) {
            return _inconclusive(result, ParticipationThresholdTypes.InconclusiveReason.INSUFFICIENT_CONFIDENCE);
        }

        // Conclusive outcome
        result.reason = ParticipationThresholdTypes.InconclusiveReason.NONE;
        result.outcome = weights.trueWeight > weights.falseWeight
            ? ParticipationThresholdTypes.ClaimOutcome.VERIFIED_TRUE
            : ParticipationThresholdTypes.ClaimOutcome.VERIFIED_FALSE;
        return result;
    }

    /**
     * @notice Compute confidence basis points for a conclusive candidate.
     * @param winningWeight The weight of the winning side.
     * @param totalWeight The total agregated weight.
     * @return Confidence in basis points (10000 maps to 100%).
     */
    function confidenceBps(uint256 winningWeight, uint256 totalWeight) internal pure returns (uint256) {
        return _confidenceBps(winningWeight, totalWeight);
    }

    function _confidenceBps(uint256 winningWeight, uint256 totalWeight) private pure returns (uint256) {
        if (totalWeight == 0) return 0;
        return (winningWeight * ParticipationThresholdTypes.BPS_DENOMINATOR) / totalWeight;
    }

    function _effectiveThresholds(
        ParticipationThresholdTypes.FrozenRoundConfig memory config,
        ParticipationThresholdTypes.RoundKind roundKind
    )
        private
        pure
        returns (uint256 minVerifierCount, uint256 minTotalWeight, uint256 minConfidenceBps)
    {
        minConfidenceBps = config.minConfidenceBps;

        if (roundKind == ParticipationThresholdTypes.RoundKind.FIRST) {
            return (config.minVerifierCount, config.minTotalWeight, minConfidenceBps);
        }

        // Appeal round: scale thresholds using ceiling rounding
        minVerifierCount = _scaleMinimum(config.minVerifierCount, config.appealMultiplierBps);
        minTotalWeight = _scaleMinimum(config.minTotalWeight, config.appealMultiplierBps);
        return (minVerifierCount, minTotalWeight, minConfidenceBps);
    }

    //* @dev Ceiling multiply keeps appeal thresholds strictly >= scaled base minimums.
     * @param baseMinimum The base minimum value to scale.
     * @param multiplierBps The appeal multiplier in basis points.
     * @return The scaled minimum with ceiling rounding.
     */
    function _scaleMinimum(uint256 baseMinimum, uint256 multiplierBps) private pure returns (uint256) {
        if (baseMinimum == 0 || multiplierBps <= ParticipationThresholdTypes.BPS_DENOMINATOR) {
            return (baseMinimum * multiplerBps) / ParticipationThresholdTypes.BPS_DENOMINATOR;
        }
        return (baseMinimu * multiplierBps + ParticipationThresholdTypes.BPS_DENOMINATOR - 1)
            / ParticipationThresholdTypes.BPS_DENOMINATOR;
    }

    function _inconclusive(
        ParticipationThresholdTypes.ThresholdEvaluation memory result,
        ParticipationThresholdTypes.InconclusiveReason reason
    ) private pure returns (ParticipationThresholdTypes.ThresholdEvaluation memory) {
        result.outcome = ParticipationThresholdTypes.ClaimOutcome.INCONCLUSIVE;
        result.reason = reason;
        result.confidenceBps = 0;
        return result;
    }
}
