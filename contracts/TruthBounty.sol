// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./governance/GovernanceOwnable.sol";

/**
 * @title TruthBounty
 * @notice Main contract for claim verification, voting, and settlement.
 * @dev DEPRECATED — use TruthBountyWeighted for all new integrations.
 *
 * ── Audit Fix CO-199 ────────────────────────────────────────────────────────
 * Issue   : `submitter` in `ClaimCreated` was emitted as a plain (non-indexed)
 *           address, making off-chain log filtering by submitter impossible
 *           without scanning every event.
 * Fix     : Added the `indexed` keyword to the `submitter` parameter.
 *           This costs one additional bloom-filter slot (Ethereum allows up to
 *           3 indexed topics per event; ClaimCreated uses claimId + submitter,
 *           so we remain within the limit).
 * Impact  : ABI-breaking change — off-chain listeners that decode the raw
 *           topic bytes must be updated.  The on-chain execution path is
 *           unchanged.
 * ────────────────────────────────────────────────────────────────────────────
 */
contract TruthBounty is AccessControl, ReentrancyGuard, Pausable, GovernanceOwnable {

    // ── Roles ──────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE    = keccak256("ADMIN_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    IERC20 public immutable bountyToken;

    // ── Structs ────────────────────────────────────────────────────────────

    struct Claim {
        uint256 id;
        address submitter;
        string  content;
        uint256 createdAt;
        uint256 verificationWindowEnd;
        bool    settled;
        uint256 totalStakedFor;
        uint256 totalStakedAgainst;
        uint256 totalStakeAmount;
    }

    struct Vote {
        bool    voted;
        bool    support;
        uint256 stakeAmount;
        bool    rewardClaimed;
        bool    stakeReturned;
    }

    struct SettlementResult {
        bool    passed;
        uint256 totalRewards;
        uint256 totalSlashed;
        uint256 winnerStake;
        uint256 loserStake;
    }

    struct VerifierStake {
        uint256 totalStaked;
        uint256 activeStakes;
    }

    // ── Storage ────────────────────────────────────────────────────────────

    mapping(uint256 => Claim)                            public claims;
    mapping(uint256 => SettlementResult)                 public settlementResults;
    mapping(uint256 => mapping(address => Vote))         public votes;
    mapping(address => VerifierStake)                    public verifierStakes;
    mapping(address => uint256)                          public verifierRewards;

    uint256 public verificationWindowDuration  = 7 days;
    uint256 public minStakeAmount              = 100 * 10**18;
    uint256 public settlementThresholdPercent  = 60;
    uint256 public rewardPercent               = 80;
    uint256 public slashPercent                = 20;

    bytes32 public constant GOVERNANCE_PARAM_VERIFICATION_WINDOW = keccak256("VERIFICATION_WINDOW_DURATION");
    bytes32 public constant GOVERNANCE_PARAM_MIN_STAKE           = keccak256("MIN_STAKE_AMOUNT");
    bytes32 public constant GOVERNANCE_PARAM_THRESHOLD           = keccak256("SETTLEMENT_THRESHOLD_PERCENT");
    bytes32 public constant GOVERNANCE_PARAM_REWARD              = keccak256("REWARD_PERCENT");
    bytes32 public constant GOVERNANCE_PARAM_SLASH               = keccak256("SLASH_PERCENT");

    uint256 public claimCounter;
    uint256 public totalSlashed;
    uint256 public totalRewarded;

    // ── Events ─────────────────────────────────────────────────────────────

    /**
     * @dev CO-199 FIX: `submitter` is now `indexed`.
     *
     * Before:
     *   event ClaimCreated(uint256 indexed claimId, address submitter, ...);
     *
     * After:
     *   event ClaimCreated(uint256 indexed claimId, address indexed submitter, ...);
     *
     * This allows node/subgraph queries such as:
     *   eth_getLogs({ topics: [CLAIM_CREATED_SIG, null, addressTopic(submitter)] })
     */
    event ClaimCreated(
        uint256 indexed claimId,
        address indexed submitter,   // ← CO-199: was non-indexed
        string  content,
        uint256 verificationWindowEnd
    );

    event VoteCast(uint256 indexed claimId, address indexed verifier, bool support, uint256 stakeAmount);
    event ClaimSettled(uint256 indexed claimId, bool passed, uint256 totalStakedFor, uint256 totalStakedAgainst, uint256 totalRewards, uint256 totalSlashed);
    event RewardsDistributed(uint256 indexed claimId, address indexed verifier, uint256 amount);
    event StakeSlashed(uint256 indexed claimId, address indexed verifier, uint256 amount);
    event StakeDeposited(address indexed verifier, uint256 amount);
    event StakeWithdrawn(address indexed verifier, uint256 amount);
    event RewardsClaimed(address indexed verifier, uint256 amount);

    // ── Constructor ────────────────────────────────────────────────────────

    constructor(
        address _bountyToken,
        address initialAdmin,
        address _governanceController
    ) {
        require(_bountyToken    != address(0), "Invalid token address");
        require(initialAdmin    != address(0), "Invalid admin address");

        bountyToken = IERC20(_bountyToken);

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE,         initialAdmin);
        _grantRole(PAUSER_ROLE,        initialAdmin);

        _setRoleAdmin(RESOLVER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TREASURY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE,   ADMIN_ROLE);

        _initializeGovernance(_governanceController, initialAdmin, initialAdmin);
    }

    // ── Core Functions ─────────────────────────────────────────────────────

    function createClaim(string memory content) external whenNotPaused returns (uint256) {
        uint256 claimId = claimCounter++;
        uint256 windowEnd = block.timestamp + verificationWindowDuration;

        claims[claimId] = Claim({
            id:                    claimId,
            submitter:             msg.sender,
            content:               content,
            createdAt:             block.timestamp,
            verificationWindowEnd: windowEnd,
            settled:               false,
            totalStakedFor:        0,
            totalStakedAgainst:    0,
            totalStakeAmount:      0
        });

        // CO-199: submitter is now emitted as an indexed topic
        emit ClaimCreated(claimId, msg.sender, content, windowEnd);
        return claimId;
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= minStakeAmount, "Stake below minimum");
        require(bountyToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        verifierStakes[msg.sender].totalStaked += amount;
        emit StakeDeposited(msg.sender, amount);
    }

    function vote(uint256 claimId, bool support, uint256 stakeAmount) external nonReentrant whenNotPaused {
        Claim storage claim = claims[claimId];
        require(claim.submitter != address(0),                                "Claim does not exist");
        require(block.timestamp < claim.verificationWindowEnd,               "Verification window closed");
        require(!claim.settled,                                               "Claim already settled");
        require(!votes[claimId][msg.sender].voted,                           "Already voted");
        require(stakeAmount >= minStakeAmount,                                "Stake below minimum");
        require(
            verifierStakes[msg.sender].totalStaked >=
                verifierStakes[msg.sender].activeStakes + stakeAmount,
            "Insufficient available stake"
        );

        verifierStakes[msg.sender].activeStakes += stakeAmount;
        votes[claimId][msg.sender] = Vote({
            voted:         true,
            support:       support,
            stakeAmount:   stakeAmount,
            rewardClaimed: false,
            stakeReturned: false
        });

        if (support) claim.totalStakedFor     += stakeAmount;
        else         claim.totalStakedAgainst += stakeAmount;
        claim.totalStakeAmount += stakeAmount;

        emit VoteCast(claimId, msg.sender, support, stakeAmount);
    }

    function settleClaim(uint256 claimId) external nonReentrant whenNotPaused {
        Claim storage claim = claims[claimId];
        require(claim.submitter != address(0),                               "Claim does not exist");
        require(block.timestamp >= claim.verificationWindowEnd,              "Verification window not closed");
        require(!claim.settled,                                              "Claim already settled");
        require(claim.totalStakeAmount > 0,                                  "No votes cast");

        claim.settled = true;
        bool passed = _determineOutcome(claim.totalStakedFor, claim.totalStakedAgainst);
        (uint256 rewardAmount, uint256 slashedAmount) = _calculateSettlement(claimId, passed);

        emit ClaimSettled(claimId, passed, claim.totalStakedFor, claim.totalStakedAgainst, rewardAmount, slashedAmount);
    }

    function claimSettlementRewards(uint256 claimId) external nonReentrant whenNotPaused {
        Claim storage claim = claims[claimId];
        require(claim.settled, "Claim not settled");

        Vote storage v = votes[claimId][msg.sender];
        require(v.voted,           "No vote cast");
        require(!v.rewardClaimed,  "Rewards already claimed");

        SettlementResult storage settlement = settlementResults[claimId];
        require(settlement.winnerStake > 0,              "No winners");
        require(v.support == settlement.passed,          "Not a winner");

        uint256 reward = (v.stakeAmount * settlement.totalRewards) / settlement.winnerStake;
        v.rewardClaimed = true;

        if (reward > 0) {
            require(bountyToken.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardsDistributed(claimId, msg.sender, reward);
        }

        if (!v.stakeReturned) {
            v.stakeReturned = true;
            verifierStakes[msg.sender].activeStakes -= v.stakeAmount;
            require(bountyToken.transfer(msg.sender, v.stakeAmount), "Stake transfer failed");
        }
    }

    function withdrawSettledStake(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.settled, "Claim not settled");

        Vote storage v = votes[claimId][msg.sender];
        require(v.voted,          "No vote cast");
        require(!v.stakeReturned, "Stake already returned");

        SettlementResult storage settlement = settlementResults[claimId];
        bool isWinner = (v.support == settlement.passed);
        require(!isWinner, "Winners should use claimSettlementRewards");

        uint256 slashedAmount = (v.stakeAmount * slashPercent) / 100;
        uint256 returnAmount  = v.stakeAmount - slashedAmount;

        v.stakeReturned = true;
        verifierStakes[msg.sender].activeStakes -= v.stakeAmount;

        if (returnAmount > 0) {
            require(bountyToken.transfer(msg.sender, returnAmount), "Stake transfer failed");
        }
        emit StakeWithdrawn(msg.sender, returnAmount);
    }

    function withdrawStake(uint256 amount) external nonReentrant whenNotPaused {
        VerifierStake storage s = verifierStakes[msg.sender];
        require(s.totalStaked >= s.activeStakes + amount, "Insufficient available stake");
        s.totalStaked -= amount;
        require(bountyToken.transfer(msg.sender, amount), "Transfer failed");
        emit StakeWithdrawn(msg.sender, amount);
    }

    // ── Internal Helpers ───────────────────────────────────────────────────

    function _determineOutcome(uint256 stakedFor, uint256 stakedAgainst) internal view returns (bool) {
        uint256 total = stakedFor + stakedAgainst;
        if (total == 0) return false;
        return (stakedFor * 100) / total >= settlementThresholdPercent;
    }

    function _calculateSettlement(uint256 claimId, bool passed) internal returns (uint256 rewardAmount, uint256 slashedAmount) {
        Claim storage claim = claims[claimId];
        uint256 winnerStake = passed ? claim.totalStakedFor   : claim.totalStakedAgainst;
        uint256 loserStake  = passed ? claim.totalStakedAgainst : claim.totalStakedFor;

        slashedAmount = (loserStake  * slashPercent)  / 100;
        rewardAmount  = (slashedAmount * rewardPercent) / 100;

        totalSlashed  += slashedAmount;
        totalRewarded += rewardAmount;

        settlementResults[claimId] = SettlementResult({
            passed:       passed,
            totalRewards: rewardAmount,
            totalSlashed: slashedAmount,
            winnerStake:  winnerStake,
            loserStake:   loserStake
        });
    }

    // ── View Functions ─────────────────────────────────────────────────────

    function getClaim(uint256 claimId)                      external view returns (Claim memory)         { return claims[claimId]; }
    function getVote(uint256 claimId, address verifier)     external view returns (Vote memory)          { return votes[claimId][verifier]; }
    function getVerifierStake(address verifier)             external view returns (VerifierStake memory) { return verifierStakes[verifier]; }

    // ── Governance Parameter Setters ───────────────────────────────────────

    function setVerificationWindowDuration(uint256 v) external onlyGovernanceOrAdmin {
        require(v >= 1 days && v <= 30 days, "Invalid duration");
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_VERIFICATION_WINDOW, verificationWindowDuration, v);
        verificationWindowDuration = v;
    }

    function setMinStakeAmount(uint256 v) external onlyGovernanceOrAdmin {
        require(v > 0, "Invalid amount");
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_MIN_STAKE, minStakeAmount, v);
        minStakeAmount = v;
    }

    function setSettlementThresholdPercent(uint256 v) external onlyGovernanceOrAdmin {
        require(v > 0 && v <= 100, "Invalid threshold");
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_THRESHOLD, settlementThresholdPercent, v);
        settlementThresholdPercent = v;
    }

    function setRewardPercent(uint256 v) external onlyGovernanceOrAdmin {
        require(v > 0 && v <= 100, "Invalid percent");
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_REWARD, rewardPercent, v);
        rewardPercent = v;
    }

    function setSlashPercent(uint256 v) external onlyGovernanceOrAdmin {
        require(v > 0 && v <= 100, "Invalid percent");
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_SLASH, slashPercent, v);
        slashPercent = v;
    }

    // ── Pauser ─────────────────────────────────────────────────────────────

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
