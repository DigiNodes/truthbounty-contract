// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Base.sol";
import "../../contracts/TruthBounty.sol";

contract TruthBountyHandler is CommonBase {
    TruthBounty public truthBounty;
    TruthBountyToken public token;

    address[] public verifiers;
    uint256[] public claimIds;

    uint256 constant MIN_STAKE = 100 * 10 ** 18;

    constructor() {
        token = new TruthBountyToken(address(this));
        truthBounty = new TruthBounty(address(token), address(this), address(this));

        token.approve(address(truthBounty), type(uint256).max);

        for (uint256 i = 0; i < 5; i++) {
            address verifier = address(uint160(0x100 + i));
            verifiers.push(verifier);
            token.transfer(verifier, 1_000_000 * 10 ** 18);
        }
    }

    function createClaim(uint256 seed) public {
        address submitter = verifiers[seed % verifiers.length];
        vm.prank(submitter);
        uint256 claimId = truthBounty.createClaim(string(abi.encodePacked("claim_", seed)));
        claimIds.push(claimId);
    }

    function stake(uint256 seed, uint256 amount) public {
        address verifier = verifiers[seed % verifiers.length];
        uint256 bounded = _boundedAmount(amount);

        vm.prank(verifier);
        token.approve(address(truthBounty), type(uint256).max);
        vm.prank(verifier);
        truthBounty.stake(bounded);
    }

    function vote(uint256 claimIdx, uint256 seed, uint256 amount) public {
        if (claimIds.length == 0) return;

        uint256 claimId = claimIds[claimIdx % claimIds.length];
        address verifier = verifiers[seed % verifiers.length];
        uint256 bounded = _boundedAmount(amount);
        bool support = (seed % 2) == 0;

        vm.prank(verifier);
        try truthBounty.vote(claimId, support, bounded) {} catch {
            // Vote may fail if already voted, out of stake, or window closed
        }
    }

    function settleClaim(uint256 claimIdx) public {
        if (claimIds.length == 0) return;

        uint256 claimId = claimIds[claimIdx % claimIds.length];
        (,,, , uint256 verificationWindowEnd, bool settled,,,) = truthBounty.claims(claimId);
        if (settled) return;
        if (block.timestamp < verificationWindowEnd) vm.warp(verificationWindowEnd + 1);

        try truthBounty.settleClaim(claimId) {} catch {
            // Settlement may fail if no votes were cast
        }
    }

    function claimRewards(uint256 claimIdx, uint256 seed) public {
        if (claimIds.length == 0) return;

        uint256 claimId = claimIds[claimIdx % claimIds.length];
        address verifier = verifiers[seed % verifiers.length];

        vm.prank(verifier);
        try truthBounty.claimSettlementRewards(claimId) {} catch {
            // Only winners can claim; losers use withdrawSettledStake
        }
    }

    function withdrawSettledStake(uint256 claimIdx, uint256 seed) public {
        if (claimIds.length == 0) return;

        uint256 claimId = claimIds[claimIdx % claimIds.length];
        address verifier = verifiers[seed % verifiers.length];

        vm.prank(verifier);
        try truthBounty.withdrawSettledStake(claimId) {} catch {
            // May fail if already withdrawn or the voter was a winner
        }
    }

    function _boundedAmount(uint256 amount) internal pure returns (uint256) {
        return MIN_STAKE + (amount % (100_000 * 10 ** 18 - MIN_STAKE));
    }
}

contract TruthBountyInvariant is StdInvariant, Test {
    TruthBountyHandler public handler;
    TruthBounty public truthBounty;

    function setUp() public {
        handler = new TruthBountyHandler();
        truthBounty = handler.truthBounty();

        targetContract(address(handler));
    }

    function invariant_TotalRewardedNeverExceedsTotalSlashed() public view {
        assertLe(truthBounty.totalRewarded(), truthBounty.totalSlashed());
    }

    function invariant_ContractEthBalanceIsNonNegative() public view {
        assertGe(address(truthBounty).balance, 0);
    }
}
