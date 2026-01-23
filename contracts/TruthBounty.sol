// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
        _mint(msg.sender, 10_000_000 * 10 ** decimals()); // Initial supply
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        _mint(to, amount);
    }
}
