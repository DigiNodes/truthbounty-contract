// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/reputation/ReputationEngine.sol";
import "../../contracts/mocks/MockGovernanceController.sol";

contract ReputationEngineFuzzTest is Test {
    ReputationEngine reputationEngine;
    MockGovernanceController mockGovernance;
    
    address admin;
    address updateRole;
    address pauser;
    
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant UPDATE_ROLE = keccak256("UPDATE_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 constant BASE_MULTIPLIER = 1e18;
    uint256 constant DEFAULT_INITIAL_SCORE = 1e18;
    uint256 constant MIN_REPUTATION_SCORE = 1e17;
    uint256 constant MAX_REPUTATION_SCORE = 10e18;

    function setUp() public {
        admin = address(this);
        updateRole = address(0x1);
        pauser = address(0x2);
        
        mockGovernance = new MockGovernanceController(admin);
        reputationEngine = new ReputationEngine(admin, address(mockGovernance));
        
        reputationEngine.grantRole(UPDATE_ROLE, updateRole);
        reputationEngine.grantRole(PAUSER_ROLE, pauser);
    }

    // ============ Fuzz: Reputation Initialization ============

    function testFuzz_InitializeReputation(address verifier) public {
        vm.assume(verifier != address(0));
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        (uint256 score, uint256 successful, uint256 failed, uint256 disputed, uint256 totalStake, uint256 lastUpdated, bool exists) = 
            reputationEngine.getReputation(verifier);
        
        assertEq(score, DEFAULT_INITIAL_SCORE);
        assertEq(successful, 0);
        assertEq(failed, 0);
        assertEq(disputed, 0);
        assertEq(totalStake, 0);
        assertEq(lastUpdated, block.timestamp);
        assertTrue(exists);
    }

    function testFuzz_InitializeReputationWithCustomScore(address verifier, uint256 score) public {
        vm.assume(verifier != address(0));
        vm.assume(score >= MIN_REPUTATION_SCORE && score <= MAX_REPUTATION_SCORE);
        
        vm.prank(updateRole);
        reputationEngine.initializeReputationWithScore(verifier, score);
        
        uint256 actualScore = reputationEngine.getReputationScore(verifier);
        assertEq(actualScore, score);
    }

    function testFuzz_DuplicateInitializationReverts(address verifier) public {
        vm.assume(verifier != address(0));
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(verifier);
        vm.expectRevert(bytes("VerifierAlreadyExists"));
        reputationEngine.initializeReputation(verifier);
    }

    function testFuzz_ZeroAddressInitializationReverts() public {
        vm.expectRevert(bytes("InvalidZeroAddress"));
        reputationEngine.initializeReputation(address(0));
    }

    // ============ Fuzz: Reputation Score Updates ============

    function testFuzz_UpdateReputationScore(address verifier, uint256 newScore) public {
        vm.assume(verifier != address(0));
        
        // Initialize reputation
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.assume(newScore >= MIN_REPUTATION_SCORE && newScore <= MAX_REPUTATION_SCORE);
        
        vm.prank(updateRole);
        reputationEngine.updateReputationScore(verifier, newScore);
        
        uint256 actualScore = reputationEngine.getReputationScore(verifier);
        assertEq(actualScore, newScore);
    }

    function testFuzz_UpdateScoreBelowBoundsReverts(address verifier, uint256 newScore) public {
        vm.assume(verifier != address(0));
        vm.assume(newScore < MIN_REPUTATION_SCORE);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        vm.expectRevert(bytes("InvalidReputationScore"));
        reputationEngine.updateReputationScore(verifier, newScore);
    }

    function testFuzz_UpdateScoreAboveBoundsReverts(address verifier, uint256 newScore) public {
        vm.assume(verifier != address(0));
        vm.assume(newScore > MAX_REPUTATION_SCORE);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        vm.expectRevert(bytes("InvalidReputationScore"));
        reputationEngine.updateReputationScore(verifier, newScore);
    }

    // ============ Fuzz: Reputation Multiplier Calculation ============

    function testFuzz_CalculateReputationMultiplier(address verifier, uint256 score) public {
        vm.assume(verifier != address(0));
        vm.assume(score >= MIN_REPUTATION_SCORE && score <= MAX_REPUTATION_SCORE);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.updateReputationScore(verifier, score);
        
        uint256 multiplier = reputationEngine.calculateReputationMultiplier(verifier);
        uint256 expectedMultiplier = score / BASE_MULTIPLIER;
        
        // Cap at 10x
        if (expectedMultiplier > 10e18) {
            expectedMultiplier = 10e18;
        }
        
        assertEq(multiplier, expectedMultiplier);
    }

    function testFuzz_CalculateWeight(address verifier, uint256 stakeAmount, uint256 score) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount > 0 && stakeAmount <= 1e30);
        vm.assume(score >= MIN_REPUTATION_SCORE && score <= MAX_REPUTATION_SCORE);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.updateReputationScore(verifier, score);
        
        uint256 weight = reputationEngine.calculateWeight(stakeAmount, verifier);
        uint256 multiplier = reputationEngine.calculateReputationMultiplier(verifier);
        uint256 expectedWeight = (stakeAmount * multiplier) / BASE_MULTIPLIER;
        
        assertEq(weight, expectedWeight);
    }

    // ============ Fuzz: Verification Statistics ============

    function testFuzz_RecordSuccessfulVerification(address verifier, uint256 stakeAmount) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount > 0 && stakeAmount <= 1e30);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        (, uint256 successfulBefore, , , , , ) = reputationEngine.getReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.recordSuccessfulVerification(verifier, stakeAmount);
        
        (, uint256 successfulAfter, , , uint256 totalStakeAfter, , ) = reputationEngine.getReputation(verifier);
        
        assertEq(successfulAfter, successfulBefore + 1);
        assertEq(totalStakeAfter, stakeAmount);
    }

    function testFuzz_RecordFailedVerification(address verifier, uint256 stakeAmount) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount > 0 && stakeAmount <= 1e30);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        (, , uint256 failedBefore, , , , ) = reputationEngine.getReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.recordFailedVerification(verifier, stakeAmount);
        
        (, , uint256 failedAfter, , uint256 totalStakeAfter, , ) = reputationEngine.getReputation(verifier);
        
        assertEq(failedAfter, failedBefore + 1);
        assertEq(totalStakeAfter, stakeAmount);
    }

    function testFuzz_RecordDisputedClaim(address verifier, uint256 stakeAmount) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount > 0 && stakeAmount <= 1e30);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        (, , , uint256 disputedBefore, , , ) = reputationEngine.getReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.recordDisputedClaim(verifier, stakeAmount);
        
        (, , , uint256 disputedAfter, , uint256 totalStakeAfter, ) = reputationEngine.getReputation(verifier);
        
        assertEq(disputedAfter, disputedBefore + 1);
        assertEq(totalStakeAfter, stakeAmount);
    }

    // ============ Fuzz: Batch Updates ============

    function testFuzz_BatchUpdateVerificationStats(
        address[] calldata verifiers,
        uint256[] calldata successCount,
        uint256[] calldata failCount,
        uint256[] calldata disputeCount
    ) public {
        vm.assume(verifiers.length > 0 && verifiers.length <= 10);
        vm.assume(successCount.length == verifiers.length);
        vm.assume(failCount.length == verifiers.length);
        vm.assume(disputeCount.length == verifiers.length);
        
        // Initialize all verifiers
        for (uint256 i = 0; i < verifiers.length; i++) {
            vm.assume(verifiers[i] != address(0));
            vm.prank(verifiers[i]);
            reputationEngine.initializeReputation(verifiers[i]);
        }
        
        vm.prank(updateRole);
        reputationEngine.batchUpdateVerificationStats(verifiers, successCount, failCount, disputeCount);
        
        // Verify updates
        for (uint256 i = 0; i < verifiers.length; i++) {
            (, uint256 successful, uint256 failed, uint256 disputed, , , ) = 
                reputationEngine.getReputation(verifiers[i]);
            
            assertEq(successful, successCount[i]);
            assertEq(failed, failCount[i]);
            assertEq(disputed, disputeCount[i]);
        }
    }

    function testFuzz_BatchUpdateArrayLengthMismatch(address[] calldata verifiers) public {
        vm.assume(verifiers.length > 0);
        
        uint256[] memory wrongLength = new uint256[](verifiers.length + 1);
        
        vm.prank(updateRole);
        vm.expectRevert("Array length mismatch");
        reputationEngine.batchUpdateVerificationStats(verifiers, wrongLength, wrongLength, wrongLength);
    }

    // ============ Fuzz: Reputation Bounds ============

    function testFuzz_SetReputationBounds(uint256 minScore, uint256 maxScore) public {
        vm.assume(minScore > 0);
        vm.assume(minScore < maxScore);
        vm.assume(maxScore <= 100e18);
        
        reputationEngine.setReputationBounds(minScore, maxScore);
        
        assertEq(reputationEngine.minReputationScore(), minScore);
        assertEq(reputationEngine.maxReputationScore(), maxScore);
    }

    function testFuzz_SetInvalidReputationBounds(uint256 minScore, uint256 maxScore) public {
        vm.assume(minScore >= maxScore || minScore == 0);
        
        vm.expectRevert(bytes("InvalidReputationBounds"));
        reputationEngine.setReputationBounds(minScore, maxScore);
    }

    function testFuzz_SetDefaultInitialScore(uint256 score) public {
        vm.assume(score > 0);
        vm.assume(score <= 100e18);
        
        reputationEngine.setDefaultInitialScore(score);
        
        assertEq(reputationEngine.defaultInitialScore(), score);
    }

    // ============ Fuzz: Deterministic Results ============

    function testFuzz_ReputationLookupIsDeterministic(address verifier) public {
        vm.assume(verifier != address(0));
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        uint256 score1 = reputationEngine.getReputationScore(verifier);
        uint256 score2 = reputationEngine.getReputationScore(verifier);
        
        assertEq(score1, score2);
    }

    function testFuzz_MultiplierCalculationIsDeterministic(address verifier, uint256 stakeAmount) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount > 0);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        uint256 weight1 = reputationEngine.calculateWeight(stakeAmount, verifier);
        uint256 weight2 = reputationEngine.calculateWeight(stakeAmount, verifier);
        
        assertEq(weight1, weight2);
    }

    // ============ Fuzz: Protocol Statistics ============

    function testFuzz_ProtocolStatisticsAccumulate(address verifier1, address verifier2) public {
        vm.assume(verifier1 != address(0) && verifier2 != address(0));
        vm.assume(verifier1 != verifier2);
        
        vm.prank(verifier1);
        reputationEngine.initializeReputation(verifier1);
        
        vm.prank(verifier2);
        reputationEngine.initializeReputation(verifier2);
        
        (uint256 totalVerifiers, , , , , , ) = reputationEngine.getStatistics();
        assertEq(totalVerifiers, 2);
        
        vm.prank(updateRole);
        reputationEngine.recordSuccessfulVerification(verifier1, 1000e18);
        
        vm.prank(updateRole);
        reputationEngine.recordFailedVerification(verifier2, 500e18);
        
        (, uint256 totalSuccess, uint256 totalFail, , , , ) = reputationEngine.getStatistics();
        assertEq(totalSuccess, 1);
        assertEq(totalFail, 1);
    }

    // ============ Fuzz: Edge Cases ============

    function testFuzz_MaxReputationScore(address verifier) public {
        vm.assume(verifier != address(0));
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.updateReputationScore(verifier, MAX_REPUTATION_SCORE);
        
        uint256 multiplier = reputationEngine.calculateReputationMultiplier(verifier);
        assertEq(multiplier, 10e18); // Capped at 10x
    }

    function testFuzz_MinReputationScore(address verifier) public {
        vm.assume(verifier != address(0));
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.updateReputationScore(verifier, MIN_REPUTATION_SCORE);
        
        uint256 multiplier = reputationEngine.calculateReputationMultiplier(verifier);
        assertEq(multiplier, MIN_REPUTATION_SCORE / BASE_MULTIPLIER);
    }

    function testFuzz_LargeStakeAmount(address verifier, uint256 stakeAmount) public {
        vm.assume(verifier != address(0));
        vm.assume(stakeAmount >= 1e18 && stakeAmount <= 1e30);
        
        vm.prank(verifier);
        reputationEngine.initializeReputation(verifier);
        
        vm.prank(updateRole);
        reputationEngine.recordSuccessfulVerification(verifier, stakeAmount);
        
        (, , , , uint256 totalStake, , ) = reputationEngine.getReputation(verifier);
        assertEq(totalStake, stakeAmount);
    }

    // ============ Fuzz: Multiple Verifiers ============

    function testFuzz_MultipleVerifiersInitialization(address[] calldata verifiers) public {
        vm.assume(verifiers.length > 0 && verifiers.length <= 20);
        
        for (uint256 i = 0; i < verifiers.length; i++) {
            vm.assume(verifiers[i] != address(0));
            vm.prank(verifiers[i]);
            reputationEngine.initializeReputation(verifiers[i]);
        }
        
        (uint256 totalVerifiers, , , , , , ) = reputationEngine.getStatistics();
        assertEq(totalVerifiers, verifiers.length);
    }

    function testFuzz_VerifierExistenceCheck(address[] calldata verifiers, address checkAddress) public {
        vm.assume(verifiers.length > 0 && verifiers.length <= 20);
        
        for (uint256 i = 0; i < verifiers.length; i++) {
            vm.assume(verifiers[i] != address(0));
            vm.prank(verifiers[i]);
            reputationEngine.initializeReputation(verifiers[i]);
        }
        
        bool exists = reputationEngine.reputationExists(checkAddress);
        bool shouldExist = false;
        
        for (uint256 i = 0; i < verifiers.length; i++) {
            if (verifiers[i] == checkAddress) {
                shouldExist = true;
                break;
            }
        }
        
        assertEq(exists, shouldExist);
    }
}
