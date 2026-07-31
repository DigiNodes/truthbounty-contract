// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./governance/GovernanceOwnable.sol";
import "./IReputationOracle.sol";

contract ReputationDecay is GovernanceOwnable, IReputationOracle {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct ReputationDecayConfig {
        uint256 decayInterval;
        uint256 decayPercentage;
        uint256 minimumReputation;
        bool enabled;
    }

    struct InactivityTracking {
        uint256 lastActiveBlock;
        uint256 lastVerificationTimestamp;
        uint256 lastSuccessfulVerification;
    }

    mapping(address => uint256) public baseReputation;
    mapping(address => uint256) public lastActivityTimestamp;
    mapping(address => InactivityTracking) public inactivityTracking;

    ReputationDecayConfig public decayConfig;

    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant DEFAULT_MINIMUM_REPUTATION = 1;

    event ReputationUpdated(address indexed user, uint256 oldReputation, uint256 newReputation, uint256 timestamp);
    event ActivityRecorded(address indexed user, uint256 timestamp);
    event ReputationDecayed(address indexed verifier, uint256 previousScore, uint256 newScore);
    event DecayConfigUpdated(uint256 decayInterval, uint256 decayPercentage, uint256 minimumReputation, bool enabled);

    error InvalidDecayPercentage();
    error InvalidDecayInterval();

    constructor(address initialAdmin) {
        _initializeGovernance(address(0), initialAdmin, initialAdmin);
        _grantRole(ORACLE_ROLE, initialAdmin);
        _setRoleAdmin(ORACLE_ROLE, GOVERNANCE_ADMIN_ROLE);

        decayConfig = ReputationDecayConfig({
            decayInterval: 7 days,
            decayPercentage: 100,
            minimumReputation: DEFAULT_MINIMUM_REPUTATION,
            enabled: true
        });
    }

    function getEffectiveReputation(address user) public view returns (uint256) {
        uint256 base = baseReputation[user];
        if (base == 0) return 0;

        if (!decayConfig.enabled) return base;

        uint256 lastActivity = lastActivityTimestamp[user];
        if (lastActivity == 0) return base;

        uint256 intervalsSinceActivity = (block.timestamp - lastActivity) / decayConfig.decayInterval;
        if (intervalsSinceActivity == 0) return base;

        uint256 totalDecayBps = intervalsSinceActivity * decayConfig.decayPercentage;
        if (totalDecayBps > BASIS_POINTS) totalDecayBps = BASIS_POINTS;

        uint256 effective = (base * (BASIS_POINTS - totalDecayBps)) / BASIS_POINTS;

        if (effective < decayConfig.minimumReputation) {
            effective = decayConfig.minimumReputation;
        }

        return effective;
    }

    function applyDecay(address user) external onlyRole(ORACLE_ROLE) {
        uint256 effective = getEffectiveReputation(user);
        uint256 base = baseReputation[user];

        if (effective < base) {
            baseReputation[user] = effective;
            lastActivityTimestamp[user] = block.timestamp;
            inactivityTracking[user] = InactivityTracking({
                lastActiveBlock: block.number,
                lastVerificationTimestamp: block.timestamp,
                lastSuccessfulVerification: block.timestamp
            });

            emit ReputationDecayed(user, base, effective);
        }
    }

    function recordActivity(address user) external onlyRole(ORACLE_ROLE) {
        _recordActivity(user);
    }

    function recordActivityBatch(address[] calldata users) external onlyRole(ORACLE_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            _recordActivity(users[i]);
        }
    }

    function setReputation(address user, uint256 amount) external onlyRole(ORACLE_ROLE) {
        uint256 oldReputation = baseReputation[user];
        baseReputation[user] = amount;
        _recordActivity(user);

        emit ReputationUpdated(user, oldReputation, amount, block.timestamp);
    }

    function addReputation(address user, uint256 amount) external onlyRole(ORACLE_ROLE) {
        uint256 oldReputation = baseReputation[user];
        uint256 newReputation = oldReputation + amount;
        baseReputation[user] = newReputation;
        _recordActivity(user);

        emit ReputationUpdated(user, oldReputation, newReputation, block.timestamp);
    }

    function deductReputation(address user, uint256 amount) external onlyRole(ORACLE_ROLE) {
        uint256 oldReputation = baseReputation[user];
        uint256 newReputation = oldReputation > amount ? oldReputation - amount : 0;
        baseReputation[user] = newReputation;

        emit ReputationUpdated(user, oldReputation, newReputation, block.timestamp);
    }

    function setDecayConfig(ReputationDecayConfig calldata newConfig) external onlyGovernanceOrAdmin {
        if (newConfig.decayPercentage > BASIS_POINTS) revert InvalidDecayPercentage();
        if (newConfig.decayInterval == 0) revert InvalidDecayInterval();

        decayConfig = newConfig;

        emit DecayConfigUpdated(
            newConfig.decayInterval,
            newConfig.decayPercentage,
            newConfig.minimumReputation,
            newConfig.enabled
        );
    }

    function calculateDecay(address user) external view returns (uint256 decayAmount) {
        uint256 base = baseReputation[user];
        uint256 effective = getEffectiveReputation(user);
        if (effective >= base) return 0;
        return base - effective;
    }

    function isDecayRequired(address user) external view returns (bool) {
        if (!decayConfig.enabled) return false;
        uint256 base = baseReputation[user];
        if (base == 0) return false;
        uint256 lastActivity = lastActivityTimestamp[user];
        if (lastActivity == 0) return false;
        return (block.timestamp - lastActivity) >= decayConfig.decayInterval;
    }

    function nextDecayTimestamp(address user) external view returns (uint256) {
        uint256 lastActivity = lastActivityTimestamp[user];
        if (lastActivity == 0) return type(uint256).max;
        return lastActivity + decayConfig.decayInterval;
    }

    function getReputationScore(address user) external view returns (uint256 score) {
        return getEffectiveReputation(user);
    }

    function isActive() external view returns (bool) {
        return decayConfig.enabled;
    }

    function getLastReputationUpdate(address user) external view returns (uint256 timestamp) {
        return lastActivityTimestamp[user];
    }

    function _recordActivity(address user) internal {
        lastActivityTimestamp[user] = block.timestamp;
        inactivityTracking[user] = InactivityTracking({
            lastActiveBlock: block.number,
            lastVerificationTimestamp: block.timestamp,
            lastSuccessfulVerification: block.timestamp
        });
        emit ActivityRecorded(user, block.timestamp);
    }

    uint256[50] private __gap;
}
