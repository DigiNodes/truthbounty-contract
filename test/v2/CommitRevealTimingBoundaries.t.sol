// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CommitRevealTimingBoundaries
 * @notice V2-SC-156 — Commit/reveal phase timing boundary unit tests.
 *
 * Coverage matrix:
 *
 *  Section A — Open phase (commit) deadline inclusivity
 *    A1. openRound: deadline == block.timestamp              → revert DeadlineMustBeFuture
 *    A2. openRound: deadline  < block.timestamp              → revert DeadlineMustBeFuture
 *    A3. openRound: deadline == block.timestamp + 1          → succeeds
 *    A4. openRound: deadline == block.timestamp + LARGE      → succeeds
 *
 *  Section B — Submit/commit (recordParticipant) phase window
 *    B1. recordParticipant: before deadline                  → accepted
 *    B2. recordParticipant: exactly at deadline second       → accepted (inclusive)
 *    B3. recordParticipant: deadline + 1                     → accepted (only state gate)
 *    B4. recordParticipant: on a closed round                → revert RoundClosed_Submissions
 *
 *  Section C — Close phase (reveal) deadline inclusivity
 *    C1. closeRound: block.timestamp == deadline             → revert DeadlineNotReached
 *    C2. closeRound: block.timestamp  < deadline             → revert DeadlineNotReached
 *    C3. closeRound: block.timestamp == deadline + 1         → succeeds
 *    C4. closeRound: block.timestamp  > deadline + 1         → succeeds (long after)
 *    C5. closeRound twice                                    → revert RoundAlreadyClosed
 *
 *  Section D — Phase transition: open → (submissions) → close → post-close
 *    D1. Full lifecycle: open → submit → warp past deadline → close succeeds
 *    D2. Submit on a just-closed round                       → revert RoundClosed_Submissions
 *    D3. Close re-opens new round for same claim + type      → succeeds
 *
 *  Section E — Missed reveal (deadline passes without close attempt)
 *    E1. Warp 30 days past deadline, close still succeeds    → no deadline window expiry
 *    E2. Late record on still-open round (very late)         → accepted (state gate only)
 *    E3. Submit then warp far past deadline, close still works
 *
 *  Section F — Pause interactions (pause ≠ deadline freeze)
 *    F1. Pause before open: openRound reverts while paused
 *    F2. Pause after open: recordParticipant reverts while paused
 *    F3. Pause during window, unpause before deadline: submissions resume
 *    F4. Pause during window, deadline passes while paused, unpause: close succeeds immediately
 *    F5. Pause does NOT extend deadline; clock continues during pause
 *    F6. closeRound while paused                             → revert (Pausable)
 *    F7. Unpause → closeRound with just-expired deadline     → succeeds
 *
 *  Section G — Time-warp stress / reorg-model tests
 *    G1. Large forward warp (7 days): deadline check uses block.timestamp, not caller clock
 *    G2. Boundary creep: deadline at uint64 max-safe value validates correctly
 *    G3. Multiple rounds for different claims: independent deadline isolation
 *    G4. Reorg-model: a round opened with future deadline is valid even if block is re-mined
 *        at a slightly different timestamp (simulated by setting timestamp to deadline-1,
 *        then deadline, then deadline+1, verifying each gate exactly once)
 *    G5. block.timestamp source: verify submittedAt on ParticipantRecord equals block.timestamp
 *    G6. startedAt on RoundParams equals block.timestamp at open
 *
 *  Section H — V2Lifecycle helper coverage (isDeadlineValid / isDeadlineExpired)
 *    H1. isDeadlineValid: timestamp == deadline  → true  (inclusive)
 *    H2. isDeadlineValid: timestamp  > deadline  → false
 *    H3. isDeadlineExpired: timestamp == deadline → false
 *    H4. isDeadlineExpired: timestamp  > deadline → true
 *    H5. timeUntilDeadline: returns 0 when expired, correct diff when not
 *
 *  Section I — VerificationSubmission window (VS contract path)
 *    I1. VS.submitVerification: at deadline              → accepted
 *    I2. VS.submitVerification: at deadline + 1          → revert VerificationWindowClosed
 *    I3. VS.submitVerification: before deadline          → accepted
 *    I4. aggregateClaim: at deadline                     → revert AggregationNotFrozen
 *    I5. aggregateClaim: at deadline + 1                 → succeeds (frozen)
 *
 *  Section J — ClaimRegistry deadline creation boundaries
 *    J1. createClaim: deadline == block.timestamp        → revert InvalidDeadline
 *    J2. createClaim: deadline == block.timestamp - 1    → revert InvalidDeadline
 *    J3. createClaim: deadline == block.timestamp + 1    → succeeds
 *    J4. createClaim: deadline > now + 365 days          → revert InvalidDeadline
 *    J5. createClaim: deadline == now + 365 days         → succeeds (max horizon)
 */

