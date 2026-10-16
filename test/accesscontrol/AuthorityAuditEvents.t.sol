// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {CrossChainEndpoint} from "../../contracts/crosschain/CrossChainEndpoint.sol";
import {VerifierAssignmentGuard} from "../../contracts/verification/VerifierAssignmentGuard.sol";
import {UpgradeController} from "../../contracts/upgrade/UpgradeController.sol";
import {VersionRegistry} from "../../contracts/upgrade/VersionRegistry.sol";
import {StorageCompatibilityValidator} from "../../contracts/upgrade/StorageCompatibilityValidator.sol";
import {AuthorityAudit} from "../../contracts/libraries/AuthorityAudit.sol";
import {ITruthBountyEvents} from "../../contracts/interfaces/ITruthBountyEvents.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice PREWAVE-SC-071 (#747) — every access-control mutation emits a
///         reconstructable canonical event.
///
///         The suite covers the scenarios the issue requires: single mutation,
///         no-op/duplicate, batch, initialization and upgrade, plus a replay
///         proof in which an indexer starts from a zero-state, consumes only
///         `Authority*V2` logs, and must arrive at the authority map the
///         contracts actually hold.
contract AuthorityAuditEventsTest is Test {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    address internal admin = address(0xA11CE);
    address internal alice = address(0xA11CE0);
    address internal bob = address(0xB0B);

    // ---- Indexer state ----------------------------------------------------
    // A replay has to accumulate into a mutable store, and Solidity forbids
    // mappings in memory. These live in the test contract's own storage, which
    // Foundry zero-initialises for every test, so each indexer below genuinely
    // starts from a zero-state exactly as a fresh indexer would.
    mapping(bytes32 => mapping(address => bool)) internal indexerAuthority;
    mapping(address => bool) internal indexerRelayers;
    mapping(uint256 => bool) internal indexerChains;

    // -----------------------------------------------------------------------
    // 1. Single mutation
    // -----------------------------------------------------------------------

    function _newEndpoint() internal returns (CrossChainEndpoint e) {
        vm.prank(admin);
        e = new CrossChainEndpoint();
    }

    function test_GrantRelayerEmitsCanonicalEvent() public {
        CrossChainEndpoint endpoint = _newEndpoint();
        vm.prank(admin);

        vm.expectEmit(true, true, true, true, address(endpoint));
        emit ITruthBountyEvents.AuthorityGrantedV2(
            AuthorityAudit.ROLE_RELAYER, alice, admin, AuthorityAudit.SOURCE_ADMIN, uint64(block.timestamp), 2
        );
        endpoint.setAuthorizedRelayer(alice, true);
    }

    function test_RevokeRelayerEmitsCanonicalEvent() public {
        CrossChainEndpoint endpoint = _newEndpoint();
        vm.startPrank(admin);
        endpoint.setAuthorizedRelayer(alice, true);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(endpoint));
        emit ITruthBountyEvents.AuthorityRevokedV2(
            AuthorityAudit.ROLE_RELAYER, alice, admin, AuthorityAudit.SOURCE_ADMIN, uint64(block.timestamp), 2
        );
        endpoint.setAuthorizedRelayer(alice, false);
    }

    function test_SetSupportedChainEmitsCanonicalEvent() public {
        CrossChainEndpoint endpoint = _newEndpoint();
        vm.prank(admin);

        vm.expectEmit(true, true, true, true, address(endpoint));
        emit ITruthBountyEvents.AuthorityGrantedV2(
            AuthorityAudit.ROLE_CHAIN,
            address(uint160(8453)),
            admin,
            AuthorityAudit.SOURCE_ADMIN,
            uint64(block.timestamp),
            2
        );
        endpoint.setSupportedChain(8453, true);
    }

    function test_PointerSwapEmitsRevokeThenGrant() public {
        UpgradeController controller =
            new UpgradeController(admin, address(new VersionRegistry(admin)), address(new StorageCompatibilityValidator()));
        address target = address(0xBEEF);

        vm.recordLogs();
        vm.prank(admin);
        controller.setCurrentImplementation(target, alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // First assignment: grant only, there is nothing to revoke.
        assertEq(logs.length, 1, "first assignment must emit exactly one event");
        assertEq(logs[0].topics[0], ITruthBountyEvents.AuthorityGrantedV2.selector, "expected a grant");
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice, "grant subject must be the new impl");
        assertEq(address(uint160(uint256(logs[0].topics[3]))), admin, "grant actor must be the caller");

        vm.recordLogs();
        vm.prank(admin);
        controller.setCurrentImplementation(target, bob);
        logs = vm.getRecordedLogs();

        // Second assignment: revoke the old pointer, then grant the new one.
        assertEq(logs.length, 2, "pointer swap must emit revoke then grant");
        assertEq(logs[0].topics[0], ITruthBountyEvents.AuthorityRevokedV2.selector, "first must be the revoke");
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice, "revoke subject must be the old impl");
        assertEq(logs[1].topics[0], ITruthBountyEvents.AuthorityGrantedV2.selector, "second must be the grant");
        assertEq(address(uint160(uint256(logs[1].topics[2]))), bob, "grant subject must be the new impl");
    }

    // -----------------------------------------------------------------------
    // 2. No-op / duplicate
    // -----------------------------------------------------------------------

    function test_RedundantGrantIsSilent() public {
        CrossChainEndpoint endpoint = _newEndpoint();
        vm.startPrank(admin);
        endpoint.setAuthorizedRelayer(alice, true);

        vm.recordLogs();
        endpoint.setAuthorizedRelayer(alice, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        assertEq(logs.length, 0, "re-granting an authority already held must not log");
        assertTrue(endpoint.authorizedRelayers(alice), "authority must still be held");
    }

    function test_RedundantRevokeIsSilent() public {
        CrossChainEndpoint endpoint = _newEndpoint();

        vm.recordLogs();
        vm.prank(admin);
        endpoint.setAuthorizedRelayer(alice, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0, "revoking an authority never held must not log");
    }

    function test_UnchangedValueUpdateIsSilent() public {
        CrossChainEndpoint endpoint = _newEndpoint();
        vm.startPrank(admin);
        endpoint.setSupportedChain(8453, true);

        vm.recordLogs();
        endpoint.setSupportedChain(8453, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        assertEq(logs.length, 0, "writing an unchanged authority must not log");
    }

    function test_UnauthorizedCallerCannotMutateAndLogsNothing() public {
        CrossChainEndpoint endpoint = _newEndpoint();

        vm.recordLogs();
        vm.prank(alice);
        vm.expectRevert();
        endpoint.setAuthorizedRelayer(bob, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0, "a failed authority mutation must produce no events");
        assertFalse(endpoint.authorizedRelayers(bob), "authority must not have been granted");
    }

    function test_UnauthorizedRoleHolderCannotMutateAndLogsNothing() public {
        VerifierAssignmentGuard guard = new VerifierAssignmentGuard(admin);

        address[] memory verifiers = new address[](1);
        uint256[] memory scores = new uint256[](1);
        verifiers[0] = alice;
        scores[0] = 10;

        vm.recordLogs();
        vm.prank(alice);
        vm.expectRevert();
        guard.registerEligibilitySnapshot(1, block.timestamp + 1 days, verifiers, scores);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0, "a failed authority mutation must produce no events");
    }

    // -----------------------------------------------------------------------
    // 3. Batch
    // -----------------------------------------------------------------------

    function test_BatchEmitsOneEventPerItem() public {
        VerifierAssignmentGuard guard = new VerifierAssignmentGuard(admin);

        address[] memory verifiers = new address[](3);
        uint256[] memory scores = new uint256[](3);
        verifiers[0] = alice;
        verifiers[1] = bob;
        verifiers[2] = address(0xCAFE);
        scores[0] = 10;
        scores[1] = 20;
        scores[2] = 30;

        vm.recordLogs();
        vm.prank(admin);
        guard.registerEligibilitySnapshot(7, block.timestamp + 1 days, verifiers, scores);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3, "a 3-entry batch must emit exactly 3 events");
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(logs[i].topics[0], ITruthBountyEvents.AuthorityGrantedV2.selector, "each item must log a grant");
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                verifiers[i],
                "each event must carry its own subject"
            );
        }
    }

    function test_BatchReRegistrationWithIdenticalEntriesIsSilent() public {
        VerifierAssignmentGuard guard = new VerifierAssignmentGuard(admin);

        address[] memory verifiers = new address[](2);
        uint256[] memory scores = new uint256[](2);
        verifiers[0] = alice;
        verifiers[1] = bob;
        scores[0] = 10;
        scores[1] = 20;

        vm.startPrank(admin);
        guard.registerEligibilitySnapshot(7, block.timestamp + 1 days, verifiers, scores);

        vm.recordLogs();
        guard.registerEligibilitySnapshot(7, block.timestamp + 1 days, verifiers, scores);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        assertEq(logs.length, 0, "re-writing byte-identical entries is a no-op and must not log");
    }

    function test_BatchReRegistrationWithChangedEntryLogsOnlyTheChangedItem() public {
        VerifierAssignmentGuard guard = new VerifierAssignmentGuard(admin);

        address[] memory verifiers = new address[](2);
        uint256[] memory scores = new uint256[](2);
        verifiers[0] = alice;
        verifiers[1] = bob;
        scores[0] = 10;
        scores[1] = 20;

        vm.startPrank(admin);
        guard.registerEligibilitySnapshot(7, block.timestamp + 1 days, verifiers, scores);

        // alice's score is unchanged, bob's moves.
        scores[1] = 99;

        vm.recordLogs();
        guard.registerEligibilitySnapshot(7, block.timestamp + 1 days, verifiers, scores);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        assertEq(logs.length, 1, "only the entry whose authority actually changed may log");
        assertEq(
            address(uint160(uint256(logs[0].topics[2]))), bob, "the changed entry must be the one that logs"
        );
    }

    // -----------------------------------------------------------------------
    // 4. Initialization
    // -----------------------------------------------------------------------

    function test_ConstructorRoleGrantsStillEmitOpenZeppelinEvents() public {
        // The V2 events deliberately do not duplicate what `RoleGranted`
        // already records, so constructor wiring must keep logging unchanged.
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, admin, address(this));
        VerifierAssignmentGuard guard = new VerifierAssignmentGuard(admin);

        assertTrue(guard.hasRole(bytes32(0), admin), "admin role must be granted at construction");
    }

    // -----------------------------------------------------------------------
    // 5. Upgrade
    // -----------------------------------------------------------------------

    function test_UpgradePointerSwapIsReconstructable() public {
        UpgradeController controller =
            new UpgradeController(admin, address(new VersionRegistry(admin)), address(new StorageCompatibilityValidator()));
        address target = address(0xBEEF);

        vm.recordLogs();
        vm.startPrank(admin);
        controller.setCurrentImplementation(target, alice);
        controller.setCurrentImplementation(target, bob);
        controller.setCurrentImplementation(target, address(0));
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Replay this single-holder pointer exactly as an indexer would: a grant moves
        // the holder, a revoke clears whichever subject currently holds it.
        address replayed;
        for (uint256 i = 0; i < logs.length; ++i) {
            address subject = address(uint160(uint256(logs[i].topics[2])));
            bytes32 topic0 = logs[i].topics[0];
            if (topic0 == ITruthBountyEvents.AuthorityGrantedV2.selector) {
                replayed = subject;
            } else if (topic0 == ITruthBountyEvents.AuthorityRevokedV2.selector) {
                if (replayed == subject) replayed = address(0);
            } else {
                revert("unexpected log");
            }
        }

        assertEq(replayed, address(0), "clearing the pointer must leave no grant in effect");
        assertEq(controller.currentImplementation(target), address(0), "storage must agree with the replay");
    }

    // -----------------------------------------------------------------------
    // 6. Replay proof
    // -----------------------------------------------------------------------

    /// @dev The core acceptance criterion. An indexer holds nothing but the
    ///      `Authority*V2` logs. Starting from a zero-state it must arrive at
    ///      exactly the authority map the contracts actually hold — including
    ///      after authority is granted, revoked, re-granted, and written to
    ///      with redundant values that must not disturb the reconstruction.
    function test_ReplayReconstructsAuthorityFromLogsAlone() public {
        CrossChainEndpoint endpoint = _newEndpoint();

        address chainToken = address(0xC4A1A);

        // A deliberately messy sequence: grants, revokes, a revoked-then-
        // re-granted relayer, redundant writes, and a chain toggled off and on.
        // Recording starts BEFORE the first mutation, so the log set below is the
        // complete history an indexer would see from genesis — not a window.
        vm.recordLogs();
        vm.startPrank(admin);
        endpoint.setAuthorizedRelayer(alice, true);
        endpoint.setAuthorizedRelayer(bob, true);
        endpoint.setAuthorizedRelayer(bob, false);
        endpoint.setAuthorizedRelayer(bob, true);
        endpoint.setAuthorizedRelayer(alice, true); // redundant
        endpoint.setSupportedChain(10, true);
        endpoint.setSupportedChain(8453, true);
        endpoint.setSupportedChain(10, false);
        endpoint.setSupportedChain(8453, true); // redundant
        vm.stopPrank();
        Vm.Log[] memory replayLogs = vm.getRecordedLogs();

        // ---- Indexer: zero-state, logs only ------------------------------
        for (uint256 i = 0; i < replayLogs.length; ++i) {
            bytes32 role = replayLogs[i].topics[1];
            address subject = address(uint160(uint256(replayLogs[i].topics[2])));

            if (replayLogs[i].topics[0] == ITruthBountyEvents.AuthorityGrantedV2.selector) {
                indexerAuthority[role][subject] = true;
            } else if (replayLogs[i].topics[0] == ITruthBountyEvents.AuthorityRevokedV2.selector) {
                indexerAuthority[role][subject] = false;
            } else {
                revert("unexpected log: replay cannot reconstruct from this event");
            }
        }

        // ---- Compare against the authority the contracts actually hold -----
        // The redundant writes in the sequence must not have disturbed the
        // reconstruction: a correct replay still lands on live storage.
        assertTrue(
            indexerAuthority[AuthorityAudit.ROLE_RELAYER][alice],
            "replay must recover alice's relayer grant"
        );
        assertTrue(
            indexerAuthority[AuthorityAudit.ROLE_RELAYER][bob],
            "replay must recover bob's relayer after revoke-then-regrant"
        );
        assertFalse(
            indexerAuthority[AuthorityAudit.ROLE_CHAIN][address(uint160(10))],
            "replay must recover the revocation of chain 10"
        );
        assertTrue(
            indexerAuthority[AuthorityAudit.ROLE_CHAIN][address(uint160(8453))],
            "replay must recover the chain 8453 grant"
        );

        // Every entry must agree with storage, not just the four asserted above.
        assertEq(
            indexerAuthority[AuthorityAudit.ROLE_RELAYER][alice],
            endpoint.authorizedRelayers(alice),
            "replay must match live relayer storage"
        );
        assertEq(
            indexerAuthority[AuthorityAudit.ROLE_RELAYER][bob],
            endpoint.authorizedRelayers(bob),
            "replay must match live relayer storage"
        );
        assertEq(
            indexerAuthority[AuthorityAudit.ROLE_CHAIN][address(uint160(10))],
            endpoint.supportedChains(10),
            "replay must match live chain storage"
        );
        assertEq(
            indexerAuthority[AuthorityAudit.ROLE_CHAIN][address(uint160(8453))],
            endpoint.supportedChains(8453),
            "replay must match live chain storage"
        );

        _assertFullHistoryReplayMatchesStorage(chainToken);
    }

    /// @dev Replays every mutation from a freshly deployed endpoint and checks
    ///      the reconstructed map against the live getters, entry by entry.
    ///      The endpoint is deployed inside so that the replayed log window and
    ///      the storage being compared describe the same history.
    function _assertFullHistoryReplayMatchesStorage(address chainToken) internal {
        CrossChainEndpoint endpoint = _newEndpoint();
        address[] memory relayers = new address[](4);
        relayers[0] = alice;
        relayers[1] = bob;
        relayers[2] = chainToken;
        relayers[3] = address(0xD00D);

        uint256[] memory chains = new uint256[](4);
        chains[0] = 10;
        chains[1] = 42161;
        chains[2] = 8453;
        chains[3] = 137;

        vm.recordLogs();
        vm.startPrank(admin);
        for (uint256 i = 0; i < relayers.length; ++i) {
            endpoint.setAuthorizedRelayer(relayers[i], true);
            endpoint.setAuthorizedRelayer(relayers[i], true); // redundant, must not log
            endpoint.setSupportedChain(chains[i], true);
        }
        endpoint.setAuthorizedRelayer(bob, false);
        endpoint.setAuthorizedRelayer(alice, false);
        endpoint.setSupportedChain(42161, false);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        
        

        for (uint256 i = 0; i < logs.length; ++i) {
            bytes32 role = logs[i].topics[1];
            address topic = address(uint160(uint256(logs[i].topics[2])));
            bool grant = logs[i].topics[0] == ITruthBountyEvents.AuthorityGrantedV2.selector;

            if (role == AuthorityAudit.ROLE_RELAYER) {
                indexerRelayers[topic] = grant;
            } else if (role == AuthorityAudit.ROLE_CHAIN) {
                indexerChains[uint160(topic)] = grant;
            } else {
                revert("replay encountered an out-of-scope role");
            }
        }

        for (uint256 i = 0; i < relayers.length; ++i) {
            assertEq(
                indexerRelayers[relayers[i]],
                endpoint.authorizedRelayers(relayers[i]),
                "replayed relayer authority must match storage"
            );
        }
        for (uint256 i = 0; i < chains.length; ++i) {
            assertEq(indexerChains[chains[i]], endpoint.supportedChains(chains[i]), "replayed chain authority must match storage");
        }
    }

    function test_RoleAccountAndActorAreTheThreeIndexedTopics() public {
        // Guards the ≤3-indexed invariant: role, subject, actor occupy the
        // topics, and `source` must stay in the data word so it is not indexed.
        CrossChainEndpoint endpoint = _newEndpoint();

        vm.recordLogs();
        vm.prank(admin);
        endpoint.setAuthorizedRelayer(alice, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1, "expected one log");
        assertEq(logs[0].topics.length, 4, "topic0 plus exactly three indexed arguments");
        assertEq(logs[0].topics[1], AuthorityAudit.ROLE_RELAYER, "topic1 is the role");
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice, "topic2 is the subject");
        assertEq(address(uint160(uint256(logs[0].topics[3]))), admin, "topic3 is the actor");

        (uint8 source, uint64 timestamp, uint16 version) =
            abi.decode(logs[0].data, (uint8, uint64, uint16));
        assertEq(source, AuthorityAudit.SOURCE_ADMIN, "source must decode from the data word");
        assertEq(timestamp, block.timestamp, "timestamp must decode from the data word");
        assertEq(version, 2, "version must decode from the data word");
    }

    function test_NoSecretDataIsEmitted() public {
        // Every emitted parameter must be a public identifier: a role hash, an
        // address, or a small discriminator. Nothing here can carry key material.
        CrossChainEndpoint endpoint = _newEndpoint();

        vm.recordLogs();
        vm.startPrank(admin);
        endpoint.setAuthorizedRelayer(alice, true);
        endpoint.setSupportedChain(8453, true);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; ++i) {
            assertEq(logs[i].emitter, address(endpoint), "events must come from the contract under audit");
            assertLe(logs[i].data.length, 96, "data word must only hold source, timestamp and version");
        }
    }
}