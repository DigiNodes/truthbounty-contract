// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TruthBounty
 * @notice Main contract for handling verifications with dispute windows
 */
contract TruthBounty {
    // Token contract reference
    TruthBountyToken public token;

    // Dispute window duration (in seconds)
    uint256 public disputeWindowDuration;

    // Verification status enum
    enum VerificationStatus {
        Pending,
        Verified,
        Disputed,
        Resolved,
        Settled
    }

    // Dispute status enum
    enum DisputeStatus {
        Active,
        Resolved,
        Dismissed
    }

    // Verification struct
    struct Verification {
        uint256 id;
        address verifier;
        string contentHash; // IPFS hash or content identifier
        bool result; // true = verified, false = rejected
        VerificationStatus status;
        uint256 createdAt;
        uint256 disputeWindowEnd; // Timestamp when dispute window closes
        uint256 disputeId; // Active dispute ID, 0 if none
        uint256 settledAt; // Timestamp when settled, 0 if not settled
    }

    // Dispute struct
    struct Dispute {
        uint256 id;
        uint256 verificationId;
        address disputer;
        string reason; // IPFS hash or reason for dispute
        DisputeStatus status;
        uint256 createdAt;
        uint256 resolvedAt; // Timestamp when resolved, 0 if not resolved
    }

    // Mappings
    mapping(uint256 => Verification) public verifications;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => bool) public verificationExists; // Track if verification exists

    // Counters
    uint256 public verificationCounter;
    uint256 public disputeCounter;

    // Events
    event VerificationCreated(
        uint256 indexed verificationId,
        address indexed verifier,
        string contentHash,
        bool result,
        uint256 disputeWindowEnd
    );

    event DisputeInitiated(
        uint256 indexed disputeId,
        uint256 indexed verificationId,
        address indexed disputer,
        string reason
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        uint256 indexed verificationId,
        DisputeStatus resolution
    );

    event VerificationSettled(
        uint256 indexed verificationId,
        uint256 settledAt
    );

    event DisputeWindowDurationUpdated(uint256 newDuration);

    // Modifiers
    modifier onlyExistingVerification(uint256 verificationId) {
        require(verificationExists[verificationId], "Verification does not exist");
        _;
    }

    modifier onlyActiveDispute(uint256 disputeId) {
        require(disputes[disputeId].status == DisputeStatus.Active, "Dispute is not active");
        _;
    }

    /**
     * @notice Constructor
     * @param _token Address of the TruthBountyToken contract
     * @param _disputeWindowDuration Initial dispute window duration in seconds
     */
    constructor(address _token, uint256 _disputeWindowDuration) {
        require(_token != address(0), "Token address cannot be zero");
        require(_disputeWindowDuration > 0, "Dispute window duration must be greater than 0");
        
        token = TruthBountyToken(_token);
        disputeWindowDuration = _disputeWindowDuration;
    }

    /**
     * @notice Create a new verification
     * @param contentHash IPFS hash or content identifier
     * @param result Verification result (true = verified, false = rejected)
     * @return verificationId The ID of the created verification
     */
    function createVerification(
        string memory contentHash,
        bool result
    ) external returns (uint256) {
        uint256 verificationId = ++verificationCounter;
        uint256 disputeWindowEnd = block.timestamp + disputeWindowDuration;

        verifications[verificationId] = Verification({
            id: verificationId,
            verifier: msg.sender,
            contentHash: contentHash,
            result: result,
            status: VerificationStatus.Verified,
            createdAt: block.timestamp,
            disputeWindowEnd: disputeWindowEnd,
            disputeId: 0,
            settledAt: 0
        });

        verificationExists[verificationId] = true;

        emit VerificationCreated(
            verificationId,
            msg.sender,
            contentHash,
            result,
            disputeWindowEnd
        );

        return verificationId;
    }

    /**
     * @notice Initiate a dispute for a verification within the dispute window
     * @param verificationId The ID of the verification to dispute
     * @param reason IPFS hash or reason for the dispute
     * @return disputeId The ID of the created dispute
     */
    function initiateDispute(
        uint256 verificationId,
        string memory reason
    ) external onlyExistingVerification(verificationId) returns (uint256) {
        Verification storage verification = verifications[verificationId];

        // Enforce strict window: dispute must be within the window
        require(
            block.timestamp < verification.disputeWindowEnd,
            "Dispute window has closed"
        );

        // Cannot dispute if already settled
        require(
            verification.status != VerificationStatus.Settled,
            "Verification already settled"
        );

        // Cannot dispute if there's already an active dispute
        require(
            verification.disputeId == 0 || disputes[verification.disputeId].status != DisputeStatus.Active,
            "Verification already has an active dispute"
        );

        // Create new dispute
        uint256 disputeId = ++disputeCounter;
        
        disputes[disputeId] = Dispute({
            id: disputeId,
            verificationId: verificationId,
            disputer: msg.sender,
            reason: reason,
            status: DisputeStatus.Active,
            createdAt: block.timestamp,
            resolvedAt: 0
        });

        // Update verification status
        verification.status = VerificationStatus.Disputed;
        verification.disputeId = disputeId;

        emit DisputeInitiated(disputeId, verificationId, msg.sender, reason);

        return disputeId;
    }

    /**
     * @notice Resolve a dispute
     * @param disputeId The ID of the dispute to resolve
     * @param resolution The resolution status (Resolved or Dismissed)
     */
    function resolveDispute(
        uint256 disputeId,
        DisputeStatus resolution
    ) external onlyActiveDispute(disputeId) {
        require(
            resolution == DisputeStatus.Resolved || resolution == DisputeStatus.Dismissed,
            "Invalid resolution status"
        );

        Dispute storage dispute = disputes[disputeId];
        Verification storage verification = verifications[dispute.verificationId];

        // Update dispute status
        dispute.status = resolution;
        dispute.resolvedAt = block.timestamp;

        // Update verification status based on resolution
        if (resolution == DisputeStatus.Resolved) {
            // Dispute was valid, verification remains disputed/resolved
            verification.status = VerificationStatus.Resolved;
            // Keep disputeId for historical record, but dispute is no longer active
        } else {
            // Dispute was dismissed, revert verification to verified status
            verification.status = VerificationStatus.Verified;
            verification.disputeId = 0; // Clear dispute reference
        }

        emit DisputeResolved(disputeId, dispute.verificationId, resolution);
    }

    /**
     * @notice Settle a verification (only if no active disputes and window closed)
     * @param verificationId The ID of the verification to settle
     */
    function settleVerification(
        uint256 verificationId
    ) external onlyExistingVerification(verificationId) {
        Verification storage verification = verifications[verificationId];

        // Block settlement if there's an active dispute
        require(
            verification.disputeId == 0 || disputes[verification.disputeId].status != DisputeStatus.Active,
            "Cannot settle: active dispute exists"
        );

        // Block settlement if still within dispute window (strict: must be after window end)
        require(
            block.timestamp >= verification.disputeWindowEnd,
            "Cannot settle: dispute window still open"
        );

        // Cannot settle if already settled
        require(
            verification.status != VerificationStatus.Settled,
            "Verification already settled"
        );

        // Update verification status
        verification.status = VerificationStatus.Settled;
        verification.settledAt = block.timestamp;

        emit VerificationSettled(verificationId, block.timestamp);
    }

    /**
     * @notice Update dispute window duration (only owner/admin)
     * @param newDuration New dispute window duration in seconds
     */
    function setDisputeWindowDuration(uint256 newDuration) external {
        // Note: In production, add access control (e.g., onlyOwner)
        require(newDuration > 0, "Dispute window duration must be greater than 0");
        
        disputeWindowDuration = newDuration;
        
        emit DisputeWindowDurationUpdated(newDuration);
    }

    /**
     * @notice Check if a verification can be disputed
     * @param verificationId The ID of the verification
     * @return canDisputeResult True if dispute can be initiated
     * @return reason Reason why dispute cannot be initiated (if applicable)
     */
    function canDispute(uint256 verificationId) external view returns (bool canDisputeResult, string memory reason) {
        if (!verificationExists[verificationId]) {
            return (false, "Verification does not exist");
        }

        Verification memory verification = verifications[verificationId];

        if (block.timestamp >= verification.disputeWindowEnd) {
            return (false, "Dispute window has closed");
        }

        if (verification.status == VerificationStatus.Settled) {
            return (false, "Verification already settled");
        }

        if (verification.disputeId != 0 && disputes[verification.disputeId].status == DisputeStatus.Active) {
            return (false, "Verification already has an active dispute");
        }

        return (true, "");
    }

    /**
     * @notice Check if a verification can be settled
     * @param verificationId The ID of the verification
     * @return canSettleResult True if verification can be settled
     * @return reason Reason why verification cannot be settled (if applicable)
     */
    function canSettle(uint256 verificationId) external view returns (bool canSettleResult, string memory reason) {
        if (!verificationExists[verificationId]) {
            return (false, "Verification does not exist");
        }

        Verification memory verification = verifications[verificationId];

        if (verification.status == VerificationStatus.Settled) {
            return (false, "Verification already settled");
        }

        if (verification.disputeId != 0 && disputes[verification.disputeId].status == DisputeStatus.Active) {
            return (false, "Active dispute exists");
        }

        if (block.timestamp <= verification.disputeWindowEnd) {
            return (false, "Dispute window still open");
        }

        return (true, "");
    }

    /**
     * @notice Get verification details
     * @param verificationId The ID of the verification
     * @return verification The verification struct
     */
    function getVerification(uint256 verificationId) external view returns (Verification memory) {
        require(verificationExists[verificationId], "Verification does not exist");
        return verifications[verificationId];
    }

    /**
     * @notice Get dispute details
     * @param disputeId The ID of the dispute
     * @return dispute The dispute struct
     */
    function getDispute(uint256 disputeId) external view returns (Dispute memory) {
        require(disputeId > 0 && disputeId <= disputeCounter, "Dispute does not exist");
        return disputes[disputeId];
    }
}

