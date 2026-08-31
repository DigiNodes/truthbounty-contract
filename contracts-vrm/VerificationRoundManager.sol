// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IVerificationRoundManager.sol";

/**
 * @title VerificationRoundManager
 * @author TruthBounty Protocol
 * @notice Manages the full lifecycle of verification rounds: opening, participant
 *         recording, closure, and read-only projection queries.
 *
 * @dev Architecture position:
 *      ┌──────────────────────────────────────────────────────────────────────┐
 *      │  VerificationRoundManager                                            │
 *      │                                                                      │
 *      │  Depends on:  none (self-contained round state machine)              │
 *      │  Depended on: VerificationSubmission, SettlementEngine, Indexer      │
 *      └──────────────────────────────────────────────────────────────────────┘
 *
 *      Security invariants:
 *      1. Round parameters are write-once; no mutator exists after {openRound}.
 *      2. At most one OPEN round of each type per claim at any time.
 *      3. An APPEAL round can only be opened after the FIRST round is CLOSED.
 *      4. Participant records are append-only within a round.
 *      5. Closure is permissionless but only possible after the deadline.
 *      6. All state-changing loops are avoided; closure is O(1).
 *      7. Participant pagination caps gas for off-chain consumers.
 *
 *      Access control:
 *      - DEFAULT_ADMIN_ROLE : can grant/revoke other roles and pause/unpause.
 *      - ROUND_MANAGER_ROLE : may call {openRound} and {recordParticipant}.
 *      - {closeRound}       : permissionless after deadline.
 *
 *      Upgradeability:
 *      The contract is intentionally not upgradeable in this iteration.
 *      A storage gap (`__gap`) is reserved for future proxy-safe layouts.
 */
