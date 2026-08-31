// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IReputationUpdateEngine.sol";
import "./IReputationOracle.sol";
import "./governance/GovernanceOwnable.sol";

/**
 * @title ReputationUpdateEngine
 * @notice Deterministic on-chain reputation update engine (SC-008)
 * @dev The sole authorised mechanism for modifying reputation within the
 *      protocol. Every completed claim resolution produces a transparent
 *      and reproducible reputation update.
 *
 * Security properties:
 * - Only authorised protocol contracts may call updateReputation()
 * - Duplicate updates per (verifier, claimId) are prevented
 * - Reputation floor and cap enforce bounds
 * - All updates are recorded immutably in the update history
 * - Governance parameters are configurable via the governance controller
 */
contract ReputationUpdateEngine is
    IReputationUpdateEngine,
    AccessControl,
    ReentrancyGuard,
    Pausable,
    GovernanceOwnable
{
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE    = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATE_ROLE   = keccak256("UPDATE_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ============ Governance Param IDs ============

    bytes32 public constant PARAM_REWARD_INCREMENT   = keccak256("REWARD_INCREMENT");
    bytes32 public constant PARAM_PENALTY_AMOUNT      = keccak256("PENALTY_AMOUNT");
    bytes32 public constant PARAM_MALICIOUS_MULT      = keccak256("MALICIOUS_MULTIPLIER");
    bytes32 public constant PARAM_DISPUTE_ADJ          = keccak256("DISPUTE_ADJUSTMENT");
    bytes32 public constant PARAM_MIN_FLOOR            = keccak256("MIN_REPUTATION_FLOOR");
    bytes32 public constant PARAM_MAX_CAP              = keccak256("MAX_REPUTATION_CAP");

    // ============ Governance Parameters ============

    /// @notice Reputation increment for a correct verification
    uint256 public rewardIncrement = 10;

    /// @notice Reputation penalty for an incorrect verification
    uint256 public penaltyAmount = 10;

    /// @notice Multiplier applied to penalties for malicious behaviour
    uint256 public maliciousMultiplier = 5;

    /// @notice Adjustment applied to disputes (neutral — signed integer)
    int256  public disputeAdjustment = 0;

    /// @notice Minimum reputation floor — score can never drop below this
    uint256 public minimumReputationFloor = 0;

    /// @notice Maximum reputation cap — score can never exceed this
    uint256 public maximumReputationCap = type(uint256).max;

    // ============ State ============

    /// @notice Current reputation score per verifier
    mapping(address => uint256) private _reputations;

    /// @notice verifier => claimId => already processed
    mapping(address => mapping(uint256 => bool)) private _claimProcessed;

    /// @notice verifier => array of update records
    mapping(address => ReputationUpdateRecord[]) private _updateHistory;

    /// @notice Cumulative statistics
    mapping(address => uint256) public totalReputationGained;
    mapping(address => uint256) public totalReputationLost;
    mapping(address => uint256) public successfulUpdates;
    mapping(address => uint256) public failedVerifications;
    mapping(address => uint256) public maliciousPenalties;
    mapping(address => uint256) public disputedOutcomes;

    // ============ Errors ============

    error UnauthorizedUpdate();
    error DuplicateUpdate(address verifier, uint256 claimId);
    error ReputationUpdateUnderflow();
    error ReputationUpdateOverflow();
    error InvalidDelta();
    error InvalidAddress();
    error InvalidParameter();

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        if (!hasRole(UPDATE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedUpdate();
        }
        _;
    }

    // ============ Constructor ============

    /**
     * @param initialAdmin         Address granted admin roles
     * @param _governanceController Address of the governance controller
     */
    constructor(
        address initialAdmin,
        address _governanceController
    ) {
        if (initialAdmin == address(0)) revert InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE,         initialAdmin);
        _grantRole(UPDATE_ROLE,        initialAdmin);
        _grantRole(PAUSER_ROLE,        initialAdmin);

        _setRoleAdmin(UPDATE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        _initializeGovernance(_governanceController, initialAdmin, initialAdmin);
    }

    // ============ Core: Update Reputation ============

    /**
     * @inheritdoc IReputationUpdateEngine
     */
    function updateReputation(
        ReputationUpdate calldata update
    )
        external
        nonReentrant
        whenNotPaused
        onlyAuthorized
    {
        address verifier = update.verifier;
        if (verifier == address(0)) revert InvalidAddress();

        // ── Duplicate prevention ──────────────────────────────────────
        if (_claimProcessed[verifier][update.claimId]) {
            revert DuplicateUpdate(verifier, update.claimId);
        }
        _claimProcessed[verifier][update.claimId] = true;

        // ── Compute effective delta based on reason ────────────────────
        int256 effectiveDelta = _computeEffectiveDelta(update);

        // ── Apply the update ───────────────────────────────────────────
        uint256 current = _reputations[verifier];
        uint256 newScore;

        if (effectiveDelta >= 0) {
            uint256 uDelta = uint256(effectiveDelta);
            newScore = current + uDelta;

            if (newScore < current) revert ReputationUpdateOverflow();
            if (newScore > maximumReputationCap) {
                newScore = maximumReputationCap;
            }

            totalReputationGained[verifier] += uDelta;
        } else {
            // effectiveDelta is negative
            uint256 uDelta = uint256(-effectiveDelta);

            if (uDelta > current) {
                newScore = minimumReputationFloor;
            } else {
                newScore = current - uDelta;
            }

            if (newScore < minimumReputationFloor) {
                newScore = minimumReputationFloor;
            }

            totalReputationLost[verifier] += uDelta;
        }

        _reputations[verifier] = newScore;

        // ── Track statistics ──────────────────────────────────────────
        if (update.reason == UpdateReason.CORRECT_VERIFICATION) {
            successfulUpdates[verifier] += 1;
        } else if (update.reason == UpdateReason.INCORRECT_VERIFICATION) {
            failedVerifications[verifier] += 1;
        } else if (update.reason == UpdateReason.MALICIOUS_BEHAVIOUR) {
            maliciousPenalties[verifier] += 1;
        } else if (update.reason == UpdateReason.DISPUTED_CLAIM) {
            disputedOutcomes[verifier] += 1;
        }

        // ── Record history ────────────────────────────────────────────
        _updateHistory[verifier].push(ReputationUpdateRecord({
            claimId:   update.claimId,
            delta:     effectiveDelta,
            timestamp: block.timestamp,
            reason:    update.reason
        }));

        emit ReputationUpdated(verifier, effectiveDelta, newScore, update.claimId);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IReputationUpdateEngine
     */
    function getReputation(address verifier) external view returns (uint256) {
        return _reputations[verifier];
    }

    /**
     * @inheritdoc IReputationUpdateEngine
     */
    function getUpdateCount(address verifier) external view returns (uint256) {
        return _updateHistory[verifier].length;
    }

    /**
     * @inheritdoc IReputationUpdateEngine
     */
    function getUpdateHistory(
        address verifier,
        uint256 offset,
        uint256 limit
    ) external view returns (ReputationUpdateRecord[] memory) {
        ReputationUpdateRecord[] storage history = _updateHistory[verifier];
        uint256 total = history.length;

        if (offset >= total) return new ReputationUpdateRecord[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        ReputationUpdateRecord[] memory page = new ReputationUpdateRecord[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = history[i];
        }
        return page;
    }

    /**
     * @inheritdoc IReputationUpdateEngine
     */
    function isClaimProcessed(address verifier, uint256 claimId) external view returns (bool) {
        return _claimProcessed[verifier][claimId];
    }

    // ============ Internal Helpers ============

    /**
     * @dev Compute the effective signed delta from an update reason.
     *      Values remain configurable through governance.
     */
    function _computeEffectiveDelta(
        ReputationUpdate calldata update
    ) internal view returns (int256) {
        if (update.reason == UpdateReason.CORRECT_VERIFICATION) {
            return int256(rewardIncrement);
        } else if (update.reason == UpdateReason.INCORRECT_VERIFICATION) {
            return -int256(penaltyAmount);
        } else if (update.reason == UpdateReason.DISPUTED_CLAIM) {
            return disputeAdjustment;
        } else if (update.reason == UpdateReason.MALICIOUS_BEHAVIOUR) {
            return -int256(penaltyAmount * maliciousMultiplier);
        }

        // Should never reach here
        revert InvalidDelta();
    }

    // ============ Governance Parameter Setters ============

    /**
     * @notice Set the reward increment for correct verifications
     * @param _value New increment value
     */
    function setRewardIncrement(uint256 _value) external onlyGovernanceOrAdmin {
        if (_value == 0) revert InvalidParameter();
        uint256 old = rewardIncrement;
        rewardIncrement = _value;
        emit UpdateParametersUpdated(PARAM_REWARD_INCREMENT, old, _value);
        emit ParameterUpdatedByGovernance(PARAM_REWARD_INCREMENT, old, _value);
    }

    /**
     * @notice Set the penalty amount for incorrect verifications
     * @param _value New penalty value
     */
    function setPenaltyAmount(uint256 _value) external onlyGovernanceOrAdmin {
        if (_value == 0) revert InvalidParameter();
        uint256 old = penaltyAmount;
        penaltyAmount = _value;
        emit UpdateParametersUpdated(PARAM_PENALTY_AMOUNT, old, _value);
        emit ParameterUpdatedByGovernance(PARAM_PENALTY_AMOUNT, old, _value);
    }

    /**
     * @notice Set the malicious behaviour penalty multiplier
     * @param _value New multiplier (1 = same as regular penalty)
     */
    function setMaliciousMultiplier(uint256 _value) external onlyGovernanceOrAdmin {
        if (_value == 0) revert InvalidParameter();
        uint256 old = maliciousMultiplier;
        maliciousMultiplier = _value;
        emit UpdateParametersUpdated(PARAM_MALICIOUS_MULT, old, _value);
        emit ParameterUpdatedByGovernance(PARAM_MALICIOUS_MULT, old, _value);
    }

    /**
     * @notice Set the dispute adjustment (signed integer)
     * @param _value New adjustment value
     */
    function setDisputeAdjustment(int256 _value) external onlyGovernanceOrAdmin {
        int256 old = disputeAdjustment;
        disputeAdjustment = _value;
        // Store as uint256 for event compatibility (negative values handled by caller)
        uint256 oldPacked = uint256(int256(old));
        uint256 newPacked = uint256(int256(_value));
        emit UpdateParametersUpdated(PARAM_DISPUTE_ADJ, oldPacked, newPacked);
        emit ParameterUpdatedByGovernance(PARAM_DISPUTE_ADJ, oldPacked, newPacked);
    }

    /**
     * @notice Set the minimum reputation floor
     * @param _value New floor value
     */
    function setMinimumReputationFloor(uint256 _value) external onlyGovernanceOrAdmin {
        if (_value > maximumReputationCap) revert InvalidParameter();
        uint256 old = minimumReputationFloor;
        minimumReputationFloor = _value;
        emit UpdateParametersUpdated(PARAM_MIN_FLOOR, old, _value);
        emit ParameterUpdatedByGovernance(PARAM_MIN_FLOOR, old, _value);
    }

    /**
     * @notice Set the maximum reputation cap
     * @param _value New cap value (0 = no cap, treated as type(uint256).max)
     */
    function setMaximumReputationCap(uint256 _value) external onlyGovernanceOrAdmin {
        uint256 effectiveCap = _value == 0 ? type(uint256).max : _value;
        if (effectiveCap < minimumReputationFloor) revert InvalidParameter();
        uint256 old = maximumReputationCap;
        maximumReputationCap = effectiveCap;
        emit UpdateParametersUpdated(PARAM_MAX_CAP, old, effectiveCap);
        emit ParameterUpdatedByGovernance(PARAM_MAX_CAP, old, effectiveCap);
    }

    // ============ Admin Functions ============

    /**
     * @notice Grant the UPDATE_ROLE to an authorised protocol contract
     */
    function grantUpdateRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(UPDATE_ROLE, account);
    }

    /**
     * @notice Revoke the UPDATE_ROLE from a contract
     */
    function revokeUpdateRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(UPDATE_ROLE, account);
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
