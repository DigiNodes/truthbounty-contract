// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/fees/FeeManager.sol";
import "./FeeManagerHandler.sol";

/**
 * @title FeeManagerInvariant
 * @notice Invariant test suite for FeeManager (SC-028)
 *
 * Invariants verified:
 *  1. Collected fees == distributed fees + retained balance (no funds created or lost)
 *  2. Treasury accounting: per-allocation totals sum to totalFeesDistributed
 *  3. Fee schedules remain valid: active schedules have effectiveAt <= block.timestamp
 *  4. Record count == number of successful collectFee calls
 *  5. Governance version is monotonically non-decreasing
 */
contract FeeManagerInvariant is StdInvariant, Test {
    FeeManager          public feeManager;
    HandlerMockToken    public token;
    FeeManagerHandler   public handler;

    address public admin        = address(0xAD01);
    address public collector    = address(0xC011);
    address public treasury     = address(0xF001);
    address public security     = address(0xF002);
    address public ecosystem    = address(0xF003);
    address public contributors = address(0xF004);
    address public emergency    = address(0xF005);

    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    function setUp() public {
        vm.startPrank(admin);

        token = new HandlerMockToken();

        feeManager = new FeeManager(
            address(token),
            admin,
            address(0),
            treasury,
            security,
            ecosystem,
            contributors,
            emergency
        );

        feeManager.grantRole(COLLECTOR_ROLE, collector);

        vm.stopPrank();

        // Deploy handler outside the prank scope so its internal pranks work
        handler = new FeeManagerHandler(feeManager, token);

        // Target only the handler — the fuzzer will call handler functions
        targetContract(address(handler));
    }

    // ── Invariant 1: Collected == Distributed + Retained ──────────────────────

    /**
     * @notice No fees may be created from nothing or permanently lost.
     *         Every wei collected must either be distributed or retained in contract.
     */
    function invariant_CollectedEqualsDistributedPlusRetained() public {
        uint256 collected   = feeManager.getTotalFeesCollected();
        uint256 distributed = feeManager.getTotalFeesDistributed();
        uint256 retained    = feeManager.getRetainedBalance();

        assertEq(
            collected,
            distributed + retained,
            "INV-1: collected != distributed + retained"
        );
    }

    // ── Invariant 2: Per-allocation totals sum to totalDistributed ────────────

    /**
     * @notice The sum of all per-allocation-target totals must equal
     *         the overall totalFeesDistributed counter.
     */
    function invariant_AllocationTotalsMatchDistributed() public {
        IFeeManager.AllocationTarget[] memory targets = feeManager.getAllocationTargets();
        uint256 sum = 0;
        for (uint256 i = 0; i < targets.length; i++) {
            sum += feeManager.getTotalByAllocation(targets[i].name);
        }

        uint256 totalDistributed = feeManager.getTotalFeesDistributed();
        // Sum may be <= totalDistributed due to dust retained in contract
        assertLe(sum, totalDistributed + 10, "INV-2: allocation sum exceeds distributed");
        assertGe(sum + 10, totalDistributed,  "INV-2: allocation sum far below distributed");
    }

    // ── Invariant 3: Active fee schedules always have effectiveAt <= now ──────

    /**
     * @notice A fee schedule should not be active with a future effectiveAt,
     *         because that would allow governance to stage a future fee
     *         that could silently activate.
     *
     * Note: after an update, effectiveAt is set to block.timestamp; this
     * invariant confirms the contract never ends up with effectiveAt > now.
     */
    function invariant_ActiveSchedulesAreEffective() public {
        bytes32[7] memory types = [
            keccak256("CLAIM_SUBMISSION_FEE"),
            keccak256("CLAIM_UPDATE_FEE"),
            keccak256("VERIFICATION_SUBMISSION_FEE"),
            keccak256("DISPUTE_INITIATION_FEE"),
            keccak256("PROTOCOL_RESERVE_FEE"),
            keccak256("ECOSYSTEM_ALLOCATION_FEE"),
            keccak256("PROTOCOL_SERVICE_FEE")
        ];

        for (uint256 i = 0; i < types.length; i++) {
            IFeeManager.FeeSchedule memory s = feeManager.getFeeSchedule(types[i]);
            if (s.active) {
                assertLe(
                    s.effectiveAt,
                    block.timestamp,
                    "INV-3: active schedule not yet effective"
                );
            }
        }
    }

    // ── Invariant 4: Record count matches ghost counter ───────────────────────

    /**
     * @notice The on-chain fee record count must always match the handler's
     *         ghost counter of successful collect calls.
     */
    function invariant_RecordCountMatchesGhost() public {
        assertEq(
            feeManager.getFeeRecordCount(),
            handler.ghost_collectCount(),
            "INV-4: record count != ghost collect count"
        );
    }

    // ── Invariant 5: Governance version is monotonically non-decreasing ───────

    /**
     * @notice The global governance version must always be >=
     *         the number of schedule updates performed by the handler.
     */
    function invariant_GovernanceVersionMonotone() public {
        assertGe(
            feeManager.globalGovVersion(),
            handler.ghost_scheduleUpdateCount(),
            "INV-5: governance version below update count"
        );
    }

    // ── Invariant 6: Fee schedule basisPoints never exceed denominator ────────

    function invariant_FeeScheduleBpsValid() public {
        bytes32[7] memory types = [
            keccak256("CLAIM_SUBMISSION_FEE"),
            keccak256("CLAIM_UPDATE_FEE"),
            keccak256("VERIFICATION_SUBMISSION_FEE"),
            keccak256("DISPUTE_INITIATION_FEE"),
            keccak256("PROTOCOL_RESERVE_FEE"),
            keccak256("ECOSYSTEM_ALLOCATION_FEE"),
            keccak256("PROTOCOL_SERVICE_FEE")
        ];

        for (uint256 i = 0; i < types.length; i++) {
            IFeeManager.FeeSchedule memory s = feeManager.getFeeSchedule(types[i]);
            assertLe(s.basisPoints, 10_000, "INV-6: basisPoints > 10000");
        }
    }

    // ── Invariant 7: Allocation targets always sum to 10000 bps ──────────────

    function invariant_AllocationTargetsSumTo10000() public {
        IFeeManager.AllocationTarget[] memory targets = feeManager.getAllocationTargets();
        uint256 totalBps = 0;
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i].active) {
                totalBps += targets[i].basisPoints;
            }
        }
        // If there are any active targets, they must sum to exactly 10000
        if (totalBps > 0) {
            assertEq(totalBps, 10_000, "INV-7: allocation targets do not sum to 10000");
        }
    }
}
