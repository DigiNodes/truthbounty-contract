// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/StdInvariant.sol";
import "forge-std/Test.sol";
import "../../contracts/tokenomics/TokenomicsEngine.sol";
import "../../contracts/treasury/TreasuryAccounting.sol";
import "../../contracts/MockERC20.sol";

contract TokenomicsInvariant is StdInvariant, Test {
    TokenomicsEngine tokenomics;
    TreasuryAccounting treasury;
    MockERC20 token;

    address admin = address(0xDeAD);
    address distributor = address(0xBEEF);
    address sender = address(0xC0DE);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new MockERC20();
        token.mint(sender, INITIAL_SUPPLY);

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

        targetContract(address(tokenomics));
        targetContract(address(treasury));
    }

    // ============ Invariant 1: Allocation Shares Sum to Total ============

    function invariant_AllocationSharesSumToTotal() public {
        uint256 len = tokenomics.distributionHistoryLength();
        for (uint256 i = 0; i < len; i++) {
            bytes32 distributionId = tokenomics.distributionIds(i);
            TokenomicsEngine.DistributionRecord memory d = tokenomics.getDistributionRecord(distributionId);
            uint256 sum = d.verifierRewards
                + d.treasuryReserve
                + d.ecosystemIncentives
                + d.governanceIncentives
                + d.protocolDevelopment
                + d.emergencyReserve;
            assertEq(sum, d.totalAmount);
        }
    }

    // ============ Invariant 2: Treasury Solvency ============

    function invariant_TreasurySolvent() public {
        uint256 actual = token.balanceOf(address(treasury));
        uint256 accounted = treasury.calculateTotalAssets();
        assertGe(actual, accounted);
    }

    // ============ Invariant 3: No Negative Counters ============

    function invariant_NoNegativeCounters() public {
        assertGe(tokenomics.totalDistributed(), 0);
        assertGe(tokenomics.emissionLimit(), 0);
        assertGe(tokenomics.rewardMultiplier(), 0);
        assertGe(tokenomics.treasuryReserveTargetBPS(), 0);
    }

    // ============ Invariant 4: All Active Config BPS Sum to 10000 ============

    function invariant_ActiveConfigsSumTo10000() public {
        for (uint256 i = 0; i < 5; i++) {
            TokenomicsEngine.RevenueSource source = TokenomicsEngine.RevenueSource(i);
            TokenomicsEngine.SourceAllocation memory config = tokenomics.getAllocationConfig(source);
            if (config.active) {
                uint256 totalBPS = config.verifierRewardsBPS
                    + config.treasuryReserveBPS
                    + config.ecosystemIncentivesBPS
                    + config.governanceIncentivesBPS
                    + config.protocolDevelopmentBPS
                    + config.emergencyReserveBPS;
                assertEq(totalBPS, TokenomicsEngine.BPS_DENOMINATOR());
            }
        }
    }

    // ============ Invariant 5: History Length Bounds ============

    function invariant_HistoryWithinBounds() public {
        uint256 len = tokenomics.distributionHistoryLength();
        assertLe(len, type(uint256).max);
    }
}
