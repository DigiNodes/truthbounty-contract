// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/v2/interfaces/IV2Types.sol";
import "../../contracts/v2/libraries/V2Lifecycle.sol";
import "../../contracts/v2/libraries/ProtocolModel.sol";

contract ProtocolModelHarness {
    function splitInvalid(uint8 roundingPolicy) external pure returns (uint256) {
        return ProtocolModel.splitAmount(100, 5000, roundingPolicy);
    }
}

contract ProtocolModelDifferentialTest is Test {
    ProtocolModelHarness internal harness;

    function setUp() public {
        harness = new ProtocolModelHarness();
    }

    function test_claimLifecycle_matches_reference_model() public {
        for (uint256 i = 0; i <= uint256(type(IV2Types.ClaimState).max); ++i) {
            IV2Types.ClaimState current = IV2Types.ClaimState(i);
            for (uint256 j = 0; j <= uint256(type(IV2Types.ClaimState).max); ++j) {
                IV2Types.ClaimState next = IV2Types.ClaimState(j);
                bool model = ProtocolModel.isValidClaimTransition(current, next);
                bool actual = V2Lifecycle.isValidClaimTransition(current, next);
                assertEq(actual, model, "claim lifecycle mismatch");
            }
        }
    }

    function test_evidenceLifecycle_matches_reference_model() public {
        for (uint256 i = 0; i <= uint256(type(IV2Types.EvidenceStatus).max); ++i) {
            IV2Types.EvidenceStatus current = IV2Types.EvidenceStatus(i);
            for (uint256 j = 0; j <= uint256(type(IV2Types.EvidenceStatus).max); ++j) {
                IV2Types.EvidenceStatus next = IV2Types.EvidenceStatus(j);
                bool model = ProtocolModel.isValidEvidenceTransition(current, next);
                bool actual = V2Lifecycle.isValidEvidenceTransition(current, next);
                assertEq(actual, model, "evidence lifecycle mismatch");
            }
        }
    }

    function test_disputeLifecycle_matches_reference_model() public {
        for (uint256 i = 0; i <= uint256(type(IV2Types.DisputeStatus).max); ++i) {
            IV2Types.DisputeStatus current = IV2Types.DisputeStatus(i);
            for (uint256 j = 0; j <= uint256(type(IV2Types.DisputeStatus).max); ++j) {
                IV2Types.DisputeStatus next = IV2Types.DisputeStatus(j);
                bool model = ProtocolModel.isValidDisputeTransition(current, next);
                bool actual = V2Lifecycle.isValidDisputeTransition(current, next);
                assertEq(actual, model, "dispute lifecycle mismatch");
            }
        }
    }

    function test_settlementLifecycle_matches_reference_model() public {
        for (uint256 i = 0; i <= uint256(type(IV2Types.SettlementStatus).max); ++i) {
            IV2Types.SettlementStatus current = IV2Types.SettlementStatus(i);
            for (uint256 j = 0; j <= uint256(type(IV2Types.SettlementStatus).max); ++j) {
                IV2Types.SettlementStatus next = IV2Types.SettlementStatus(j);
                bool model = ProtocolModel.isValidSettlementTransition(current, next);
                bool actual = V2Lifecycle.isValidSettlementTransition(current, next);
                assertEq(actual, model, "settlement lifecycle mismatch");
            }
        }
    }

    function test_roundingAndRewardSplits_match_reference_model() public {
        assertEq(ProtocolModel.splitAmount(10, 3333, 0), 3, "floor rounding mismatch");
        assertEq(ProtocolModel.splitAmount(10, 3333, 1), 4, "ceil rounding mismatch");
        assertEq(ProtocolModel.splitAmount(10, 3333, 2), 3, "half-up rounding mismatch");

        (uint256 verifierReward, uint256 treasuryCut) = ProtocolModel.rewardSplit(1_000, 8000, 0);
        assertEq(verifierReward, 800, "reward split mismatch");
        assertEq(treasuryCut, 200, "treasury split mismatch");

        assertTrue(ProtocolModel.isClaimOpen(IV2Types.ClaimState.VerificationOpen), "claim open model mismatch");
        assertTrue(ProtocolModel.isClaimVerified(IV2Types.ClaimState.AwaitingSettlement), "claim verified model mismatch");
        assertTrue(ProtocolModel.isClaimDisputed(IV2Types.ClaimState.Disputed), "claim disputed model mismatch");
        assertTrue(ProtocolModel.isTerminalSettlementStatus(IV2Types.SettlementStatus.EXECUTED), "terminal settlement mismatch");
    }

    function test_invalid_rounding_policy_and_terminal_transitions_revert() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolModel.InvalidRoundingPolicy.selector, 3));
        harness.splitInvalid(3);

        assertFalse(ProtocolModel.isValidClaimTransition(IV2Types.ClaimState.Finalized, IV2Types.ClaimState.VerificationOpen));
        assertFalse(ProtocolModel.isValidEvidenceTransition(IV2Types.EvidenceStatus.REJECTED, IV2Types.EvidenceStatus.SUBMITTED));
        assertFalse(ProtocolModel.isValidDisputeTransition(IV2Types.DisputeStatus.RESOLVED, IV2Types.DisputeStatus.OPEN));
        assertFalse(ProtocolModel.isValidSettlementTransition(IV2Types.SettlementStatus.EXECUTED, IV2Types.SettlementStatus.PENDING));
    }

    function test_v2Lifecycle_matches_reference_model_for_all_state_pairs() public {
        for (uint256 i = 0; i <= uint256(type(IV2Types.ClaimState).max); ++i) {
            IV2Types.ClaimState current = IV2Types.ClaimState(i);
            for (uint256 j = 0; j <= uint256(type(IV2Types.ClaimState).max); ++j) {
                IV2Types.ClaimState next = IV2Types.ClaimState(j);
                assertEq(
                    V2Lifecycle.isValidClaimTransition(current, next),
                    ProtocolModel.isValidClaimTransition(current, next),
                    "reference-vs-implementation mismatch"
                );
            }
        }
    }
}