/**
 * @title TruthBountyToken
 * @notice ERC20 token for TruthBounty rewards
 */
contract TruthBountyToken is ERC20 {
    address public owner;

    constructor() ERC20("TruthBounty", "BOUNTY") {
        owner = msg.sender;
    }
}

/**
 * @title TruthBounty
 * @notice Main contract for claim verification, voting, and settlement
 */
contract TruthBounty is Ownable, ReentrancyGuard {
    // Token contract
    IERC20 public immutable bountyToken;

    // Claim structure
    struct Claim {
        uint256 id;
        address submitter;
        string content; // IPFS hash or content reference
        uint256 createdAt;
        uint256 verificationWindowEnd; // Timestamp when verification window closes
        bool settled;
        uint256 totalStakedFor; // Weighted votes for claim (pass)
        uint256 totalStakedAgainst; // Weighted votes against claim (fail)
        uint256 totalStakeAmount; // Total stake amount in this claim
    }

    // Vote structure
    struct Vote {
        bool voted;
        bool support; // true = pass, false = fail
        uint256 stakeAmount;
        bool rewardClaimed; // Whether rewards have been claimed for this vote
        bool stakeReturned; // Whether stake has been returned
    }

    // Settlement result for a claim
    struct SettlementResult {
        bool passed;
        uint256 totalRewards;
        uint256 totalSlashed;
        uint256 winnerStake;
        uint256 loserStake;
    }

    // Verifier staking information
    struct VerifierStake {
        uint256 totalStaked;
        uint256 activeStakes; // Stakes currently locked in active claims
    }

    // Claim state
    mapping(uint256 => Claim) public claims;
    mapping(uint256 => SettlementResult) public settlementResults; // claimId => settlement
    mapping(uint256 => mapping(address => Vote)) public votes; // claimId => verifier => vote
    mapping(address => VerifierStake) public verifierStakes;
    mapping(address => uint256) public verifierRewards; // Accumulated rewards

    // Configuration
    uint256 public constant VERIFICATION_WINDOW_DURATION = 7 days;
    uint256 public constant MIN_STAKE_AMOUNT = 100 * 10**18; // Minimum stake to vote
    uint256 public constant SETTLEMENT_THRESHOLD_PERCENT = 60; // 60% threshold for pass/fail
    uint256 public constant REWARD_PERCENT = 80; // 80% of slashed tokens go to winners
    uint256 public constant SLASH_PERCENT = 20; // 20% of staked tokens slashed from losers

    // State
    uint256 public claimCounter;
    uint256 public totalSlashed;
    uint256 public totalRewarded;

    // Events
    event ClaimCreated(
        uint256 indexed claimId,
        address indexed submitter,
        string content,
        uint256 verificationWindowEnd
    );
    event VoteCast(
        uint256 indexed claimId,
        address indexed verifier,
        bool support,
        uint256 stakeAmount
    );
    event ClaimSettled(
        uint256 indexed claimId,
        bool passed,
        uint256 totalStakedFor,
        uint256 totalStakedAgainst,
        uint256 totalRewards,
        uint256 totalSlashed
    );
    event RewardsDistributed(
        uint256 indexed claimId,
        address indexed verifier,
        uint256 amount
    );
    event StakeSlashed(
        uint256 indexed claimId,
        address indexed verifier,
        uint256 amount
    );
    event StakeDeposited(address indexed verifier, uint256 amount);
    event StakeWithdrawn(address indexed verifier, uint256 amount);
    event RewardsClaimed(address indexed verifier, uint256 amount);

    constructor(address _bountyToken) Ownable(msg.sender) {
        require(_bountyToken != address(0), "Invalid token address");
        bountyToken = IERC20(_bountyToken);
    }

    /**
     * @notice Create a new claim for verification
     * @param content IPFS hash or content reference
     * @return claimId The ID of the newly created claim
     */
    function createClaim(string memory content) external returns (uint256) {
        uint256 claimId = claimCounter++;
        uint256 verificationWindowEnd = block.timestamp + VERIFICATION_WINDOW_DURATION;

        claims[claimId] = Claim({
            id: claimId,
            submitter: msg.sender,
            content: content,
            createdAt: block.timestamp,
            verificationWindowEnd: verificationWindowEnd,
            settled: false,
            totalStakedFor: 0,
            totalStakedAgainst: 0,
            totalStakeAmount: 0
        });

        emit ClaimCreated(claimId, msg.sender, content, verificationWindowEnd);
        return claimId;
    }

    /**
     * @notice Stake tokens to participate in verification
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount >= MIN_STAKE_AMOUNT, "Stake below minimum");
        require(bountyToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        verifierStakes[msg.sender].totalStaked += amount;

        emit StakeDeposited(msg.sender, amount);
    }

    /**
     * @notice Vote on a claim (pass or fail)
     * @param claimId The ID of the claim to vote on
     * @param support true for pass, false for fail
     * @param stakeAmount Amount of stake to commit to this vote
     */
    function vote(
        uint256 claimId,
        bool support,
        uint256 stakeAmount
    ) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(block.timestamp < claim.verificationWindowEnd, "Verification window closed");
        require(!claim.settled, "Claim already settled");
        require(!votes[claimId][msg.sender].voted, "Already voted");
        require(stakeAmount >= MIN_STAKE_AMOUNT, "Stake below minimum");
        require(
            verifierStakes[msg.sender].totalStaked >=
                verifierStakes[msg.sender].activeStakes + stakeAmount,
            "Insufficient available stake"
        );

        // Lock the stake
        verifierStakes[msg.sender].activeStakes += stakeAmount;

        // Record the vote
        votes[claimId][msg.sender] = Vote({
            voted: true,
            support: support,
            stakeAmount: stakeAmount,
            rewardClaimed: false,
            stakeReturned: false
        });

        // Update claim totals
        if (support) {
            claim.totalStakedFor += stakeAmount;
        } else {
            claim.totalStakedAgainst += stakeAmount;
        }
        claim.totalStakeAmount += stakeAmount;

        emit VoteCast(claimId, msg.sender, support, stakeAmount);
    }

    /**
     * @notice Settle a claim after verification window closes
     * @param claimId The ID of the claim to settle
     */
    function settleClaim(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(block.timestamp >= claim.verificationWindowEnd, "Verification window not closed");
        require(!claim.settled, "Claim already settled");
        require(claim.totalStakeAmount > 0, "No votes cast");

        claim.settled = true;

        // Determine outcome based on weighted votes
        bool passed = _determineOutcome(claim.totalStakedFor, claim.totalStakedAgainst);

        // Calculate rewards and slashing
        (uint256 rewardAmount, uint256 slashedAmount) = _calculateSettlement(
            claimId,
            passed
        );

        emit ClaimSettled(
            claimId,
            passed,
            claim.totalStakedFor,
            claim.totalStakedAgainst,
            rewardAmount,
            slashedAmount
        );
    }

    /**
     * @notice Determine if claim passed or failed based on threshold
     * @param stakedFor Total weighted votes for
     * @param stakedAgainst Total weighted votes against
     * @return passed true if claim passed, false otherwise
     */
    function _determineOutcome(
        uint256 stakedFor,
        uint256 stakedAgainst
    ) internal pure returns (bool) {
        uint256 totalStake = stakedFor + stakedAgainst;
        if (totalStake == 0) return false;

        // Calculate percentage for "for" votes
        uint256 forPercent = (stakedFor * 100) / totalStake;

        // Claim passes if >= 60% support
        return forPercent >= SETTLEMENT_THRESHOLD_PERCENT;
    }

    /**
     * @notice Calculate and store settlement results for a claim
     * @param claimId The ID of the claim
     * @param passed Whether the claim passed or failed
     * @return rewardAmount Total rewards to be distributed
     * @return slashedAmount Total tokens to be slashed
     */
    function _calculateSettlement(
        uint256 claimId,
        bool passed
    ) internal returns (uint256 rewardAmount, uint256 slashedAmount) {
        Claim storage claim = claims[claimId];
        uint256 winnerStake = passed ? claim.totalStakedFor : claim.totalStakedAgainst;
        uint256 loserStake = passed ? claim.totalStakedAgainst : claim.totalStakedFor;

        // Calculate slashing from losers (20% of their stake)
        slashedAmount = (loserStake * SLASH_PERCENT) / 100;

        // Calculate rewards for winners (80% of slashed tokens)
        rewardAmount = (slashedAmount * REWARD_PERCENT) / 100;
        
        // Track in state (update state variables)
        totalSlashed += slashedAmount;
        totalRewarded += rewardAmount;

        // Store settlement results for pull-based claiming
        settlementResults[claimId] = SettlementResult({
            passed: passed,
            totalRewards: rewardAmount,
            totalSlashed: slashedAmount,
            winnerStake: winnerStake,
            loserStake: loserStake
        });
    }

    /**
     * @notice Claim rewards and return stake for a specific claim (pull-based)
     * @param claimId The ID of the settled claim
     */
    function claimSettlementRewards(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(claim.settled, "Claim not settled");
        
        Vote storage vote = votes[claimId][msg.sender];
        require(vote.voted, "No vote cast");
        require(!vote.rewardClaimed, "Rewards already claimed");

        SettlementResult storage settlement = settlementResults[claimId];
        require(settlement.winnerStake > 0, "No winners");

        // Check if verifier was on the winning side
        bool isWinner = (vote.support == settlement.passed);
        require(isWinner, "Not a winner");

        // Calculate proportional reward
        uint256 reward = (vote.stakeAmount * settlement.totalRewards) / settlement.winnerStake;
        
        // Mark as claimed
        vote.rewardClaimed = true;

        // Transfer reward
        if (reward > 0) {
            require(bountyToken.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardsDistributed(claimId, msg.sender, reward);
        }

        // Return stake (winners get full stake back)
        if (!vote.stakeReturned) {
            vote.stakeReturned = true;
            verifierStakes[msg.sender].activeStakes -= vote.stakeAmount;
            require(bountyToken.transfer(msg.sender, vote.stakeAmount), "Stake transfer failed");
        }
    }

    /**
     * @notice Withdraw stake after settlement (for losers, stake is already slashed)
     * @param claimId The ID of the settled claim
     */
    function withdrawSettledStake(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(claim.settled, "Claim not settled");
        
        Vote storage vote = votes[claimId][msg.sender];
        require(vote.voted, "No vote cast");
        require(!vote.stakeReturned, "Stake already returned");

        SettlementResult storage settlement = settlementResults[claimId];
        bool isWinner = (vote.support == settlement.passed);

        uint256 stakeToReturn;
        
        if (isWinner) {
            // Winners get full stake back (already handled in claimSettlementRewards, but allow separate call)
            stakeToReturn = vote.stakeAmount;
        } else {
            // Losers get stake back minus slashing (80% of original stake)
            uint256 slashAmount = (vote.stakeAmount * SLASH_PERCENT) / 100;
            stakeToReturn = vote.stakeAmount - slashAmount;
            
            // Emit slashing event
            emit StakeSlashed(claimId, msg.sender, slashAmount);
        }

        // Mark as returned
        vote.stakeReturned = true;

        // Update verifier stake tracking
        verifierStakes[msg.sender].activeStakes -= vote.stakeAmount;
        if (!isWinner) {
            verifierStakes[msg.sender].totalStaked -= (vote.stakeAmount - stakeToReturn);
        }

        // Transfer remaining stake
        if (stakeToReturn > 0) {
            require(bountyToken.transfer(msg.sender, stakeToReturn), "Stake transfer failed");
        }
    }

    /**
     * @notice Internal helper to return stake to verifier
     */
    function _returnStake(uint256 claimId, address verifier, uint256 stakeAmount) internal {
        Vote storage vote = votes[claimId][verifier];
        if (vote.stakeReturned) return;

        vote.stakeReturned = true;
        verifierStakes[verifier].activeStakes -= stakeAmount;
    }

    /**
     * @notice Claim accumulated rewards from multiple claims
     */
    function claimRewards() external nonReentrant {
        uint256 amount = verifierRewards[msg.sender];
        require(amount > 0, "No rewards to claim");

        verifierRewards[msg.sender] = 0;
        require(bountyToken.transfer(msg.sender, amount), "Transfer failed");

        emit RewardsClaimed(msg.sender, amount);
    }

    /**
     * @notice Withdraw available stake (not locked in active claims)
     */
    function withdrawStake(uint256 amount) external nonReentrant {
        VerifierStake storage stake = verifierStakes[msg.sender];
        require(
            stake.totalStaked >= stake.activeStakes + amount,
            "Insufficient available stake"
        );

        stake.totalStaked -= amount;
        require(bountyToken.transfer(msg.sender, amount), "Transfer failed");

        emit StakeWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Get claim details
     */
    function getClaim(
        uint256 claimId
    ) external view returns (Claim memory) {
        return claims[claimId];
    }

    /**
     * @notice Get vote details for a verifier on a claim
     */
    function getVote(
        uint256 claimId,
        address verifier
    ) external view returns (Vote memory) {
        return votes[claimId][verifier];
    }

    /**
     * @notice Get verifier stake information
     */
    function getVerifierStake(
        address verifier
    ) external view returns (VerifierStake memory) {
        return verifierStakes[verifier];
    }
}

/**
 * @title TruthBounty
 * @notice Main contract for claim verification, voting, and settlement
 */
contract TruthBounty is Ownable, ReentrancyGuard {
    // Token contract
    IERC20 public immutable bountyToken;

    // Claim structure
    struct Claim {
        uint256 id;
        address submitter;
        string content; // IPFS hash or content reference
        uint256 createdAt;
        uint256 verificationWindowEnd; // Timestamp when verification window closes
        bool settled;
        uint256 totalStakedFor; // Weighted votes for claim (pass)
        uint256 totalStakedAgainst; // Weighted votes against claim (fail)
        uint256 totalStakeAmount; // Total stake amount in this claim
    }

    // Vote structure
    struct Vote {
        bool voted;
        bool support; // true = pass, false = fail
        uint256 stakeAmount;
        bool rewardClaimed; // Whether rewards have been claimed for this vote
        bool stakeReturned; // Whether stake has been returned
    }

    // Settlement result for a claim
    struct SettlementResult {
        bool passed;
        uint256 totalRewards;
        uint256 totalSlashed;
        uint256 winnerStake;
        uint256 loserStake;
    }

    // Verifier staking information
    struct VerifierStake {
        uint256 totalStaked;
        uint256 activeStakes; // Stakes currently locked in active claims
    }

    // Claim state
    mapping(uint256 => Claim) public claims;
    mapping(uint256 => SettlementResult) public settlementResults; // claimId => settlement
    mapping(uint256 => mapping(address => Vote)) public votes; // claimId => verifier => vote
    mapping(address => VerifierStake) public verifierStakes;
    mapping(address => uint256) public verifierRewards; // Accumulated rewards

    // Configuration
    uint256 public constant VERIFICATION_WINDOW_DURATION = 7 days;
    uint256 public constant MIN_STAKE_AMOUNT = 100 * 10**18; // Minimum stake to vote
    uint256 public constant SETTLEMENT_THRESHOLD_PERCENT = 60; // 60% threshold for pass/fail
    uint256 public constant REWARD_PERCENT = 80; // 80% of slashed tokens go to winners
    uint256 public constant SLASH_PERCENT = 20; // 20% of staked tokens slashed from losers

    // State
    uint256 public claimCounter;
    uint256 public totalSlashed;
    uint256 public totalRewarded;

    // Events
    event ClaimCreated(
        uint256 indexed claimId,
        address indexed submitter,
        string content,
        uint256 verificationWindowEnd
    );
    event VoteCast(
        uint256 indexed claimId,
        address indexed verifier,
        bool support,
        uint256 stakeAmount
    );
    event ClaimSettled(
        uint256 indexed claimId,
        bool passed,
        uint256 totalStakedFor,
        uint256 totalStakedAgainst,
        uint256 totalRewards,
        uint256 totalSlashed
    );
    event RewardsDistributed(
        uint256 indexed claimId,
        address indexed verifier,
        uint256 amount
    );
    event StakeSlashed(
        uint256 indexed claimId,
        address indexed verifier,
        uint256 amount
    );
    event StakeDeposited(address indexed verifier, uint256 amount);
    event StakeWithdrawn(address indexed verifier, uint256 amount);
    event RewardsClaimed(address indexed verifier, uint256 amount);

    constructor(address _bountyToken) Ownable(msg.sender) {
        require(_bountyToken != address(0), "Invalid token address");
        bountyToken = IERC20(_bountyToken);
    }

    /**
     * @notice Create a new claim for verification
     * @param content IPFS hash or content reference
     * @return claimId The ID of the newly created claim
     */
    function createClaim(string memory content) external returns (uint256) {
        uint256 claimId = claimCounter++;
        uint256 verificationWindowEnd = block.timestamp + VERIFICATION_WINDOW_DURATION;

        claims[claimId] = Claim({
            id: claimId,
            submitter: msg.sender,
            content: content,
            createdAt: block.timestamp,
            verificationWindowEnd: verificationWindowEnd,
            settled: false,
            totalStakedFor: 0,
            totalStakedAgainst: 0,
            totalStakeAmount: 0
        });

        emit ClaimCreated(claimId, msg.sender, content, verificationWindowEnd);
        return claimId;
    }

    /**
     * @notice Stake tokens to participate in verification
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount >= MIN_STAKE_AMOUNT, "Stake below minimum");
        require(bountyToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        verifierStakes[msg.sender].totalStaked += amount;

        emit StakeDeposited(msg.sender, amount);
    }

    /**
     * @notice Vote on a claim (pass or fail)
     * @param claimId The ID of the claim to vote on
     * @param support true for pass, false for fail
     * @param stakeAmount Amount of stake to commit to this vote
     */
    function vote(
        uint256 claimId,
        bool support,
        uint256 stakeAmount
    ) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(block.timestamp < claim.verificationWindowEnd, "Verification window closed");
        require(!claim.settled, "Claim already settled");
        require(!votes[claimId][msg.sender].voted, "Already voted");
        require(stakeAmount >= MIN_STAKE_AMOUNT, "Stake below minimum");
        require(
            verifierStakes[msg.sender].totalStaked >=
                verifierStakes[msg.sender].activeStakes + stakeAmount,
            "Insufficient available stake"
        );

        // Lock the stake
        verifierStakes[msg.sender].activeStakes += stakeAmount;

        // Record the vote
        votes[claimId][msg.sender] = Vote({
            voted: true,
            support: support,
            stakeAmount: stakeAmount,
            rewardClaimed: false,
            stakeReturned: false
        });

        // Update claim totals
        if (support) {
            claim.totalStakedFor += stakeAmount;
        } else {
            claim.totalStakedAgainst += stakeAmount;
        }
        claim.totalStakeAmount += stakeAmount;

        emit VoteCast(claimId, msg.sender, support, stakeAmount);
    }

    /**
     * @notice Settle a claim after verification window closes
     * @param claimId The ID of the claim to settle
     */
    function settleClaim(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(block.timestamp >= claim.verificationWindowEnd, "Verification window not closed");
        require(!claim.settled, "Claim already settled");
        require(claim.totalStakeAmount > 0, "No votes cast");

        claim.settled = true;

        // Determine outcome based on weighted votes
        bool passed = _determineOutcome(claim.totalStakedFor, claim.totalStakedAgainst);

        // Calculate rewards and slashing
        (uint256 rewardAmount, uint256 slashedAmount) = _calculateSettlement(
            claimId,
            passed
        );

        emit ClaimSettled(
            claimId,
            passed,
            claim.totalStakedFor,
            claim.totalStakedAgainst,
            rewardAmount,
            slashedAmount
        );
    }

    /**
     * @notice Determine if claim passed or failed based on threshold
     * @param stakedFor Total weighted votes for
     * @param stakedAgainst Total weighted votes against
     * @return passed true if claim passed, false otherwise
     */
    function _determineOutcome(
        uint256 stakedFor,
        uint256 stakedAgainst
    ) internal pure returns (bool) {
        uint256 totalStake = stakedFor + stakedAgainst;
        if (totalStake == 0) return false;

        // Calculate percentage for "for" votes
        uint256 forPercent = (stakedFor * 100) / totalStake;

        // Claim passes if >= 60% support
        return forPercent >= SETTLEMENT_THRESHOLD_PERCENT;
    }

    /**
     * @notice Calculate and store settlement results for a claim
     * @param claimId The ID of the claim
     * @param passed Whether the claim passed or failed
     * @return rewardAmount Total rewards to be distributed
     * @return slashedAmount Total tokens to be slashed
     */
    function _calculateSettlement(
        uint256 claimId,
        bool passed
    ) internal returns (uint256 rewardAmount, uint256 slashedAmount) {
        Claim storage claim = claims[claimId];
        uint256 winnerStake = passed ? claim.totalStakedFor : claim.totalStakedAgainst;
        uint256 loserStake = passed ? claim.totalStakedAgainst : claim.totalStakedFor;

        // Calculate slashing from losers (20% of their stake)
        slashedAmount = (loserStake * SLASH_PERCENT) / 100;

        // Calculate rewards for winners (80% of slashed tokens)
        rewardAmount = (slashedAmount * REWARD_PERCENT) / 100;
        
        // Track in state (update state variables)
        totalSlashed += slashedAmount;
        totalRewarded += rewardAmount;

        // Store settlement results for pull-based claiming
        settlementResults[claimId] = SettlementResult({
            passed: passed,
            totalRewards: rewardAmount,
            totalSlashed: slashedAmount,
            winnerStake: winnerStake,
            loserStake: loserStake
        });
    }

    /**
     * @notice Claim rewards and return stake for a specific claim (pull-based)
     * @param claimId The ID of the settled claim
     */
    function claimSettlementRewards(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(claim.settled, "Claim not settled");
        
        Vote storage vote = votes[claimId][msg.sender];
        require(vote.voted, "No vote cast");
        require(!vote.rewardClaimed, "Rewards already claimed");

        SettlementResult storage settlement = settlementResults[claimId];
        require(settlement.winnerStake > 0, "No winners");

        // Check if verifier was on the winning side
        bool isWinner = (vote.support == settlement.passed);
        require(isWinner, "Not a winner");

        // Calculate proportional reward
        uint256 reward = (vote.stakeAmount * settlement.totalRewards) / settlement.winnerStake;
        
        // Mark as claimed
        vote.rewardClaimed = true;

        // Transfer reward
        if (reward > 0) {
            require(bountyToken.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardsDistributed(claimId, msg.sender, reward);
        }

        // Return stake (winners get full stake back)
        if (!vote.stakeReturned) {
            vote.stakeReturned = true;
            verifierStakes[msg.sender].activeStakes -= vote.stakeAmount;
            require(bountyToken.transfer(msg.sender, vote.stakeAmount), "Stake transfer failed");
        }
    }

    /**
     * @notice Withdraw stake after settlement (for losers, stake is already slashed)
     * @param claimId The ID of the settled claim
     */
    function withdrawSettledStake(uint256 claimId) external nonReentrant {
        Claim storage claim = claims[claimId];
        require(claim.id == claimId, "Claim does not exist");
        require(claim.settled, "Claim not settled");
        
        Vote storage vote = votes[claimId][msg.sender];
        require(vote.voted, "No vote cast");
        require(!vote.stakeReturned, "Stake already returned");

        SettlementResult storage settlement = settlementResults[claimId];
        bool isWinner = (vote.support == settlement.passed);

        uint256 stakeToReturn;
        
        if (isWinner) {
            // Winners get full stake back (already handled in claimSettlementRewards, but allow separate call)
            stakeToReturn = vote.stakeAmount;
        } else {
            // Losers get stake back minus slashing (80% of original stake)
            uint256 slashAmount = (vote.stakeAmount * SLASH_PERCENT) / 100;
            stakeToReturn = vote.stakeAmount - slashAmount;
            
            // Emit slashing event
            emit StakeSlashed(claimId, msg.sender, slashAmount);
        }

        // Mark as returned
        vote.stakeReturned = true;

        // Update verifier stake tracking
        verifierStakes[msg.sender].activeStakes -= vote.stakeAmount;
        if (!isWinner) {
            verifierStakes[msg.sender].totalStaked -= (vote.stakeAmount - stakeToReturn);
        }

        // Transfer remaining stake
        if (stakeToReturn > 0) {
            require(bountyToken.transfer(msg.sender, stakeToReturn), "Stake transfer failed");
        }
    }

    /**
     * @notice Internal helper to return stake to verifier
     */
    function _returnStake(uint256 claimId, address verifier, uint256 stakeAmount) internal {
        Vote storage vote = votes[claimId][verifier];
        if (vote.stakeReturned) return;

        vote.stakeReturned = true;
        verifierStakes[verifier].activeStakes -= stakeAmount;
    }

    /**
     * @notice Claim accumulated rewards from multiple claims
     */
    function claimRewards() external nonReentrant {
        uint256 amount = verifierRewards[msg.sender];
        require(amount > 0, "No rewards to claim");

        verifierRewards[msg.sender] = 0;
        require(bountyToken.transfer(msg.sender, amount), "Transfer failed");

        emit RewardsClaimed(msg.sender, amount);
    }

    /**
     * @notice Withdraw available stake (not locked in active claims)
     */
    function withdrawStake(uint256 amount) external nonReentrant {
        VerifierStake storage stake = verifierStakes[msg.sender];
        require(
            stake.totalStaked >= stake.activeStakes + amount,
            "Insufficient available stake"
        );

        stake.totalStaked -= amount;
        require(bountyToken.transfer(msg.sender, amount), "Transfer failed");

        emit StakeWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Get claim details
     */
    function getClaim(
        uint256 claimId
    ) external view returns (Claim memory) {
        return claims[claimId];
    }

    /**
     * @notice Get vote details for a verifier on a claim
     */
    function getVote(
        uint256 claimId,
        address verifier
    ) external view returns (Vote memory) {
        return votes[claimId][verifier];
    }

    /**
     * @notice Get verifier stake information
     */
    function getVerifierStake(
        address verifier
    ) external view returns (VerifierStake memory) {
        return verifierStakes[verifier];
    }
}
