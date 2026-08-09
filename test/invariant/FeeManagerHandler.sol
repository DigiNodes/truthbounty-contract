// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/fees/FeeManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title FeeManagerHandler
 * @notice Stateful handler for FeeManager invariant testing.
 *
 * The invariant test suite targets this handler contract. Each public
 * function represents an action the fuzzer can take. Ghost variables
 * mirror the expected on-chain state so the invariant suite can compare
 * them without reading every storage slot.
 */
contract FeeManagerHandler is Test {
    // ── Contracts ──────────────────────────────────────────────────────────────

    FeeManager       public feeManager;
    HandlerMockToken public token;

    // ── Actors ────────────────────────────────────────────────────────────────

    address public admin     = address(0xAD01);
    address public collector = address(0xC011);

    address[] public payers;

    // ── Ghost Variables ────────────────────────────────────────────────────────

    /// @notice Total fee amount deposited via handler calls
    uint256 public ghost_totalDeposited;

    /// @notice Number of collect calls made
    uint256 public ghost_collectCount;

    /// @notice Number of schedule update calls made
    uint256 public ghost_scheduleUpdateCount;

    // ── Constants ─────────────────────────────────────────────────────────────

    bytes32 public constant CLAIM_SUBMISSION_FEE = keccak256("CLAIM_SUBMISSION_FEE");
    bytes32 public constant CLAIM_UPDATE_FEE      = keccak256("CLAIM_UPDATE_FEE");
    bytes32 public constant VERIFICATION_FEE      = keccak256("VERIFICATION_SUBMISSION_FEE");
    bytes32 public constant COLLECTOR_ROLE        = keccak256("COLLECTOR_ROLE");

    bytes32[] internal feeTypes;

    // ── Constructor ────────────────────────────────────────────────────────────

    constructor(FeeManager _feeManager, HandlerMockToken _token) {
        feeManager = _feeManager;
        token      = _token;

        payers.push(address(0xAB01));
        payers.push(address(0xAB02));
        payers.push(address(0xAB03));

        feeTypes.push(CLAIM_SUBMISSION_FEE);
        feeTypes.push(CLAIM_UPDATE_FEE);
        feeTypes.push(VERIFICATION_FEE);

        // Mint tokens to payers and approve feeManager
        for (uint256 i = 0; i < payers.length; i++) {
            token.mint(payers[i], 1_000_000e18);
            vm.prank(payers[i]);
            token.approve(address(feeManager), type(uint256).max);
        }
    }

    // ── Handler Actions ────────────────────────────────────────────────────────

    /**
     * @notice Collect a fee as a protocol module
     */
    function collectFee(
        uint256 payerSeed,
        uint256 feeTypeSeed,
        uint256 amount
    ) public {
        amount = bound(amount, 1e15, 10_000e18);

        address payer    = payers[payerSeed % payers.length];
        bytes32 feeType  = feeTypes[feeTypeSeed % feeTypes.length];

        // Ensure the fee type is active
        IFeeManager.FeeSchedule memory schedule = feeManager.getFeeSchedule(feeType);
        if (!schedule.active) return;

        // Check payer has enough balance
        if (token.balanceOf(payer) < amount) return;

        ghost_totalDeposited += amount;
        ghost_collectCount++;

        vm.prank(collector);
        try feeManager.collectFee(feeType, payer, amount) {} catch {
            ghost_totalDeposited -= amount;
            ghost_collectCount--;
        }
    }

    /**
     * @notice Update a fee schedule through governance
     */
    function updateFeeSchedule(
        uint256 feeTypeSeed,
        uint256 fixedAmount,
        uint256 bps,
        uint256 minVal
    ) public {
        fixedAmount = bound(fixedAmount, 0, 100e18);
        bps         = bound(bps, 0, 10000);
        minVal      = bound(minVal, 0, 10e18);
        bytes32 feeType = feeTypes[feeTypeSeed % feeTypes.length];

        ghost_scheduleUpdateCount++;

        vm.prank(admin);
        try feeManager.updateFeeSchedule(feeType, fixedAmount, bps, minVal, 0) {} catch {
            ghost_scheduleUpdateCount--;
        }
    }

    /**
     * @notice Toggle a fee type active/inactive
     */
    function toggleFeeActive(uint256 feeTypeSeed, bool active) public {
        bytes32 feeType = feeTypes[feeTypeSeed % feeTypes.length];
        vm.prank(admin);
        try feeManager.setFeeActive(feeType, active) {} catch {}
    }
}

// ── Mock Token ────────────────────────────────────────────────────────────────

contract HandlerMockToken is ERC20 {
    constructor() ERC20("HandlerToken", "HT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
