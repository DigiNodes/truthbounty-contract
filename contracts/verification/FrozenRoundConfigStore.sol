// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ParticipationThresholdTypes} from "./ParticipationThresholdTypes.sol";
import {ParticipationConfidenceRules} from "./ParticipationConfidenceRules.sol";

/**
 * @title FrozenRoundConfigStore
 * @notice Stores immutable threshold configuration per claim round (V2-SC-004 consumer).
 * @dev Once frozen, governance updates cannot affect an open round's thresholds.
 */
contract FrozenRoundConfigStore is AccessControl {
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    mapping(bytes32 => ParticipationThresholdTypes.FrozenRoundConfig) private _configs;
    mapping(bytes32 => bool) private _frozen;

    event RoundConfigFrozen(
        bytes32 indexed roundId,
        uint256 indexed claimId,
        ParticipationThresholdTypes.RoundKind roundKind,
        uint256 configVersion,
        uint256 minVerifierCount,
        uint256 minTotalWeight,
        uint256 minConfidenceBps,
        uint256 appealMultiplierBps
    );

    error RoundAlreadyFrozen(bytes32 roundId);
    error RoundNotFrozen(bytes32 roundId);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
    }

    function roundId(uint256 claimId, ParticipationThresholdTypes.RoundKind roundKind)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(claimId, roundKind));
    }

    function freezeRoundConfig(
        uint256 claimId,
        ParticipationThresholdTypes.RoundKind roundKind,
        ParticipationThresholdTypes.FrozenRoundConfig calldata config
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        ParticipationConfidenceRules.validateConfig(config);

        bytes32 id = roundId(claimId, roundKind);
        if (_frozen[id]) revert RoundAlreadyFrozen(id);

        _configs[id] = config;
        _frozen[id] = true;

        emit RoundConfigFrozen(
            id,
            claimId,
            roundKind,
            config.configVersion,
            config.minVerifierCount,
            config.minTotalWeight,
            config.minConfidenceBps,
            config.appealMultiplierBps
        );
    }

    function getFrozenConfig(bytes32 id)
        external
        view
        returns (ParticipationThresholdTypes.FrozenRoundConfig memory)
    {
        if (!_frozen[id]) revert RoundNotFrozen(id);
        return _configs[id];
    }

    function isRoundFrozen(bytes32 id) external view returns (bool) {
        return _frozen[id];
    }
}
