// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/Fuzz.sol";
import "../../contracts/tokenomics/TokenomicsEngine.sol";
import "../../contracts/treasury/TreasuryAccounting.sol";
import "../../contracts/MockERC20.sol";

interface ITokenomicsEngineView {
    function sourceAllocations(uint256)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        );
}

contract TokenomicsFuzzTest is Test, Fuzz {
    TokenomicsEngine tokenomics;
    TreasuryAccounting treasury;
    MockERC20 token;

    address admin = address(0xDeAD);
    address distributor = address(0xBEEF);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new MockERC20();
        token.mint(address(this), INITIAL_SUPPLY);

        treasury = new TreasuryAccounting(
            address(token),
            address(0),
            admin
        );

        vm.startPrank(admin);
        treasury.grantRole(treasury.ADMIN_ROLE(), distributor);
        treasury.grantRole(treasury.TREASURY_MANAGER_ROLE(), admin);
        vm.stopPrank();

        tokenomics = new TokenomicsEngine(
            address(treasury),
            address(token),
            admin,
            address(0)
        );

        vm.startPrank(admin);
        tokenomics.grantRole(tokenomics.DISTRIBUTOR_ROLE(), distributor);
        vm.stopPrank();
    }

    // ============ Fuzz: Allocation BPS Summation ============

    function testFuzz_AllocationConfig_ValidBPSSummation(
        uint256 verifier,
        uint256 treasury,
        uint256 ecosystem,
        uint256 governance,
        uint256 protocol,
        uint256 emergency
    ) external {
        // Clamp each to valid BPS range
        verifier = bound(verifier, 0, 10000);
        treasury = bound(treasury, 0, 10000);
        ecosystem = bound(ecosystem, 0, 10000);
        governance = bound(governance, 0, 10000);
        protocol = bound(protocol, 0, 10000);
        emergency = bound(emergency, 0, 10000);

        // Only test valid configurations
        if (
            verifier + treasury + ecosystem + governance + protocol + emergency != 10000
        ) {
            return;
        }

        vm.startPrank(admin);
        TokenomicsEngine.SourceAllocation memory config = TokenomicsEngine.SourceAllocation({
            verifierRewardsBPS: verifier,
            treasuryReserveBPS: treasury,
            ecosystemIncentivesBPS: ecosystem,
            governanceIncentivesBPS: governance,
            protocolDevelopmentBPS: protocol,
            emergencyReserveBPS: emergency,
            active: true
        });
        tokenomics.setSourceAllocation(
            TokenomicsEngine.RevenueSource.PROTOCOL_FEES,
            config
        );
        vm.stopPrank();

        TokenomicsEngine.SourceAllocation memory stored = tokenomics.getAllocationConfig(
            TokenomicsEngine.RevenueSource.PROTOCOL_FEES
        );
        assertEq(stored.verifierRewardsBPS, verifier);
        assertEq(stored.treasuryReserveBPS, treasury);
        assertEq(stored.ecosystemIncentivesBPS, ecosystem);
        assertEq(stored.governanceIncentivesBPS, governance);
        assertEq(stored.protocolDevelopmentBPS, protocol);
        assertEq(stored.emergencyReserveBPS, emergency);
    }

    // ============ Fuzz: Distribution Amounts ============

    function testFuzz_DistributeRevenue_RandomAmounts(
        uint256 amount
    ) external {
        amount = bound(amount, 1, INITIAL_SUPPLY / 10);

        vm.startPrank(admin);
        vm.deal(address(token), INITIAL_SUPPLY - token.balanceOf(address(this)));
        token.mint(address(this), amount);
        vm.stopPrank();

        vm.startPrank(address(this));
        token.approve(address(tokenomics), amount);
        vm.stopPrank();

        vm.startPrank(distributor);
        bytes32 distributionId = tokenomics.distributeRevenue(
            TokenomicsEngine.RevenueSource.PROTOCOL_FEES,
            amount
        );
        vm.stopPrank();

        TokenomicsEngine.DistributionRecord memory record = tokenomics.getDistributionRecord(distributionId);
        assertEq(record.totalAmount, amount);

        uint256 sum = record.verifierRewards
            + record.treasuryReserve
            + record.ecosystemIncentives
            + record.governanceIncentives
            + record.protocolDevelopment
            + record.emergencyReserve;
        assertEq(sum, amount);
    }

    // ============ Fuzz: Multi-Source Batch ============

    function testFuzz_AllocateBatch_RandomSources(
        uint256 count,
        uint256 totalAmount
    ) external {
        count = bound(count, 1, 5);
        totalAmount = bound(totalAmount, 1, INITIAL_SUPPLY / 10);

        TokenomicsEngine.RevenueSource[] memory sources = new TokenomicsEngine.RevenueSource[](count);
        uint256[] memory amounts = new uint256[](count);

        uint256 perSource = totalAmount / count;
        uint256 remainder = totalAmount % count;

        for (uint256 i = 0; i < count; i++) {
            sources[i] = TokenomicsEngine.RevenueSource(i);
            amounts[i] = i < remainder ? perSource + 1 : perSource;
        }

        vm.startPrank(admin);
        vm.deal(address(token), INITIAL_SUPPLY - token.balanceOf(address(this)));
        token.mint(address(this), totalAmount);
        vm.stopPrank();

        vm.startPrank(address(this));
        token.approve(address(tokenomics), totalAmount);
        vm.stopPrank();

        vm.startPrank(distributor);
        bytes32[] memory distributionIds = tokenomics.allocateBatch(sources, amounts);
        vm.stopPrank();

        assertEq(distributionIds.length, count);
        assertEq(tokenomics.totalDistributed(), totalAmount);
    }

    // ============ Fuzz: Emission Limit Enforcement ============

    function testFuzz_EmissionLimit_RandomLimits(
        uint256 limit,
        uint256 attempt1,
        uint256 attempt2
    ) external {
        limit = bound(limit, 1, 10_000e18);
        attempt1 = bound(attempt1, 1, 10_000e18);
        attempt2 = bound(attempt2, 1, 10_000e18);

        vm.startPrank(admin);
        tokenomics.setEmissionLimit(limit);
        vm.stopPrank();

        uint256 totalAttempted = attempt1 + attempt2;

        vm.startPrank(admin);
        vm.deal(address(token), INITIAL_SUPPLY - token.balanceOf(address(this)));
        token.mint(address(this), totalAttempted);
        vm.stopPrank();

        vm.startPrank(address(this));
        token.approve(address(tokenomics), totalAttempted);
        vm.stopPrank();

        vm.startPrank(distributor);

        if (attempt1 <= limit) {
            tokenomics.distributeRevenue(TokenomicsEngine.RevenueSource.PROTOCOL_FEES, attempt1);
        } else {
            vm.expectRevert(TokenomicsEngine.EmissionLimitExceeded.selector);
            tokenomics.distributeRevenue(TokenomicsEngine.RevenueSource.PROTOCOL_FEES, attempt1);
        }

        if (attempt1 + attempt2 > limit && attempt1 <= limit) {
            vm.expectRevert(TokenomicsEngine.EmissionLimitExceeded.selector);
            tokenomics.distributeRevenue(TokenomicsEngine.RevenueSource.PROTOCOL_FEES, attempt2);
        }

        vm.stopPrank();
    }

    // ============ Fuzz: Reward Multiplier ============

    function testFuzz_RewardMultiplier_RandomMultipliers(
        uint256 multiplier,
        uint256 amount
    ) external {
        multiplier = bound(multiplier, 1, 5e18);
        amount = bound(amount, 1, INITIAL_SUPPLY / 10);

        vm.startPrank(admin);
        tokenomics.setRewardMultiplier(multiplier);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.deal(address(token), INITIAL_SUPPLY - token.balanceOf(address(this)));
        token.mint(address(this), amount);
        vm.stopPrank();

        vm.startPrank(address(this));
        token.approve(address(tokenomics), amount);
        vm.stopPrank();

        vm.startPrank(distributor);
        bytes32 distributionId = tokenomics.distributeRevenue(
            TokenomicsEngine.RevenueSource.PROTOCOL_FEES,
            amount
        );
        vm.stopPrank();

        TokenomicsEngine.DistributionRecord memory record = tokenomics.getDistributionRecord(distributionId);

        // Base verifier reward for PROTOCOL_FEES is 4000 BPS
        uint256 expectedVerifierRewards = (amount * 4000 * multiplier) / (10000 * 1e18);
        assertEq(record.verifierRewards, expectedVerifierRewards);
    }

    // ============ Fuzz: Deterministic Distribution IDs ============

    function testFuzz_DistributionId_Deterministic(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000e18);

        vm.startPrank(admin);
        vm.deal(address(token), INITIAL_SUPPLY - token.balanceOf(address(this)));
        token.mint(address(this), amount);
        vm.stopPrank();

        vm.startPrank(address(this));
        token.approve(address(tokenomics), amount);
        vm.stopPrank();

        vm.startPrank(distributor);
        bytes32 id1 = tokenomics.distributeRevenue(TokenomicsEngine.RevenueSource.PROTOCOL_FEES, amount);
        bytes32 id2 = tokenomics.distributeRevenue(TokenomicsEngine.RevenueSource.TREASURY_ALLOCATION, amount);
        vm.stopPrank();

        assertTrue(id1 != id2, "IDs must be unique across sources");
    }

    // ============ Fuzz: BPS Validation ============

    function testFuzz_InvalidBPSConfiguration_Reverts(
        uint256 verifier,
        uint256 treasury,
        uint256 ecosystem,
        uint256 governance,
        uint256 protocol,
        uint256 emergency
    ) external {
        // Only test configurations that do NOT sum to 10000
        uint256 total = verifier + treasury + ecosystem + governance + protocol + emergency;
        // Clamp to ensure we don't hit overflow, and only test invalid configs
        if (total == 10000) return;

        vm.startPrank(admin);
        TokenomicsEngine.SourceAllocation memory config = TokenomicsEngine.SourceAllocation({
            verifierRewardsBPS: bound(verifier, 1, 9999),
            treasuryReserveBPS: bound(treasury, 1, 9999),
            ecosystemIncentivesBPS: bound(ecosystem, 1, 9999),
            governanceIncentivesBPS: bound(governance, 1, 9999),
            protocolDevelopmentBPS: bound(protocol, 1, 9999),
            emergencyReserveBPS: bound(emergency, 1, 9999),
            active: true
        });
        vm.expectRevert(TokenomicsEngine.AllocationConfigInvalid.selector);
        tokenomics.setSourceAllocation(
            TokenomicsEngine.RevenueSource.PROTOCOL_FEES,
            config
        );
        vm.stopPrank();
    }
}
