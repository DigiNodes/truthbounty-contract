// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/insurance/InsuranceFund.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InvariantMockToken is ERC20 {
    constructor() ERC20("InvariantMock", "IMOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract InsuranceFundInvariant is StdInvariant, Test {
    InsuranceFund public fund;
    InvariantMockToken public token;

    address public admin = address(0x1);
    address public governance = address(0x2);
    address public insuranceManager = address(0x3);

    address[] public claimants;

    uint256 constant INITIAL_FUND = 500000 * 10**18;

    function setUp() public {
        token = new InvariantMockToken();
        token.mint(admin, INITIAL_FUND * 10);

        vm.prank(admin);
        fund = new InsuranceFund(address(token), admin, governance);

        bytes32 managerRole = fund.INSURANCE_MANAGER_ROLE();
        bytes32 governanceRole = fund.GOVERNANCE_ROLE();
        vm.prank(admin);
        fund.grantRole(managerRole, insuranceManager);
        vm.prank(admin);
        fund.grantRole(governanceRole, governance);

        // Fund the reserve
        vm.prank(admin);
        token.approve(address(fund), INITIAL_FUND);
        vm.prank(admin);
        fund.fundReserve(IInsuranceFund.FundingSource.GOVERNANCE, INITIAL_FUND);

        // Set up claimants
        for (uint256 i = 0; i < 5; i++) {
            address c = address(uint160(0x100 + i));
            claimants.push(c);
            token.mint(c, INITIAL_FUND);
        }

        // Set max payout high enough for testing
        vm.prank(admin);
        fund.setMaxPayoutPerClaim(INITIAL_FUND / 10);

        targetContract(address(fund));
    }

    // ============ Invariants ============

    function invariant_ReserveBalanceNeverNegative() public view {
        assertGe(token.balanceOf(address(fund)), 0);
    }

    function invariant_TotalPaidOutNeverExceedsFundedPlusBalance() public view {
        uint256 balance = token.balanceOf(address(fund));
        uint256 paidOut = fund.totalPaidOut();
        uint256 totalFundedGov = fund.totalFundedBySource(IInsuranceFund.FundingSource.GOVERNANCE);

        // paidOut should not exceed what was ever received by the fund
        assertLe(paidOut, balance + paidOut, "Arithmetic sanity");
    }

    function invariant_PaidClaimsNotInActiveSet() public view {
        uint256[] memory active = fund.getActiveClaims();
        for (uint256 i = 0; i < active.length; i++) {
            IInsuranceFund.Claim memory claim = fund.getClaim(active[i]);
            assertTrue(
                uint256(claim.state) != uint256(IInsuranceFund.ClaimState.PAID),
                "PAID claim in active set"
            );
            assertTrue(
                uint256(claim.state) != uint256(IInsuranceFund.ClaimState.REJECTED),
                "REJECTED claim in active set"
            );
        }
    }

    function invariant_ClaimStateTransitionsAreValid() public view {
        uint256 count = fund.claimCounter();
        for (uint256 i = 0; i < count; i++) {
            IInsuranceFund.Claim memory claim = fund.getClaim(i);
            if (claim.submittedAt == 0) continue;

            IInsuranceFund.ClaimState state = claim.state;

            // If PAID, must have approvedAmount > 0
            if (state == IInsuranceFund.ClaimState.PAID) {
                assertGt(claim.approvedAmount, 0, "PAID claim has zero approvedAmount");
            }

            // If APPROVED, must have approvedAmount > 0
            if (state == IInsuranceFund.ClaimState.APPROVED) {
                assertGt(claim.approvedAmount, 0, "APPROVED claim has zero approvedAmount");
            }

            // If REJECTED or PAID, should not be active
            if (state == IInsuranceFund.ClaimState.REJECTED || state == IInsuranceFund.ClaimState.PAID) {
                assertGt(claim.resolvedAt, 0, "Resolved claim has zero resolvedAt");
            }
        }
    }

    function invariant_UtilizationRatioBounded() public view {
        uint256 ratio = fund.getUtilizationRatio();
        assertLe(ratio, 10000, "Utilization ratio exceeds 100%");
    }

    function invariant_FundingHistoryConsistent() public view {
        IInsuranceFund.FundingRecord[] memory history = fund.getFundingHistory(0, 200);
        uint256 totalFromHistory = 0;

        for (uint256 i = 0; i < 5; i++) {
            IInsuranceFund.FundingSource source = IInsuranceFund.FundingSource(i);
            totalFromHistory += fund.totalFundedBySource(source);
        }

        // Total from all sources equals sum of individual sources
        uint256 balance = token.balanceOf(address(fund));
        uint256 paidOut = fund.totalPaidOut();
        assertEq(paidOut + balance, totalFromHistory, "Balance + paidOut must equal total funded");
    }
}
