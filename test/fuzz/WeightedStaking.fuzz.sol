// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/WeightedStaking.sol";
import "../contracts/MockReputationOracle.sol";

contract WeightedStakingFuzzTest is Test {
    WeightedStaking public weightedStaking;
    MockReputationOracle public mockOracle;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    
    uint256 public constant BASE_MULTIPLIER = 1e18;
    uint256 public constant MIN_REPUTATION = 1e17; // 0.1
    uint256 public constant MAX_REPUTATION = 10e18; // 10
    
    event WeightedStakeCalculated(
        address indexed user,
        uint256 rawStake,
        uint256 reputationScore,
        uint256 effectiveStake,
        uint256 weight
    );
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock oracle
        mockOracle = new MockReputationOracle();
        
        // Deploy weighted staking contract
        weightedStaking = new WeightedStaking(address(mockOracle));
        
        vm.stopPrank();
    }
    
    /// @dev Fuzz test for calculateWeightedStake with random stake amounts and reputation scores
    function testFuzz_CalculateWeightedStake_RandomInputs(
        uint256 stakeAmount,
        uint256 reputationScore
    ) public {
        // Bound inputs to reasonable ranges
        vm.assume(stakeAmount > 0 && stakeAmount <= 1000e18); // Max 1000 tokens
        vm.assume(reputationScore > 0 && reputationScore <= 100e18); // Max 100x reputation
        
        // Set reputation for user1
        vm.prank(owner);
        mockOracle.setReputationScore(user1, reputationScore);
        
        // Calculate weighted stake
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, stakeAmount);
        
        // Verify invariants
        assertEq(result.rawStake, stakeAmount, "Raw stake should match input");
        
        // Reputation should be bounded
        assertGe(result.reputationScore, MIN_REPUTATION, "Reputation should be at least minimum");
        assertLe(result.reputationScore, MAX_REPUTATION, "Reputation should be at most maximum");
        
        // Weight should equal bounded reputation
        assertEq(result.weight, result.reputationScore, "Weight should equal bounded reputation");
        
        // Effective stake should be calculated correctly
        uint256 expectedEffectiveStake = (stakeAmount * result.reputationScore) / BASE_MULTIPLIER;
        assertEq(result.effectiveStake, expectedEffectiveStake, "Effective stake calculation incorrect");
        
        // Effective stake should not exceed maximum possible
        uint256 maxEffectiveStake = (stakeAmount * MAX_REPUTATION) / BASE_MULTIPLIER;
        assertLe(result.effectiveStake, maxEffectiveStake, "Effective stake exceeds maximum");
    }
    
    /// @dev Fuzz test for reputation bounds enforcement
    function testFuzz_ReputationBounds_Enforced(
        uint256 reputationScore
    ) public {
        vm.assume(reputationScore > 0 && reputationScore <= 1000e18); // Allow very high scores
        
        vm.prank(owner);
        mockOracle.setReputationScore(user1, reputationScore);
        
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, 1e18);
        
        // Verify bounds are enforced
        if (reputationScore < MIN_REPUTATION) {
            assertEq(result.reputationScore, MIN_REPUTATION, "Should use min reputation for low scores");
        } else if (reputationScore > MAX_REPUTATION) {
            assertEq(result.reputationScore, MAX_REPUTATION, "Should use max reputation for high scores");
        } else {
            assertEq(result.reputationScore, reputationScore, "Should use original reputation for normal scores");
        }
    }
    
    /// @dev Fuzz test for batch calculation with random arrays
    function testFuzz_BatchCalculateWeightedStake_RandomArrays(
        uint256[] calldata stakeAmounts,
        uint256[] calldata reputationScores
    ) public {
        // Ensure arrays have same length and reasonable size
        vm.assume(stakeAmounts.length == reputationScores.length);
        vm.assume(stakeAmounts.length > 0 && stakeAmounts.length <= 10);
        
        address[] memory users = new address[](stakeAmounts.length);
        
        // Set up users and reputation scores
        for (uint256 i = 0; i < stakeAmounts.length; i++) {
            users[i] = address(uint160(0x100 + i)); // Generate unique addresses
            
            // Bound values
            stakeAmounts[i] = bound(stakeAmounts[i], 1, 1000e18);
            reputationScores[i] = bound(reputationScores[i], 1, 100e18);
            
            vm.prank(owner);
            mockOracle.setReputationScore(users[i], reputationScores[i]);
        }
        
        // Test batch calculation
        WeightedStaking.WeightedStakeResult[] memory results = 
            weightedStaking.batchCalculateWeightedStake(users, stakeAmounts);
        
        // Verify each result
        for (uint256 i = 0; i < results.length; i++) {
            assertEq(results[i].rawStake, stakeAmounts[i], "Raw stake should match");
            assertGe(results[i].reputationScore, MIN_REPUTATION, "Reputation should respect minimum");
            assertLe(results[i].reputationScore, MAX_REPUTATION, "Reputation should respect maximum");
            
            uint256 expectedEffective = (stakeAmounts[i] * results[i].reputationScore) / BASE_MULTIPLIER;
            assertEq(results[i].effectiveStake, expectedEffective, "Effective stake should be correct");
        }
    }
    
    /// @dev Fuzz test for weighted staking disabled scenario
    function testFuzz_WeightedStakingDisabled_EqualWeights(
        uint256 stakeAmount,
        uint256 reputationScore
    ) public {
        vm.assume(stakeAmount > 0 && stakeAmount <= 1000e18);
        vm.assume(reputationScore > 0 && reputationScore <= 100e18);
        
        // Disable weighted staking
        vm.prank(owner);
        weightedStaking.setWeightedStakingEnabled(false);
        
        vm.prank(owner);
        mockOracle.setReputationScore(user1, reputationScore);
        
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, stakeAmount);
        
        // When disabled, should return equal weights
        assertEq(result.reputationScore, BASE_MULTIPLIER, "Reputation should be base multiplier when disabled");
        assertEq(result.weight, BASE_MULTIPLIER, "Weight should be base multiplier when disabled");
        assertEq(result.effectiveStake, stakeAmount, "Effective stake should equal raw stake when disabled");
    }
    
    /// @dev Fuzz test for oracle failure scenarios
    function testFuzz_OracleFailure_UsesDefault(
        uint256 stakeAmount
    ) public {
        vm.assume(stakeAmount > 0 && stakeAmount <= 1000e18);
        
        // Set oracle to inactive
        vm.prank(owner);
        mockOracle.setActive(false);
        
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, stakeAmount);
        
        // Should use default reputation when oracle is inactive
        assertEq(result.reputationScore, weightedStaking.defaultReputationScore(), "Should use default reputation");
        assertEq(result.weight, weightedStaking.defaultReputationScore(), "Weight should equal default reputation");
        
        uint256 expectedEffective = (stakeAmount * weightedStaking.defaultReputationScore()) / BASE_MULTIPLIER;
        assertEq(result.effectiveStake, expectedEffective, "Effective stake should use default reputation");
    }
    
    /// @dev Fuzz test for configuration parameter updates
    function testFuzz_ConfigurationUpdates_ValidBounds(
        uint256 minScore,
        uint256 maxScore
    ) public {
        // Ensure valid bounds
        vm.assume(minScore > 0 && minScore < maxScore);
        vm.assume(maxScore <= 100e18);
        
        vm.prank(owner);
        weightedStaking.setReputationBounds(minScore, maxScore);
        
        // Test with reputation score outside new bounds
        uint256 testReputation = minScore / 2; // Below new minimum
        vm.prank(owner);
        mockOracle.setReputationScore(user1, testReputation);
        
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, 1e18);
        
        // Should use new minimum
        assertEq(result.reputationScore, minScore, "Should use new minimum bound");
    }
    
    /// @dev Fuzz test for calculateAndRecordWeightedStake event emission
    function testFuzz_CalculateAndRecordWeightedStake_EventEmitted(
        uint256 stakeAmount,
        uint256 reputationScore
    ) public {
        vm.assume(stakeAmount > 0 && stakeAmount <= 1000e18);
        vm.assume(reputationScore > 0 && reputationScore <= 100e18);
        
        vm.prank(owner);
        mockOracle.setReputationScore(user1, reputationScore);
        
        vm.expectEmit(true, true, true, true);
        emit WeightedStakeCalculated(
            user1,
            stakeAmount,
            _applyBounds(reputationScore),
            (stakeAmount * _applyBounds(reputationScore)) / BASE_MULTIPLIER,
            _applyBounds(reputationScore)
        );
        
        weightedStaking.calculateAndRecordWeightedStake(user1, stakeAmount);
    }
    
    /// @dev Fuzz test for zero stake amount rejection
    function testFuzz_ZeroStakeAmount_Reverts(
        uint256 stakeAmount
    ) public {
        vm.assume(stakeAmount == 0);
        
        vm.expectRevert(WeightedStaking.ZeroStakeAmount.selector);
        weightedStaking.calculateWeightedStake(user1, stakeAmount);
    }
    
    /// @dev Fuzz test for preview weight function
    function testFuzz_PreviewWeight_ConsistentWithCalculation(
        uint256 reputationScore
    ) public {
        vm.assume(reputationScore > 0 && reputationScore <= 100e18);
        
        vm.prank(owner);
        mockOracle.setReputationScore(user1, reputationScore);
        
        uint256 previewWeight = weightedStaking.previewWeight(user1);
        WeightedStaking.WeightedStakeResult memory result = weightedStaking.calculateWeightedStake(user1, 1e18);
        
        assertEq(previewWeight, result.weight, "Preview weight should match calculation weight");
        assertEq(previewWeight, result.reputationScore, "Preview weight should equal reputation score");
    }
    
    /// @dev Helper function to apply reputation bounds
    function _applyBounds(uint256 score) internal view returns (uint256) {
        if (score < MIN_REPUTATION) return MIN_REPUTATION;
        if (score > MAX_REPUTATION) return MAX_REPUTATION;
        return score;
    }
}
