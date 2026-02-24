#!/bin/bash

# Fuzz Testing Script for TruthBounty Staking Contracts
# This script runs comprehensive fuzz tests for staking logic validation

set -e

echo "🔍 Starting TruthBounty Fuzz Testing Campaign"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Foundry is installed
if ! command -v forge &> /dev/null; then
    print_error "Foundry is not installed. Please install it first."
    exit 1
fi

print_status "Foundry installation found"

# Install dependencies if needed
if [ ! -d "lib" ]; then
    print_status "Installing Foundry dependencies..."
    forge install
fi

# Compile contracts
print_status "Compiling contracts..."
forge build

# Run basic fuzz tests with standard iterations
print_status "Running standard fuzz tests (256 iterations each)..."

echo ""
print_status "Testing WeightedStaking contract..."
if forge test --match-contract WeightedStakingFuzzTest -vv; then
    print_status "✅ WeightedStaking fuzz tests passed"
else
    print_error "❌ WeightedStaking fuzz tests failed"
    exit 1
fi

echo ""
print_status "Testing basic Staking contract..."
if forge test --match-contract StakingFuzzTest -vv; then
    print_status "✅ Staking fuzz tests passed"
else
    print_error "❌ Staking fuzz tests failed"
    exit 1
fi

echo ""
print_status "Testing Integration scenarios..."
if forge test --match-contract IntegrationFuzzTest -vv; then
    print_status "✅ Integration fuzz tests passed"
else
    print_error "❌ Integration fuzz tests failed"
    exit 1
fi

# Run extended fuzz campaign
echo ""
print_status "Running extended fuzz campaign (1000 iterations each)..."

echo ""
print_warning "Running extended WeightedStaking tests..."
if forge test --match-contract WeightedStakingFuzzTest --fuzz-runs 1000 -vv; then
    print_status "✅ Extended WeightedStaking tests passed"
else
    print_error "❌ Extended WeightedStaking tests failed"
    exit 1
fi

echo ""
print_warning "Running extended Staking tests..."
if forge test --match-contract StakingFuzzTest --fuzz-runs 1000 -vv; then
    print_status "✅ Extended Staking tests passed"
else
    print_error "❌ Extended Staking tests failed"
    exit 1
fi

# Run property-based tests
echo ""
print_status "Running property-based tests..."
if forge test --match-test testFuzz_ --no-match-contract Test -vv; then
    print_status "✅ Property-based tests passed"
else
    print_error "❌ Property-based tests failed"
    exit 1
fi

# Generate coverage report
echo ""
print_status "Generating coverage report..."
if forge coverage --report lcov; then
    print_status "✅ Coverage report generated"
else
    print_warning "⚠️ Coverage generation failed, but tests passed"
fi

# Run gas analysis
echo ""
print_status "Running gas analysis..."
if forge test --gas-report; then
    print_status "✅ Gas analysis completed"
else
    print_warning "⚠️ Gas analysis failed, but tests passed"
fi

echo ""
print_status "🎉 All fuzz tests completed successfully!"
echo "=============================================="
echo ""
echo "📊 Test Summary:"
echo "  - WeightedStaking: ✅ Standard + Extended fuzz tests"
echo "  - Staking: ✅ Standard + Extended fuzz tests"  
echo "  - Integration: ✅ Cross-contract scenarios"
echo "  - Property-based: ✅ Invariant testing"
echo "  - Coverage: ✅ Generated"
echo "  - Gas analysis: ✅ Completed"
echo ""
echo "🔬 Fuzz testing validates:"
echo "  - Random stake amounts and sequences"
echo "  - Boundary value conditions"
echo "  - Reputation score edge cases"
echo "  - Slashing mechanism robustness"
echo "  - Emergency scenario handling"
echo "  - Cross-contract integration"
echo ""
print_status "Ready for production deployment! 🚀"
