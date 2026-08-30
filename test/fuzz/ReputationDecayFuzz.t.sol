// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ReputationDecay.sol";

contract ReputationDecayFuzzTest is Test {
    ReputationDecay public decay;

    address public owner = address(0x1);
    address public oracle = address(0x2);
    address public verifier = address(0x3);

    uint256 public constant ONE_WEEK = 7 * 86400;
    uint256 public constant BASIS_POINTS = 10000;

    function setUp() public {
        vm.startPrank(owner);
        decay = new ReputationDecay(owner);
        decay.grantRole(decay.ORACLE_ROLE(), oracle);
        vm.stopPrank();
    }

    function testFuzz_Decay_LinearCalculation(
        uint256 baseRep,
        uint256 intervalsInactive,
        uint256 decayPercentage
    ) public {
        baseRep = bound(baseRep, 1, 1e24);
        intervalsInactive = bound(intervalsInactive, 1, 100);
        decayPercentage = bound(decayPercentage, 1, BASIS_POINTS);

        vm.prank(owner);
        decay.setDecayConfig(ReputationDecay.ReputationDecayConfig({
            decayInterval: ONE_WEEK,
            decayPercentage: decayPercentage,
            minimumReputation: 1,
            enabled: true
        }));

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        uint256 expectedDecayBps = intervalsInactive * decayPercentage;
        if (expectedDecayBps > BASIS_POINTS) expectedDecayBps = BASIS_POINTS;

        uint256 expectedEffective = (baseRep * (BASIS_POINTS - expectedDecayBps)) / BASIS_POINTS;
        if (expectedEffective < 1) expectedEffective = 1;

        vm.warp(block.timestamp + intervalsInactive * ONE_WEEK);

        uint256 effective = decay.getEffectiveReputation(verifier);
        assertEq(effective, expectedEffective);
    }

    function testFuzz_MinimumReputation_Enforced(
        uint256 baseRep,
        uint256 intervalsInactive,
        uint256 minRep
    ) public {
        baseRep = bound(baseRep, 1, 1e6);
        intervalsInactive = bound(intervalsInactive, 1, 1000);
        minRep = bound(minRep, 1, 1000);

        vm.prank(owner);
        decay.setDecayConfig(ReputationDecay.ReputationDecayConfig({
            decayInterval: ONE_WEEK,
            decayPercentage: 5000,
            minimumReputation: minRep,
            enabled: true
        }));

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        vm.warp(block.timestamp + intervalsInactive * ONE_WEEK);

        uint256 effective = decay.getEffectiveReputation(verifier);
        assertGe(effective, minRep);
    }

    function testFuzz_ActivityReset_PreventsDecay(
        uint256 baseRep,
        uint256 intervalsBeforeReset,
        uint256 intervalsAfterReset
    ) public {
        baseRep = bound(baseRep, 1, 1e6);
        intervalsBeforeReset = bound(intervalsBeforeReset, 1, 10);
        intervalsAfterReset = bound(intervalsAfterReset, 1, 10);

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        vm.warp(block.timestamp + intervalsBeforeReset * ONE_WEEK);

        vm.prank(oracle);
        decay.recordActivity(verifier);

        vm.warp(block.timestamp + intervalsAfterReset * ONE_WEEK);

        uint256 effective = decay.getEffectiveReputation(verifier);
        uint256 expectedDecayBps = intervalsAfterReset * 100;
        if (expectedDecayBps > BASIS_POINTS) expectedDecayBps = BASIS_POINTS;
        uint256 expected = (baseRep * (BASIS_POINTS - expectedDecayBps)) / BASIS_POINTS;
        if (expected < 1) expected = 1;

        assertEq(effective, expected);
    }

    function testFuzz_DecayDisabled_NoDecay(
        uint256 baseRep,
        uint256 timeJump
    ) public {
        baseRep = bound(baseRep, 1, 1e6);
        timeJump = bound(timeJump, ONE_WEEK, 365 days);

        vm.prank(owner);
        decay.setDecayConfig(ReputationDecay.ReputationDecayConfig({
            decayInterval: ONE_WEEK,
            decayPercentage: 1000,
            minimumReputation: 1,
            enabled: false
        }));

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        vm.warp(block.timestamp + timeJump);

        assertEq(decay.getEffectiveReputation(verifier), baseRep);
    }

    function testFuzz_ZeroReputation_ReturnsZero(
        uint256 timeJump
    ) public {
        timeJump = bound(timeJump, ONE_WEEK, 365 days);

        vm.warp(block.timestamp + timeJump);

        assertEq(decay.getEffectiveReputation(verifier), 0);
    }

    function testFuzz_ApplyDecay_UpdatesState(
        uint256 baseRep,
        uint256 intervalsInactive
    ) public {
        baseRep = bound(baseRep, 2, 1e6);
        intervalsInactive = bound(intervalsInactive, 1, 50);

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        vm.warp(block.timestamp + intervalsInactive * ONE_WEEK);

        vm.prank(oracle);
        decay.applyDecay(verifier);

        uint256 effectiveBefore = decay.getEffectiveReputation(verifier);
        uint256 storedBase = decay.baseReputation(verifier);

        assertEq(storedBase, effectiveBefore);
    }

    function testFuzz_IsDecayRequired_Consistent(
        uint256 baseRep,
        uint256 timeJump
    ) public {
        baseRep = bound(baseRep, 1, 1e6);
        timeJump = bound(timeJump, 0, 100 * ONE_WEEK);

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        vm.warp(block.timestamp + timeJump);

        bool required = decay.isDecayRequired(verifier);
        bool shouldBeRequired = timeJump >= ONE_WEEK;
        assertEq(required, shouldBeRequired);
    }

    function testFuzz_NextDecayTimestamp_Accurate(
        uint256 baseRep,
        uint256 timeJump
    ) public {
        baseRep = bound(baseRep, 1, 1e6);
        timeJump = bound(timeJump, 0, 10 * ONE_WEEK);

        vm.prank(oracle);
        decay.setReputation(verifier, baseRep);

        uint256 expectedNext = block.timestamp + ONE_WEEK;
        assertEq(decay.nextDecayTimestamp(verifier), expectedNext);

        vm.warp(block.timestamp + timeJump);
        assertEq(decay.nextDecayTimestamp(verifier), expectedNext);
    }
}
