// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum ClaimOutcome {
    VERIFIED_TRUE,
    VERIFIED_FALSE,
    INCONCLUSIVE
}

struct AggregationResult {
    ClaimOutcome outcome;
    uint256 trueWeight;
    uint256 falseWeight;
    uint256 totalWeight;
    uint256 confidence;
}

interface IVerificationSource {
    function getClaimVoterCount(uint256 claimId) external view returns (uint256);
    function getClaimVoterAt(uint256 claimId, uint256 index) external view returns (address);
    function getVerificationWeight(uint256 claimId, address verifier) external view returns (uint256);
    function getVerificationSupport(uint256 claimId, address verifier) external view returns (bool);
    function getClaimVerificationWindowEnd(uint256 claimId) external view returns (uint256);
    function getClaimSubmitter(uint256 claimId) external view returns (address);
}

contract VerificationAggregation {
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;
    uint256 public constant MAX_VERIFICATION_COUNT = 200;

    uint256 public minVerificationCount;
    uint256 public minTotalStake;
    uint256 public minConfidenceBps;

    address public owner;

    IVerificationSource public verificationSource;

    mapping(uint256 => AggregationResult) private _aggregations;
    mapping(uint256 => bool) private _aggregated;

    event ClaimAggregated(uint256 indexed claimId, ClaimOutcome outcome, uint256 confidence);
    event ThresholdsUpdated(uint256 minVerificationCount, uint256 minTotalStake, uint256 minConfidenceBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotAggregated(uint256 claimId);
    error AlreadyAggregated(uint256 claimId);
    error InvalidSource();
    error ClaimNotExists(uint256 claimId);
    error VerificationWindowOpen(uint256 claimId);
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _verificationSource) {
        if (_verificationSource == address(0)) revert InvalidSource();
        verificationSource = IVerificationSource(_verificationSource);
        owner = msg.sender;
        minVerificationCount = 1;
    }

    function aggregateClaim(uint256 claimId) external returns (AggregationResult memory) {
        if (_aggregated[claimId]) revert AlreadyAggregated(claimId);

        address submitter = verificationSource.getClaimSubmitter(claimId);
        if (submitter == address(0)) revert ClaimNotExists(claimId);

        uint256 verificationWindowEnd = verificationSource.getClaimVerificationWindowEnd(claimId);
        if (block.timestamp < verificationWindowEnd) revert VerificationWindowOpen(claimId);

        (uint256 trueWeight, uint256 falseWeight, uint256 totalWeight) = _calculateWeights(claimId);

        uint256 voterCount = verificationSource.getClaimVoterCount(claimId);

        if (voterCount < minVerificationCount || totalWeight < minTotalStake) {
            AggregationResult memory insufficient = AggregationResult({
                outcome: ClaimOutcome.INCONCLUSIVE,
                trueWeight: trueWeight,
                falseWeight: falseWeight,
                totalWeight: totalWeight,
                confidence: 0
            });
            _aggregations[claimId] = insufficient;
            _aggregated[claimId] = true;
            emit ClaimAggregated(claimId, ClaimOutcome.INCONCLUSIVE, 0);
            return insufficient;
        }

        uint256 confidence = _calculateConfidence(trueWeight, falseWeight);
        ClaimOutcome outcome = _determineOutcome(trueWeight, falseWeight, confidence);

        AggregationResult memory aggregated = AggregationResult({
            outcome: outcome,
            trueWeight: trueWeight,
            falseWeight: falseWeight,
            totalWeight: totalWeight,
            confidence: confidence
        });

        _aggregations[claimId] = aggregated;
        _aggregated[claimId] = true;

        emit ClaimAggregated(claimId, outcome, confidence);

        return aggregated;
    }

    function calculateWeights(uint256 claimId) external view returns (uint256 trueWeight, uint256 falseWeight, uint256 totalWeight) {
        return _calculateWeights(claimId);
    }

    function calculateConfidence(uint256 trueWeight, uint256 falseWeight) external pure returns (uint256) {
        return _calculateConfidence(trueWeight, falseWeight);
    }

    function getAggregation(uint256 claimId) external view returns (AggregationResult memory) {
        if (!_aggregated[claimId]) revert NotAggregated(claimId);
        return _aggregations[claimId];
    }

    function isAggregated(uint256 claimId) external view returns (bool) {
        return _aggregated[claimId];
    }

    function setThresholds(uint256 _minVerificationCount, uint256 _minTotalStake, uint256 _minConfidenceBps) external onlyOwner {
        minVerificationCount = _minVerificationCount;
        minTotalStake = _minTotalStake;
        minConfidenceBps = _minConfidenceBps;
        emit ThresholdsUpdated(_minVerificationCount, _minTotalStake, _minConfidenceBps);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidSource();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function _calculateWeights(uint256 claimId) internal view returns (uint256 trueWeight, uint256 falseWeight, uint256 totalWeight) {
        uint256 count = verificationSource.getClaimVoterCount(claimId);

        for (uint256 i = 0; i < count; i++) {
            address voter = verificationSource.getClaimVoterAt(claimId, i);
            bool support = verificationSource.getVerificationSupport(claimId, voter);
            uint256 weight = verificationSource.getVerificationWeight(claimId, voter);

            if (support) {
                trueWeight += weight;
            } else {
                falseWeight += weight;
            }
        }

        totalWeight = trueWeight + falseWeight;
    }

    function _calculateConfidence(uint256 trueWeight, uint256 falseWeight) internal pure returns (uint256) {
        uint256 totalWeight = trueWeight + falseWeight;
        if (totalWeight == 0) return 0;
        uint256 winningWeight = trueWeight > falseWeight ? trueWeight : falseWeight;
        return (winningWeight * BASIS_POINTS_DENOMINATOR) / totalWeight;
    }

    function _determineOutcome(uint256 trueWeight, uint256 falseWeight, uint256 confidence) internal view returns (ClaimOutcome) {
        if (trueWeight == falseWeight && trueWeight > 0) {
            return ClaimOutcome.INCONCLUSIVE;
        }

        if (trueWeight == 0 && falseWeight == 0) {
            return ClaimOutcome.INCONCLUSIVE;
        }

        if (minConfidenceBps > 0 && confidence < minConfidenceBps) {
            return ClaimOutcome.INCONCLUSIVE;
        }

        return trueWeight > falseWeight ? ClaimOutcome.VERIFIED_TRUE : ClaimOutcome.VERIFIED_FALSE;
    }
}
