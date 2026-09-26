// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAggregation} from "./interfaces/IAggregation.sol";
import {IVerification} from "./interfaces/IVerification.sol";
import {IConfiguration} from "./interfaces/IConfiguration.sol";
import {IClaims} from "./interfaces/IClaims.sol";
import {IModuleRegistry} from "./interfaces/IModuleRegistry.sol";
import {IV2Types} from "./interfaces/IV2Types.sol";
import {IV2Module} from "./interfaces/IV2Module.sol";
import {V2Errors} from "./libraries/V2Errors.sol";

/// @title Aggregation
/// @notice V2-SC-056 Aggregation Tie, Quorum, and Rounding Semantics
contract Aggregation is IAggregation {
    IModuleRegistry public immutable registry;

    struct OutcomeData {
        bool finalized;
        bool accepted;
        uint256 supportingWeight;
        uint256 opposingWeight;
    }

    mapping(uint256 => OutcomeData) private _outcomes;

    constructor(address _registry) {
        if (_registry == address(0)) revert V2Errors.ZeroAddress();
        registry = IModuleRegistry(_registry);
    }

    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IAggregation).interfaceId || interfaceId == type(IV2Module).interfaceId;
    }

    function finalizeAggregation(uint256 claimId) external override {
        if (_outcomes[claimId].finalized) revert V2Errors.SettlementAlreadyFinalized(claimId, 0);

        IConfiguration config = IConfiguration(registry.getModule(keccak256("CONFIGURATION")));
        IVerification verifier = IVerification(registry.getModule(keccak256("VERIFICATION")));
        
        uint256 versionId = config.getLatestVersion();
        IConfiguration.ParameterSet memory params = config.getParameterSet(versionId);

        uint256 supportingWeight = 0;
        uint256 opposingWeight = 0;
        uint256 cursor = 0;
        uint256 limit = 100;

        while (true) {
            (uint256[] memory ids, uint256 nextCursor) = verifier.claimVerifications(claimId, cursor, limit);
            
            for (uint256 i = 0; i < ids.length; i++) {
                IV2Types.Verification memory v = verifier.getVerification(ids[i]);
                uint256 weight = v.stake > params.weightCap ? params.weightCap : v.stake;
                
                if (v.supportsClaim) {
                    supportingWeight += weight;
                } else {
                    opposingWeight += weight;
                }
            }
            
            if (nextCursor == cursor || ids.length == 0) break;
            cursor = nextCursor;
        }

        uint256 totalWeight = supportingWeight + opposingWeight;
        bool accepted = false;

        if (totalWeight >= params.participationThreshold && totalWeight > 0) {
            // Remainder allocation & Rounding semantics: Round UP for required support
            uint256 requiredSupport = (totalWeight * params.confidenceThreshold + 9999) / 10000;
            
            // Tie behaviour: If exactly equal to required support, is it accepted? 
            // In most systems, it must strictly exceed if 50/50 tie, but if threshold is exactly met, it's accepted.
            if (supportingWeight >= requiredSupport) {
                // If it's a tie (supporting == opposing) and threshold is 50%, we reject it (fail-closed)
                if (supportingWeight == opposingWeight && params.confidenceThreshold == 5000) {
                    accepted = false;
                } else {
                    accepted = true;
                }
            }
        }

        _outcomes[claimId] = OutcomeData({
            finalized: true,
            accepted: accepted,
            supportingWeight: supportingWeight,
            opposingWeight: opposingWeight
        });

        emit AggregationFinalized(claimId, accepted, supportingWeight, opposingWeight);
    }

    function outcome(uint256 claimId) external view override returns (bool finalized, bool accepted, uint256 supportingWeight, uint256 opposingWeight) {
        OutcomeData memory data = _outcomes[claimId];
        return (data.finalized, data.accepted, data.supportingWeight, data.opposingWeight);
    }
}
