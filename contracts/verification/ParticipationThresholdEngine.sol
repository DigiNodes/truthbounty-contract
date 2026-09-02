// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ParticipationThresholdTypes} from "./ParticipationThresholdTypes.sol";
import {ParticipationConfidenceRules} from "./ParticipationConfidenceRules.sol";
import {FrozenRoundConfigStore} from "./FrozenRoundConfigStore.sol";

/**
 * @title ParticipationThresholdEngine
 * @notice V2-SC-014 engine applying frozen round thresholds to aggregated weights.
 */
contract ParticipationThresholdEngine is AccessControl {
    bytes32 public constant EVALUATOR_ROLE = keccak256("EVALUATOR_ROLE");

    FrozenRoundConfigStore public immutable configStore;

    mapping(bytes32 => ParticipationThresholdTypes.ThresholdEvaluation) private _evaluations;
    mapping(bytes32 => bool) private _evaluated;

    event ThresholdEvaluated(
        bytes32 indexed roundId,
        uint256 indexed claimId,
        ParticipationThresholdTypes.RoundKind roundKind,
        ParticipationThresholdTypes.ClaimOutcome outcome,
        ParticipationThresholdTypes.InconclusiveReason reason,
        uint256 confidenceBps
    );

    error AlreadyEvaluated(bytes32 roundId);
    error RoundNotFrozen(bytes32 roundId);

    constructor(address admin, FrozenRoundConfigStore store) {
        configStore = store;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EVALUATOR_ROLE, admin);
    }

    function evaluateRound(
        uint256 claimId,
        ParticipationThresholdTypes.RoundKind roundKind,
        ParticipationThresholdTypes.WeightTotals calldata weights
    ) external onlyRole(EVALUATOR_ROLE) returns (ParticipationThresholdTypes.ThresholdEvaluation memory evaluation) {
        bytes32 id = configStore.roundId(claimId, roundKind);
        if (!configStore.isRoundFrozen(id)) revert RoundNotFrozen(id);
        if (_evaluated[id]) revert AlreadyEvaluated(id);

        ParticipationThresholdTypes.FrozenRoundConfig memory config = configStore.getFrozenConfig(id);
        evaluation = ParticipationConfidenceRules.evaluate(weights, config, roundKind);

        _evaluations[id] = evaluation;
        _evaluated[id] = true;

        emit ThresholdEvaluated(id, claimId, roundKind, evaluation.outcome, evaluation.reason, evaluation.confidenceBps);
    }

    function previewEvaluation(
        ParticipationThresholdTypes.WeightTotals calldata weights,
        ParticipationThresholdTypes.FrozenRoundConfig calldata config,
        ParticipationThresholdTypes.RoundKind roundKind
    ) external pure returns (ParticipationThresholdTypes.ThresholdEvaluation memory) {
        return ParticipationConfidenceRules.evaluate(weights, config, roundKind);
    }

    function getEvaluation(bytes32 roundId)
        external
        view
        returns (ParticipationThresholdTypes.ThresholdEvaluation memory)
    {
        return _evaluations[roundId];
    }

    function isEvaluated(bytes32 roundId) external view returns (bool) {
        return _evaluated[roundId];
    }
}