import "forge-std/Test.sol";

import {VerificationRoundManager} from "../../contracts/VerificationRoundManager.sol";
import {IVerificationRoundManager} from "../../contracts/interfaces/IVerificationRoundManager.sol";
import {VerificationSubmission} from "../../contracts/VerificationSubmission.sol";
import {IVerificationSubmission} from "../../contracts/interfaces/IVerificationSubmission.sol";
import {ClaimRegistry} from "../../contracts/ClaimRegistry.sol";
import {IClaimRegistry} from "../../contracts/interfaces/IClaimRegistry.sol";
import {MockERC20} from "../../contracts/MockERC20.sol";
import {V2Lifecycle} from "../../contracts/v2/libraries/V2Lifecycle.sol";
import {ParameterVersionRegistry} from "../../contracts/governance/ParameterVersionRegistry.sol";

/// @dev Thin harness exposing V2Lifecycle timing helpers as externally callable.
contract V2LifecycleTimingHarness {
    function isDeadlineValid(uint64 deadline) external view returns (bool) {
        return V2Lifecycle.isDeadlineValid(deadline);
    }

    function isDeadlineExpired(uint64 deadline) external view returns (bool) {
        return V2Lifecycle.isDeadlineExpired(deadline);
    }

    function timeUntilDeadline(uint64 deadline) external view returns (uint256) {
        return V2Lifecycle.timeUntilDeadline(deadline);
    }
}

