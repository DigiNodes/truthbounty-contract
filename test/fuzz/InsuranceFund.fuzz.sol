// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/insurance/InsuranceFund.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract InsuranceFundFuzzTest is Test {
    InsuranceFund public fund;
    MockToken public token;

    address public admin = address(0x1);
    address public governance = address(0x2);
    address public insuranceManager = address(0x3);
    address public claimant = address(0x4);

    uint256 constant INITIAL_FUND = 100000 * 10**18;

    function setUp() public {
        token = new MockToken();
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
    }

    // ============ Fuzz: Funding ============

    function testFuzz_FundReserve(
        uint256 amount,
        uint8 source
    ) public {
        amount = bound(amount, 1, INITIAL_FUND / 10);
        token.mint(address(this), amount);
        token.approve(address(fund), amount);

        IInsuranceFund.FundingSource fundingSource = IInsuranceFund.FundingSource(source % 5);

        uint256 balanceBefore = token.balanceOf(address(fund));
        vm.expectEmit(true, true, false, true);
        emit IInsuranceFund.InsuranceFunded(address(this), fundingSource, amount);
        fund.fundReserve(fundingSource, amount);
        uint256 balanceAfter = token.balanceOf(address(fund));

        assertEq(balanceAfter, balanceBefore + amount, "Reserve balance mismatch");
        assertEq(
            fund.getFundingTotalBySource(fundingSource),
            (fundingSource == IInsuranceFund.FundingSource.GOVERNANCE ? INITIAL_FUND : 0) + amount
        );
    }

    function testFuzz_FundReserve_ZeroAmountReverts(
        uint8 source
    ) public {
        IInsuranceFund.FundingSource fundingSource = IInsuranceFund.FundingSource(source % 5);
        vm.expectRevert(InsuranceFund.InvalidFundingAmount.selector);
        fund.fundReserve(fundingSource, 0);
    }

    // ============ Fuzz: Claim Submission ============

    function testFuzz_SubmitClaim(
        uint256 requestedAmount,
        uint8 categoryIdx,
        string calldata desc
    ) public {
        requestedAmount = bound(requestedAmount, 1, INITIAL_FUND);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        vm.prank(claimant);
        uint256 claimId = fund.submitClaim(category, requestedAmount, desc);

        assertEq(claimId, 0, "First claim should be ID 0");
        IInsuranceFund.Claim memory claim = fund.getClaim(claimId);
        assertEq(uint256(claim.state), uint256(IInsuranceFund.ClaimState.SUBMITTED));
        assertEq(claim.requestedAmount, requestedAmount);
    }

    function testFuzz_SubmitClaim_ZeroAmountReverts(
        uint8 categoryIdx,
        string calldata desc
    ) public {
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);
        vm.prank(claimant);
        vm.expectRevert(InsuranceFund.InvalidFundingAmount.selector);
        fund.submitClaim(category, 0, desc);
    }

    function testFuzz_SubmitClaim_DuplicateReverts(
        uint256 requestedAmount,
        uint8 categoryIdx,
        string calldata desc
    ) public {
        requestedAmount = bound(requestedAmount, 1, INITIAL_FUND);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        vm.startPrank(claimant);
        fund.submitClaim(category, requestedAmount, desc);

        bytes32 incidentHash = keccak256(abi.encodePacked(claimant, category, requestedAmount, desc));
        vm.expectRevert(abi.encodeWithSelector(InsuranceFund.DuplicateIncident.selector, incidentHash));
        fund.submitClaim(category, requestedAmount, desc);
        vm.stopPrank();
    }

    // ============ Fuzz: Claim Lifecycle ============

    function testFuzz_ApproveAndPayout(
        uint256 requestedAmount,
        uint256 approvedAmount,
        uint8 categoryIdx
    ) public {
        requestedAmount = bound(requestedAmount, 100, INITIAL_FUND / 5);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        // Set max payout high enough
        vm.prank(admin);
        fund.setMaxPayoutPerClaim(INITIAL_FUND);

        // Submit claim
        vm.prank(claimant);
        uint256 claimId = fund.submitClaim(category, requestedAmount, "ipfs://test");

        // Approve with bounded amount
        approvedAmount = bound(approvedAmount, 1, requestedAmount);
        vm.prank(governance);
        fund.reviewAndApproveClaim(claimId, approvedAmount, "ipfs://audit");

        IInsuranceFund.Claim memory claim = fund.getClaim(claimId);
        assertEq(uint256(claim.state), uint256(IInsuranceFund.ClaimState.APPROVED));
        assertEq(claim.approvedAmount, approvedAmount);

        // Fast forward past timelock
        vm.warp(block.timestamp + fund.payoutTimelock() + 1);

        // Execute payout
        uint256 balanceBefore = token.balanceOf(claimant);
        fund.executePayout(claimId);
        uint256 balanceAfter = token.balanceOf(claimant);

        assertEq(balanceAfter, balanceBefore + approvedAmount, "Claimant should receive approved amount");
        assertEq(uint256(fund.getClaim(claimId).state), uint256(IInsuranceFund.ClaimState.PAID));
    }

    function testFuzz_PayoutBeforeTimelockReverts(
        uint256 requestedAmount,
        uint256 approvedAmount,
        uint8 categoryIdx,
        uint256 warpAmount
    ) public {
        requestedAmount = bound(requestedAmount, 100, INITIAL_FUND / 5);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);
        uint256 timelock = fund.payoutTimelock();
        vm.assume(timelock > 0);
        warpAmount = bound(warpAmount, 0, timelock - 1);

        vm.prank(admin);
        fund.setMaxPayoutPerClaim(INITIAL_FUND);

        vm.prank(claimant);
        uint256 claimId = fund.submitClaim(category, requestedAmount, "ipfs://test");

        approvedAmount = bound(approvedAmount, 1, requestedAmount);
        vm.prank(governance);
        fund.reviewAndApproveClaim(claimId, approvedAmount, "ipfs://audit");

        vm.warp(block.timestamp + warpAmount);

        IInsuranceFund.Claim memory claim = fund.getClaim(claimId);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsuranceFund.PayoutTimelockActive.selector,
                claimId,
                claim.submittedAt + fund.payoutTimelock()
            )
        );
        fund.executePayout(claimId);
    }

    // ============ Fuzz: Rejection ============

    function testFuzz_RejectClaim(
        uint256 requestedAmount,
        uint8 categoryIdx,
        string calldata reason
    ) public {
        requestedAmount = bound(requestedAmount, 1, INITIAL_FUND);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        vm.prank(claimant);
        uint256 claimId = fund.submitClaim(category, requestedAmount, "ipfs://test");

        vm.prank(governance);
        fund.rejectClaim(claimId, reason);

        assertEq(uint256(fund.getClaim(claimId).state), uint256(IInsuranceFund.ClaimState.REJECTED));
        assertEq(fund.getActiveClaims().length, 0);
    }

    // ============ Fuzz: Governance Controls ============

    function testFuzz_SetMaxPayoutPerClaim(
        uint256 maxPayout
    ) public {
        maxPayout = bound(maxPayout, 0, type(uint256).max);

        bytes32 policyId = fund.POLICY_MAX_PAYOUT();
        uint256 currentMaxPayout = fund.getMaxPayoutPerClaim();
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IInsuranceFund.InsurancePolicyUpdated(
            policyId,
            currentMaxPayout,
            maxPayout
        );
        fund.setMaxPayoutPerClaim(maxPayout);

        assertEq(fund.getMaxPayoutPerClaim(), maxPayout);
    }

    function testFuzz_SetGlobalUtilizationLimit(
        uint256 limit
    ) public {
        limit = bound(limit, 0, 10000);

        vm.prank(admin);
        fund.setGlobalUtilizationLimit(limit);

        assertEq(fund.getGlobalUtilizationLimit(), limit);
    }

    function testFuzz_SetAllocationPercentage(
        uint256 percentage
    ) public {
        percentage = bound(percentage, 0, 10000);

        vm.prank(admin);
        fund.setAllocationPercentage(percentage);

        assertEq(fund.getAllocationPercentage(), percentage);
    }

    function testFuzz_SetCoverageEnabled(
        uint8 categoryIdx,
        bool enabled
    ) public {
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        vm.prank(admin);
        fund.setCoverageEnabled(category, enabled);

        assertEq(fund.isCoverageEnabled(category), enabled);
    }

    function testFuzz_SetPayoutTimelock(
        uint256 timelock
    ) public {
        timelock = bound(timelock, 0, 30 days);

        vm.prank(admin);
        fund.setPayoutTimelock(timelock);

        assertEq(fund.getPayoutTimelock(), timelock);
    }

    // ============ Fuzz: Access Control ============

    function testFuzz_UnauthorizedActionsRevert(
        address caller,
        uint256 requestedAmount,
        uint8 categoryIdx
    ) public {
        vm.assume(caller != admin && caller != governance && caller != insuranceManager && caller != address(0));
        requestedAmount = bound(requestedAmount, 1, INITIAL_FUND);
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);

        // Non-governance cannot set policies
        vm.prank(caller);
        vm.expectRevert(GovernanceOwnable.UnauthorizedGovernance.selector);
        fund.setMaxPayoutPerClaim(requestedAmount);

        // Non-manager/non-governance cannot update claim state
        vm.prank(claimant);
        uint256 claimId = fund.submitClaim(category, requestedAmount, "ipfs://test");
        vm.prank(caller);
        vm.expectRevert(GovernanceOwnable.UnauthorizedGovernance.selector);
        fund.updateClaimState(claimId, IInsuranceFund.ClaimState.INVESTIGATING);
    }

    // ============ Fuzz: View Functions ============

    function testFuzz_GetReserveMetrics_MultipleClaims(
        uint256[3] calldata amounts,
        uint8 categoryIdx
    ) public {
        IInsuranceFund.CoverageCategory category = IInsuranceFund.CoverageCategory(categoryIdx % 4);
        uint256 totalRequested = 0;

        for (uint256 i = 0; i < 3; i++) {
            uint256 amount = bound(amounts[i], 1, INITIAL_FUND);
            totalRequested += amount;
            vm.prank(claimant);
            fund.submitClaim(category, amount, string(abi.encodePacked("ipfs://", i)));
        }

        IInsuranceFund.ReserveMetrics memory metrics = fund.getReserveMetrics();
        assertEq(metrics.activeClaims, 3, "Should have 3 active claims");
        assertEq(metrics.currentBalance, INITIAL_FUND, "Balance should match funding");
    }
}