contract VerificationRoundManager is
    AccessControl,
    Pausable,
    ReentrancyGuard,
    IVerificationRoundManager
{
    // =========================================================================
    // Roles
    // =========================================================================

    /// @notice Role that permits calling {openRound} and {recordParticipant}.
    bytes32 public constant ROUND_MANAGER_ROLE = keccak256("ROUND_MANAGER_ROLE");

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum basis-point value for passingThreshold (100 %).
    uint16 public constant MAX_BPS = 10_000;

    // =========================================================================
    // State
    // =========================================================================

    /// @dev Monotonic round ID counter; first issued ID is 1.
    uint256 private _nextRoundId = 1;

    /// @dev roundId → frozen parameter snapshot.
    mapping(uint256 => RoundParams) private _rounds;

    /// @dev roundId → ordered participant list.
    mapping(uint256 => ParticipantRecord[]) private _participants;

    /// @dev roundId → participant address → already recorded flag.
    mapping(uint256 => mapping(address => bool)) private _participated;

    /// @dev claimId → RoundType → active (non-closed) roundId, or 0 if none.
    mapping(uint256 => mapping(uint8 => uint256)) private _activeRound;

    /// @dev claimId → whether the FIRST round has ever been closed.
    mapping(uint256 => bool) private _firstRoundClosed;

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @param admin  Address granted DEFAULT_ADMIN_ROLE and initial ROUND_MANAGER_ROLE.
     */
    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROUND_MANAGER_ROLE, admin);
    }

    // =========================================================================
    // Custom errors not declared in interface
    // =========================================================================

    error ZeroAddress();
    error ExceedsMaxStake(uint256 roundId, uint256 stake, uint256 maxStake);
    error InsufficientStake(uint256 roundId, uint256 stake, uint256 minStake);

    // =========================================================================
    // Admin: pause / unpause
    // =========================================================================

    /**
     * @notice Pauses all state-changing operations.
     * @dev Only DEFAULT_ADMIN_ROLE.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all state-changing operations.
     * @dev Only DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // =========================================================================
    // IVerificationRoundManager: write functions
    // =========================================================================

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function openRound(
        uint256 claimId,
        RoundType roundType,
        uint64 deadline,
        uint256 minStake,
        uint256 maxStake,
        uint256 weightCap,
        uint16 passingThreshold,
        uint32 paramVersion
    )
        external
        override
        onlyRole(ROUND_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 roundId)
    {
        // --- Validation ---
        if (deadline <= uint64(block.timestamp)) revert DeadlineMustBeFuture();
        if (minStake > maxStake) revert InvalidStakeBounds();
        if (passingThreshold > MAX_BPS) revert InvalidThreshold();

        uint8 typeIndex = uint8(roundType);

        // At most one open round of each type per claim.
        if (_activeRound[claimId][typeIndex] != 0) {
            revert OverlappingActiveRound(claimId, roundType);
        }

        // Appeal round requires FIRST round to be closed.
        if (roundType == RoundType.APPEAL && !_firstRoundClosed[claimId]) {
            revert FirstRoundNotClosed(claimId);
        }

        // --- State update ---
        roundId = _nextRoundId;
        unchecked { _nextRoundId = roundId + 1; }

        _rounds[roundId] = RoundParams({
            claimId:          claimId,
            roundType:        roundType,
            state:            RoundState.OPEN,
            startedAt:        uint64(block.timestamp),
            deadline:         deadline,
            minStake:         minStake,
            maxStake:         maxStake,
            weightCap:        weightCap,
            passingThreshold: passingThreshold,
            paramVersion:     paramVersion
        });

        _activeRound[claimId][typeIndex] = roundId;

        // --- Event ---
        emit RoundOpened(
            claimId,
            roundId,
            typeIndex,
            uint64(block.timestamp),
            deadline,
            minStake,
            maxStake,
            weightCap,
            passingThreshold,
            paramVersion
        );
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function closeRound(uint256 roundId)
        external
        override
        whenNotPaused
        nonReentrant
    {
        RoundParams storage params = _rounds[roundId];

        // Round must exist (startedAt == 0 only for uninitialised storage).
        if (params.startedAt == 0) revert RoundNotFound(roundId);
        if (params.state == RoundState.CLOSED) revert RoundAlreadyClosed(roundId);
        if (uint64(block.timestamp) <= params.deadline) revert DeadlineNotReached(roundId);

        // --- State update ---
        params.state = RoundState.CLOSED;

        uint256 claimId   = params.claimId;
        uint8  typeIndex  = uint8(params.roundType);

        // Clear active-round pointer so a new round of the same type can open.
        _activeRound[claimId][typeIndex] = 0;

        // Track first-round closure to gate appeal rounds.
        if (params.roundType == RoundType.FIRST) {
            _firstRoundClosed[claimId] = true;
        }

        uint256 voteCount = _participants[roundId].length;

        // --- Event ---
        emit RoundClosed(claimId, roundId, uint64(block.timestamp), voteCount);
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function recordParticipant(
        uint256 roundId,
        address participant,
        uint256 stake
    )
        external
        override
        onlyRole(ROUND_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        RoundParams storage params = _rounds[roundId];

        if (params.startedAt == 0) revert RoundNotFound(roundId);
        if (params.state == RoundState.CLOSED) revert RoundClosed_Submissions(roundId);
        if (_participated[roundId][participant]) revert AlreadyParticipated(roundId, participant);
        if (stake < params.minStake) revert InsufficientStake(roundId, stake, params.minStake);
        if (stake > params.maxStake) revert ExceedsMaxStake(roundId, stake, params.maxStake);

        _participated[roundId][participant] = true;

        _participants[roundId].push(ParticipantRecord({
            participant: participant,
            stake:       stake,
            submittedAt: uint64(block.timestamp)
        }));
    }

    // =========================================================================
    // IVerificationRoundManager: view functions
    // =========================================================================

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function getRound(uint256 roundId)
        external
        view
        override
        returns (RoundParams memory params)
    {
        params = _rounds[roundId];
        if (params.startedAt == 0) revert RoundNotFound(roundId);
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function getRoundState(uint256 roundId)
        external
        view
        override
        returns (RoundState state)
    {
        RoundParams storage params = _rounds[roundId];
        if (params.startedAt == 0) revert RoundNotFound(roundId);
        return params.state;
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function getActiveRound(uint256 claimId, RoundType roundType)
        external
        view
        override
        returns (uint256 roundId)
    {
        return _activeRound[claimId][uint8(roundType)];
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function getParticipantCount(uint256 roundId)
        external
        view
        override
        returns (uint256 count)
    {
        if (_rounds[roundId].startedAt == 0) revert RoundNotFound(roundId);
        return _participants[roundId].length;
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function getParticipants(
        uint256 roundId,
        uint256 offset,
        uint256 limit
    )
        external
        view
        override
        returns (ParticipantRecord[] memory records)
    {
        if (_rounds[roundId].startedAt == 0) revert RoundNotFound(roundId);

        ParticipantRecord[] storage all = _participants[roundId];
        uint256 total = all.length;

        if (offset >= total) {
            return new ParticipantRecord[](0);
        }

        uint256 available = total - offset;
        uint256 size = (limit == 0 || limit > available) ? available : limit;

        records = new ParticipantRecord[](size);
        for (uint256 i = 0; i < size; ) {
            records[i] = all[offset + i];
            unchecked { ++i; }
        }
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function hasParticipated(uint256 roundId, address participant)
        external
        view
        override
        returns (bool recorded)
    {
        return _participated[roundId][participant];
    }

    /**
     * @inheritdoc IVerificationRoundManager
     */
    function totalRounds()
        external
        view
        override
        returns (uint256 total)
    {
        unchecked { return _nextRoundId - 1; }
    }

    // =========================================================================
    // Storage gap (for future proxy-safe upgrades)
    // =========================================================================

    uint256[50] private __gap;
}