contract CommitRevealTimingBoundariesTest is Test {
    // =========================================================================
    // Actors
    // =========================================================================

    address internal constant ADMIN     = address(0xA11CE);
    address internal constant MANAGER   = address(0xBEEF);
    address internal constant VERIFIER1 = address(0xAA01);
    address internal constant VERIFIER2 = address(0xAA02);
    address internal constant CLAIMER   = address(0xCA11);

    // =========================================================================
    // Round parameters
    // =========================================================================

    uint256 internal constant MIN_STAKE  = 10 ether;
    uint256 internal constant MAX_STAKE  = 1_000 ether;
    uint256 internal constant WEIGHT_CAP = 100 ether;
    uint16  internal constant THRESHOLD  = 6_000;
    uint32  internal constant PARAM_VER  = 1;

    uint256 internal constant CLAIM_ID_1 = 1;
    uint256 internal constant CLAIM_ID_2 = 2;
    uint256 internal constant CLAIM_ID_3 = 3;

    // Duration used when opening a normal round.
    uint64 internal constant DEFAULT_DURATION = 7 days;

    // ClaimRegistry CID must be >= 46 bytes.
    string internal constant VALID_CID       = "Qm1234567890abcdef1234567890abcdef1234567890abcd";
    string internal constant VALID_STATEMENT = "Is this claim true or false? (at least ten chars)";

    // =========================================================================
    // Contracts under test
    // =========================================================================

    VerificationRoundManager  internal vrm;
    V2LifecycleTimingHarness  internal lifecycle;
    VerificationSubmission    internal vs;
    ClaimRegistry             internal registry;
    MockERC20                 internal token;
    ParameterVersionRegistry  internal paramReg;

    bytes32 internal ROUND_MANAGER_ROLE;
    bytes32 internal REGISTRY_UPDATER_ROLE;

    // =========================================================================
    // setUp
    // =========================================================================

    function setUp() public {
        // Pin a deterministic starting timestamp so warp deltas are predictable.
        vm.warp(1_700_000_000);

        // Deploy VRM.
        vm.prank(ADMIN);
        vrm = new VerificationRoundManager(ADMIN);
        ROUND_MANAGER_ROLE = vrm.ROUND_MANAGER_ROLE();

        vm.prank(ADMIN);
        vrm.grantRole(ROUND_MANAGER_ROLE, MANAGER);

        // Deploy V2Lifecycle harness.
        lifecycle = new V2LifecycleTimingHarness();

        // Deploy token and ParameterVersionRegistry for VerificationSubmission / ClaimRegistry.
        vm.prank(ADMIN);
        token = new MockERC20("TestToken", "TTK");

        vm.prank(ADMIN);
        paramReg = new ParameterVersionRegistry(ADMIN, ADMIN);

        vm.prank(ADMIN);
        registry = new ClaimRegistry(ADMIN, address(paramReg));
        REGISTRY_UPDATER_ROLE = registry.REGISTRY_UPDATER_ROLE();

        // Grant ClaimRegistry updater role to ADMIN.
        vm.startPrank(ADMIN);
        registry.grantRole(REGISTRY_UPDATER_ROLE, ADMIN);
        vm.stopPrank();

        // Deploy VerificationSubmission pointed at registry and token.
        vs = new VerificationSubmission(address(registry), address(token), MIN_STAKE);

        // Mint tokens to verifiers.
        token.mint(VERIFIER1, 10_000 ether);
        token.mint(VERIFIER2, 10_000 ether);

        // Approve VS to spend verifier tokens.
        vm.prank(VERIFIER1);
        token.approve(address(vs), type(uint256).max);
        vm.prank(VERIFIER2);
        token.approve(address(vs), type(uint256).max);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Opens a FIRST round with a deadline `duration` seconds from now.
    function _openRound(uint256 claimId, uint64 duration) internal returns (uint256 roundId, uint64 deadline) {
        deadline = uint64(block.timestamp) + duration;
        vm.prank(MANAGER);
        roundId = vrm.openRound(
            claimId,
            IVerificationRoundManager.RoundType.FIRST,
            deadline,
            MIN_STAKE,
            MAX_STAKE,
            WEIGHT_CAP,
            THRESHOLD,
            PARAM_VER
        );
    }

    /// @dev Records a participant in a round with MIN_STAKE.
    function _record(uint256 roundId, address participant) internal {
        vm.prank(MANAGER);
        vrm.recordParticipant(roundId, participant, MIN_STAKE);
    }

    /// @dev Closes a round (permissionless; caller = address(this)).
    function _close(uint256 roundId) internal {
        vrm.closeRound(roundId);
    }

    /// @dev Creates a claim in ClaimRegistry with deadline `offset` seconds from now.
    function _createClaim(uint64 deadlineOffset) internal returns (uint256 claimId) {
        uint64 deadline = uint64(block.timestamp) + deadlineOffset;
        vm.prank(CLAIMER);
        claimId = registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
    }

    /// @dev Submits a verification verdict for a claim in the VS contract.
    function _submitVerification(
        address verifier,
        uint256 claimId,
        IVerificationSubmission.VerificationVerdict verdict
    ) internal {
        vm.prank(verifier);
        vs.submitVerification(claimId, verdict, MIN_STAKE);
    }

    // =========================================================================
    // Section A — Open phase (commit) deadline inclusivity
    // =========================================================================

    /// @notice A1: openRound with deadline == block.timestamp reverts DeadlineMustBeFuture.
    function test_A1_openRound_deadlineEqualTimestamp_reverts() public {
        uint64 deadline = uint64(block.timestamp); // not strictly future
        vm.prank(MANAGER);
        vm.expectRevert(IVerificationRoundManager.DeadlineMustBeFuture.selector);
        vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST, deadline,
                      MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
    }

    /// @notice A2: openRound with deadline < block.timestamp reverts DeadlineMustBeFuture.
    function test_A2_openRound_deadlineInPast_reverts() public {
        uint64 deadline = uint64(block.timestamp) - 1;
        vm.prank(MANAGER);
        vm.expectRevert(IVerificationRoundManager.DeadlineMustBeFuture.selector);
        vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST, deadline,
                      MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
    }

    /// @notice A3: openRound with deadline == block.timestamp + 1 succeeds (minimal future).
    function test_A3_openRound_deadlineOnePlusTimestamp_succeeds() public {
        uint64 deadline = uint64(block.timestamp) + 1;
        vm.prank(MANAGER);
        uint256 roundId = vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST,
                                        deadline, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
        assertEq(roundId, 1, "first round should have id=1");
        IVerificationRoundManager.RoundParams memory p = vrm.getRound(roundId);
        assertEq(p.deadline, deadline, "deadline should be frozen at open");
        assertEq(uint8(p.state), uint8(IVerificationRoundManager.RoundState.OPEN));
    }

    /// @notice A4: openRound with a large future deadline (365 days) succeeds.
    function test_A4_openRound_largeDeadline_succeeds() public {
        uint64 deadline = uint64(block.timestamp) + 365 days;
        vm.prank(MANAGER);
        uint256 roundId = vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST,
                                        deadline, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
        IVerificationRoundManager.RoundParams memory p = vrm.getRound(roundId);
        assertEq(p.deadline, deadline);
    }

    // =========================================================================
    // Section B — Submit/commit (recordParticipant) phase window
    // =========================================================================

    /// @notice B1: recordParticipant well before deadline is accepted.
    function test_B1_recordParticipant_beforeDeadline_accepted() public {
        (uint256 roundId, ) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        // Warp to 1 second before deadline.
        vm.warp(block.timestamp + DEFAULT_DURATION - 1);
        _record(roundId, VERIFIER1);
        assertTrue(vrm.hasParticipated(roundId, VERIFIER1));
        assertEq(vrm.getParticipantCount(roundId), 1);
    }

    /// @notice B2: recordParticipant at the exact deadline second is accepted (inclusive).
    function test_B2_recordParticipant_atDeadline_accepted() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        // Warp to exactly the deadline second.
        vm.warp(deadline);
        _record(roundId, VERIFIER1);
        assertTrue(vrm.hasParticipated(roundId, VERIFIER1));
        // Confirm state is still OPEN (no time-based auto-close).
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.OPEN));
    }

    /// @notice B3: recordParticipant after deadline is accepted while round is still OPEN
    ///         (VRM has no time-gate on recordParticipant; gate is purely state-based).
    function test_B3_recordParticipant_afterDeadlineBeforeClose_accepted() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        // Warp 1 second past deadline; round not yet closed.
        vm.warp(uint256(deadline) + 1);
        _record(roundId, VERIFIER1);
        assertTrue(vrm.hasParticipated(roundId, VERIFIER1));
        // Round is still OPEN (close has not been called).
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.OPEN));
    }

    /// @notice B4: recordParticipant on a closed round reverts RoundClosed_Submissions.
    function test_B4_recordParticipant_onClosedRound_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);
        _close(roundId);

        vm.prank(MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.RoundClosed_Submissions.selector, roundId)
        );
        vrm.recordParticipant(roundId, VERIFIER1, MIN_STAKE);
    }

    // =========================================================================
    // Section C — Close phase (reveal) deadline inclusivity
    // =========================================================================

    /// @notice C1: closeRound at exactly the deadline second reverts DeadlineNotReached.
    function test_C1_closeRound_atDeadline_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(deadline); // block.timestamp == deadline → not strictly after
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.DeadlineNotReached.selector, roundId)
        );
        vrm.closeRound(roundId);
    }

    /// @notice C2: closeRound before deadline reverts DeadlineNotReached.
    function test_C2_closeRound_beforeDeadline_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.DeadlineNotReached.selector, roundId)
        );
        vrm.closeRound(roundId);
    }

    /// @notice C3: closeRound at deadline + 1 succeeds (minimal valid close timestamp).
    function test_C3_closeRound_deadlinePlusOne_succeeds() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice C4: closeRound long after deadline succeeds.
    function test_C4_closeRound_longAfterDeadline_succeeds() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 30 days);
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice C5: closing an already-closed round reverts RoundAlreadyClosed.
    function test_C5_closeRound_twice_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);
        _close(roundId);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.RoundAlreadyClosed.selector, roundId)
        );
        vrm.closeRound(roundId);
    }

    // =========================================================================
    // Section D — Phase transition: open → submissions → close → post-close
    // =========================================================================

    /// @notice D1: Full lifecycle — open, submit, warp, close — all transitions succeed.
    function test_D1_fullLifecycle_openSubmitWarpClose() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        _record(roundId, VERIFIER1);
        _record(roundId, VERIFIER2);

        assertEq(vrm.getParticipantCount(roundId), 2);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.OPEN));

        vm.warp(uint256(deadline) + 1);
        _close(roundId);

        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice D2: Submitting on a just-closed round reverts RoundClosed_Submissions.
    function test_D2_submitOnJustClosedRound_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);
        _close(roundId);

        vm.prank(MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.RoundClosed_Submissions.selector, roundId)
        );
        vrm.recordParticipant(roundId, VERIFIER1, MIN_STAKE);
    }

    /// @notice D3: After closing a FIRST round, a new FIRST round can be opened for the same claim.
    function test_D3_afterClose_newRoundForSameClaim_succeeds() public {
        (uint256 roundId1, uint64 deadline1) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline1) + 1);
        _close(roundId1);

        // A second FIRST round (different epoch) should now open.
        (uint256 roundId2, ) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        assertEq(roundId2, 2, "second round ID should be 2");
        assertEq(uint8(vrm.getRoundState(roundId2)), uint8(IVerificationRoundManager.RoundState.OPEN));
        assertGt(roundId2, roundId1);
    }

    // =========================================================================
    // Section E — Missed reveal (deadline passes without close)
    // =========================================================================

    /// @notice E1: A round can be closed 30 days after its deadline (no expiry window).
    function test_E1_missedReveal_30daysLater_closeStillSucceeds() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        // Completely skip the reveal window — warp 30 days past deadline.
        vm.warp(uint256(deadline) + 30 days);
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice E2: A record submitted 30 days after deadline (round still open) is accepted
    ///         because VRM has no timestamp gate on recordParticipant.
    function test_E2_lateRecord_30daysAfterDeadline_acceptedWhileOpen() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 30 days);
        // Round has not been closed yet; should accept.
        _record(roundId, VERIFIER1);
        assertTrue(vrm.hasParticipated(roundId, VERIFIER1));
    }

    /// @notice E3: Submit before deadline, let deadline pass by 60 days, then close succeeds.
    function test_E3_submitEarly_closeVeryLate_succeeds() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        _record(roundId, VERIFIER1);

        vm.warp(uint256(deadline) + 60 days);
        _close(roundId);
        assertEq(vrm.getParticipantCount(roundId), 1);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    // =========================================================================
    // Section F — Pause interactions (pause ≠ deadline freeze)
    // =========================================================================

    /// @notice F1: openRound while paused reverts with Pausable's EnforcedPause.
    function test_F1_openRound_whilePaused_reverts() public {
        vm.prank(ADMIN);
        vrm.pause();

        uint64 deadline = uint64(block.timestamp) + DEFAULT_DURATION;
        vm.prank(MANAGER);
        vm.expectRevert();
        vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST,
                      deadline, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
    }

    /// @notice F2: recordParticipant while paused reverts.
    function test_F2_recordParticipant_whilePaused_reverts() public {
        (uint256 roundId, ) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        vm.prank(ADMIN);
        vrm.pause();

        vm.prank(MANAGER);
        vm.expectRevert();
        vrm.recordParticipant(roundId, VERIFIER1, MIN_STAKE);
    }

    /// @notice F3: Pause then unpause before deadline — submissions resume normally.
    function test_F3_pauseUnpauseBeforeDeadline_submissionsResume() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        // Pause partway through.
        vm.warp(block.timestamp + 1 days);
        vm.prank(ADMIN);
        vrm.pause();

        // Warp more time — deadline is NOT paused.
        vm.warp(block.timestamp + 2 days);

        // Unpause while still before deadline.
        vm.prank(ADMIN);
        vrm.unpause();

        // Deadline has not passed yet; submit should succeed.
        assertLt(block.timestamp, deadline, "should still be before deadline");
        _record(roundId, VERIFIER1);
        assertTrue(vrm.hasParticipated(roundId, VERIFIER1));
    }

    /// @notice F4: Pause after open, deadline passes while paused, unpause → close immediately succeeds.
    ///         Demonstrates pause does NOT extend the deadline.
    function test_F4_pauseDuringWindow_deadlinePassesWhilePaused_closePossibleAfterUnpause() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        vm.prank(ADMIN);
        vrm.pause();

        // Warp past the deadline while paused.
        vm.warp(uint256(deadline) + 10);

        vm.prank(ADMIN);
        vrm.unpause();

        // Close should succeed immediately — deadline expired during the pause.
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice F5: block.timestamp continues advancing during a pause (clock is not frozen).
    function test_F5_pause_doesNotFreezeBlockTimestamp() public {
        uint256 tBefore = block.timestamp;
        vm.prank(ADMIN);
        vrm.pause();

        vm.warp(tBefore + 500);

        // Timestamp advanced even though paused.
        assertEq(block.timestamp, tBefore + 500, "timestamp must advance during pause");

        vm.prank(ADMIN);
        vrm.unpause();
    }

    /// @notice F6: closeRound while paused reverts.
    function test_F6_closeRound_whilePaused_reverts() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);

        vm.prank(ADMIN);
        vrm.pause();

        vm.expectRevert();
        vrm.closeRound(roundId);
    }

    /// @notice F7: Unpause right after deadline, then close succeeds.
    function test_F7_unpauseAfterDeadline_closeSucceeds() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        vm.prank(ADMIN);
        vrm.pause();

        vm.warp(uint256(deadline) + 1);

        vm.prank(ADMIN);
        vrm.unpause();

        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    // =========================================================================
    // Section G — Time-warp stress / reorg-model tests
    // =========================================================================

    /// @notice G1: Large warp (7 days from now) — deadline check uses block.timestamp, not
    ///         any caller-supplied value.  Demonstrates timestamp-source isolation.
    function test_G1_largeTimestampJump_usesBlockTimestamp() public {
        uint64 duration = 3 days;
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, duration);

        // Warp well past 7 days so block.timestamp >> deadline.
        vm.warp(block.timestamp + 7 days);

        // block.timestamp > deadline → close succeeds.
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice G2: Deadline at a large (but valid) uint64 value is stored and read correctly.
    function test_G2_largeDeadlineValue_storedAndReadCorrectly() public {
        // Pick a deadline near but below the uint64 safe max (well within forge warp range).
        uint64 deadline = type(uint64).max - 1;
        vm.prank(MANAGER);
        uint256 roundId = vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST,
                                        deadline, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
        IVerificationRoundManager.RoundParams memory p = vrm.getRound(roundId);
        assertEq(p.deadline, deadline, "deadline must survive round-trip storage");
    }

    /// @notice G3: Multiple rounds for different claims have isolated deadlines.
    function test_G3_multipleRounds_isolatedDeadlines() public {
        uint64 d1 = uint64(block.timestamp) + 1 days;
        uint64 d2 = uint64(block.timestamp) + 5 days;

        vm.prank(MANAGER);
        uint256 r1 = vrm.openRound(CLAIM_ID_1, IVerificationRoundManager.RoundType.FIRST,
                                   d1, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);
        vm.prank(MANAGER);
        uint256 r2 = vrm.openRound(CLAIM_ID_2, IVerificationRoundManager.RoundType.FIRST,
                                   d2, MIN_STAKE, MAX_STAKE, WEIGHT_CAP, THRESHOLD, PARAM_VER);

        // Warp past d1 but not d2.
        vm.warp(uint256(d1) + 1);

        // r1 can be closed.
        _close(r1);
        assertEq(uint8(vrm.getRoundState(r1)), uint8(IVerificationRoundManager.RoundState.CLOSED));

        // r2 cannot be closed yet.
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.DeadlineNotReached.selector, r2)
        );
        vrm.closeRound(r2);
        assertEq(uint8(vrm.getRoundState(r2)), uint8(IVerificationRoundManager.RoundState.OPEN));
    }

    /// @notice G4: Reorg-model: boundary sweep at deadline-1, deadline, deadline+1.
    ///         The protocol gate toggles exactly at the boundary.
    function test_G4_reorgModel_boundaryAtDeadlineMinusOnePlusOne() public {
        (uint256 roundId, uint64 deadline) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        // T = deadline - 1: close must revert.
        vm.warp(uint256(deadline) - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.DeadlineNotReached.selector, roundId)
        );
        vrm.closeRound(roundId);

        // T = deadline: close must still revert (not strictly after).
        vm.warp(deadline);
        vm.expectRevert(
            abi.encodeWithSelector(IVerificationRoundManager.DeadlineNotReached.selector, roundId)
        );
        vrm.closeRound(roundId);

        // T = deadline + 1: close must succeed.
        vm.warp(uint256(deadline) + 1);
        _close(roundId);
        assertEq(uint8(vrm.getRoundState(roundId)), uint8(IVerificationRoundManager.RoundState.CLOSED));
    }

    /// @notice G5: submittedAt on a ParticipantRecord equals block.timestamp at the time of submission.
    function test_G5_blockTimestampSource_submittedAt_matchesBlockTimestamp() public {
        (uint256 roundId, ) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        uint256 warpTarget = block.timestamp + 3 hours;
        vm.warp(warpTarget);

        _record(roundId, VERIFIER1);

        IVerificationRoundManager.ParticipantRecord[] memory records =
            vrm.getParticipants(roundId, 0, 10);
        assertEq(records.length, 1);
        assertEq(uint256(records[0].submittedAt), warpTarget,
                 "submittedAt must equal block.timestamp at submission");
    }

    /// @notice G6: startedAt on RoundParams equals block.timestamp at the time openRound was called.
    function test_G6_blockTimestampSource_startedAt_matchesBlockTimestamp() public {
        uint256 openTs = block.timestamp;
        (uint256 roundId, ) = _openRound(CLAIM_ID_1, DEFAULT_DURATION);

        IVerificationRoundManager.RoundParams memory p = vrm.getRound(roundId);
        assertEq(uint256(p.startedAt), openTs,
                 "startedAt must equal block.timestamp when openRound was called");
    }

    // =========================================================================
    // Section H — V2Lifecycle helper coverage
    // =========================================================================

    /// @notice H1: isDeadlineValid returns true when block.timestamp == deadline (inclusive).
    function test_H1_isDeadlineValid_atDeadline_true() public {
        uint64 deadline = uint64(block.timestamp) + 1 hours;
        vm.warp(deadline);
        assertTrue(lifecycle.isDeadlineValid(deadline), "deadline inclusive: should be valid");
    }

    /// @notice H2: isDeadlineValid returns false when block.timestamp > deadline.
    function test_H2_isDeadlineValid_afterDeadline_false() public {
        uint64 deadline = uint64(block.timestamp) + 1 hours;
        vm.warp(uint256(deadline) + 1);
        assertFalse(lifecycle.isDeadlineValid(deadline), "expired deadline should not be valid");
    }

    /// @notice H3: isDeadlineExpired returns false when block.timestamp == deadline.
    function test_H3_isDeadlineExpired_atDeadline_false() public {
        uint64 deadline = uint64(block.timestamp) + 1 hours;
        vm.warp(deadline);
        assertFalse(lifecycle.isDeadlineExpired(deadline), "at-deadline: not yet expired");
    }

    /// @notice H4: isDeadlineExpired returns true when block.timestamp > deadline.
    function test_H4_isDeadlineExpired_afterDeadline_true() public {
        uint64 deadline = uint64(block.timestamp) + 1 hours;
        vm.warp(uint256(deadline) + 1);
        assertTrue(lifecycle.isDeadlineExpired(deadline), "past deadline: must be expired");
    }

    /// @notice H5: timeUntilDeadline returns 0 when expired, correct diff otherwise.
    function test_H5_timeUntilDeadline_correctValues() public {
        uint64 deadline = uint64(block.timestamp) + 1 hours;

        // Before expiry.
        uint256 remaining = lifecycle.timeUntilDeadline(deadline);
        assertApproxEqAbs(remaining, 1 hours, 1, "remaining should be ~1 hour");

        // At expiry.
        vm.warp(deadline);
        assertEq(lifecycle.timeUntilDeadline(deadline), 0, "at deadline: 0 remaining");

        // After expiry.
        vm.warp(uint256(deadline) + 100);
        assertEq(lifecycle.timeUntilDeadline(deadline), 0, "past deadline: 0 remaining");
    }

    // =========================================================================
    // Section I — VerificationSubmission window (VS contract path)
    // =========================================================================

    /// @dev Opens a claim in registry, transitions it to UnderVerification, and returns claimId + deadline.
    function _setupVSClaim(uint64 duration) internal returns (uint256 claimId, uint64 deadline) {
        uint64 deadlineTs = uint64(block.timestamp) + duration;
        vm.prank(CLAIMER);
        claimId = registry.createClaim(VALID_STATEMENT, VALID_CID, deadlineTs);
        deadline = deadlineTs;
        // Transition claim to UnderVerification so VS accepts submissions.
        vm.prank(ADMIN);
        registry.updateClaimStatus(claimId, IClaimRegistry.ClaimStatus.UnderVerification);
    }

    /// @notice I1: VS.submitVerification at the exact deadline second is accepted.
    function test_I1_vsSubmit_atDeadline_accepted() public {
        (uint256 claimId, uint64 deadline) = _setupVSClaim(DEFAULT_DURATION);
        vm.warp(deadline); // block.timestamp == verificationDeadline → accepted (not strictly after)
        _submitVerification(VERIFIER1, claimId, IVerificationSubmission.VerificationVerdict.TRUE);
        assertEq(vs.getVerificationCount(), 1);
    }

    /// @notice I2: VS.submitVerification at deadline + 1 reverts VerificationWindowClosed.
    function test_I2_vsSubmit_deadlinePlusOne_reverts() public {
        (uint256 claimId, uint64 deadline) = _setupVSClaim(DEFAULT_DURATION);
        vm.warp(uint256(deadline) + 1);
        vm.prank(VERIFIER1);
        vm.expectRevert(VerificationSubmission.VerificationWindowClosed.selector);
        vs.submitVerification(claimId, IVerificationSubmission.VerificationVerdict.TRUE, MIN_STAKE);
    }

    /// @notice I3: VS.submitVerification well before deadline is accepted.
    function test_I3_vsSubmit_beforeDeadline_accepted() public {
        (uint256 claimId, ) = _setupVSClaim(DEFAULT_DURATION);
        // Still in the first second after setup; well before deadline.
        _submitVerification(VERIFIER1, claimId, IVerificationSubmission.VerificationVerdict.TRUE);
        assertEq(vs.getVerificationCount(), 1);
    }

    /// @notice I4: aggregateClaim reverts when block.timestamp == verificationDeadline (not yet frozen).
    function test_I4_aggregateClaim_atDeadline_reverts() public {
        (uint256 claimId, uint64 deadline) = _setupVSClaim(DEFAULT_DURATION);
        _submitVerification(VERIFIER1, claimId, IVerificationSubmission.VerificationVerdict.TRUE);

        vm.warp(deadline); // block.timestamp == deadline → not strictly after → AggregationNotFrozen
        vm.expectRevert(VerificationSubmission.AggregationNotFrozen.selector);
        vs.aggregateClaim(claimId);
    }

    /// @notice I5: aggregateClaim succeeds at deadline + 1 (verification window frozen).
    function test_I5_aggregateClaim_deadlinePlusOne_succeeds() public {
        (uint256 claimId, uint64 deadline) = _setupVSClaim(DEFAULT_DURATION);
        _submitVerification(VERIFIER1, claimId, IVerificationSubmission.VerificationVerdict.TRUE);

        vm.warp(uint256(deadline) + 1); // strictly after deadline
        VerificationSubmission.AggregationRecord memory result = vs.aggregateClaim(claimId);
        assertEq(result.trueCount, 1);
        assertEq(uint8(result.outcome), uint8(VerificationSubmission.VerificationOutcome.True));
    }

    // =========================================================================
    // Section J — ClaimRegistry deadline creation boundaries
    // =========================================================================

    /// @notice J1: createClaim with deadline == block.timestamp reverts InvalidDeadline.
    function test_J1_createClaim_deadlineEqualNow_reverts() public {
        uint64 deadline = uint64(block.timestamp);
        vm.prank(CLAIMER);
        vm.expectRevert(IClaimRegistry.InvalidDeadline.selector);
        registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
    }

    /// @notice J2: createClaim with deadline < block.timestamp reverts InvalidDeadline.
    function test_J2_createClaim_deadlineInPast_reverts() public {
        uint64 deadline = uint64(block.timestamp) - 1;
        vm.prank(CLAIMER);
        vm.expectRevert(IClaimRegistry.InvalidDeadline.selector);
        registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
    }

    /// @notice J3: createClaim with deadline == block.timestamp + 1 succeeds.
    function test_J3_createClaim_deadlineOnePlusNow_succeeds() public {
        uint64 deadline = uint64(block.timestamp) + 1;
        vm.prank(CLAIMER);
        uint256 claimId = registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
        IClaimRegistry.Claim memory c = registry.getClaim(claimId);
        assertEq(c.verificationDeadline, deadline);
    }

    /// @notice J4: createClaim with deadline > now + 365 days reverts InvalidDeadline.
    function test_J4_createClaim_beyondMaxHorizon_reverts() public {
        uint64 deadline = uint64(block.timestamp) + 365 days + 1;
        vm.prank(CLAIMER);
        vm.expectRevert(IClaimRegistry.InvalidDeadline.selector);
        registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
    }

    /// @notice J5: createClaim with deadline == now + 365 days succeeds (at max horizon).
    function test_J5_createClaim_exactMaxHorizon_succeeds() public {
        uint64 deadline = uint64(block.timestamp) + 365 days;
        vm.prank(CLAIMER);
        uint256 claimId = registry.createClaim(VALID_STATEMENT, VALID_CID, deadline);
        IClaimRegistry.Claim memory c = registry.getClaim(claimId);
        assertEq(c.verificationDeadline, deadline, "max-horizon deadline must be stored");
    }
}
