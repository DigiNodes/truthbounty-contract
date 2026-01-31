// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReputationDecay
 * @dev Manages user reputation with time-based decay for inactive users.
 *
 * Decay is calculated on-read (view function) for gas efficiency.
 * Users experience gradual reputation decay after an inactivity threshold.
 *
 * Decay Formula:
 *   epochsInactive = (currentTime - lastActivity) / epochDuration
 *   effectiveInactiveEpochs = max(0, epochsInactive - inactivityThreshold)
 *   decayPercent = min(effectiveInactiveEpochs * decayRatePerEpoch, maxDecayPercent)
 *   effectiveReputation = baseReputation * (100 - decayPercent) / 100
 */
contract ReputationDecay is Ownable {
    // ============ Storage ============

    /// @notice Base reputation scores (before decay calculation)
    mapping(address => uint256) public baseReputation;

    /// @notice Last activity timestamp for each user
    mapping(address => uint256) public lastActivityTimestamp;

    // ============ Merkle Root Storage ============

    /// @notice Merkle roots for reputation snapshots by epoch
    /// @dev epoch => merkle root (immutable once set)
    mapping(uint256 => bytes32) public reputationRoots;

    /// @notice Track which epochs have been committed
    /// @dev epoch => committed (true if root exists for this epoch)
    mapping(uint256 => bool) public epochCommitted;

    // ============ Decay Parameters ============

    /// @notice Percentage of reputation lost per epoch (in basis points, e.g., 100 = 1%)
    uint256 public decayRatePerEpoch = 100; // 1%

    /// @notice Duration of one epoch in seconds (default: 7 days)
    uint256 public epochDuration = 7 days;

    /// @notice Number of epochs before decay starts (default: 4 epochs = 28 days)
    uint256 public inactivityThreshold = 4;

    /// @notice Maximum total decay percentage (in basis points, e.g., 5000 = 50%)
    uint256 public maxDecayPercent = 5000; // 50%

    /// @notice Basis points constant for percentage calculations
    uint256 private constant BASIS_POINTS = 10000;

    // ============ Events ============

    /// @notice Emitted when a user's base reputation is updated
    event ReputationUpdated(
        address indexed user,
        uint256 oldReputation,
        uint256 newReputation,
        uint256 timestamp
    );

    /// @notice Emitted when user activity is recorded
    event ActivityRecorded(address indexed user, uint256 timestamp);

    /// @notice Emitted when decay parameters are updated
    event DecayParametersUpdated(
        uint256 rate,
        uint256 epochDuration,
        uint256 threshold,
        uint256 maxDecay
    );

    /// @notice Emitted when a reputation Merkle root is submitted
    event ReputationRootSubmitted(
        bytes32 indexed root,
        uint256 indexed epoch,
        address indexed submitter,
        uint256 timestamp
    );

    // ============ Errors ============

    error InvalidDecayRate();
    error InvalidEpochDuration();
    error InvalidMaxDecayPercent();
    error EpochAlreadyCommitted();
    error InvalidMerkleRoot();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Core Functions ============

    /**
     * @notice Get the effective reputation after applying decay
     * @param user The address to query
     * @return The current effective reputation (after decay)
     */
    function getEffectiveReputation(
        address user
    ) public view returns (uint256) {
        uint256 base = baseReputation[user];
        if (base == 0) return 0;

        uint256 lastActivity = lastActivityTimestamp[user];
        if (lastActivity == 0) {
            // No activity recorded, return base reputation
            return base;
        }

        // Calculate epochs since last activity
        uint256 timeSinceActivity = block.timestamp - lastActivity;
        uint256 epochsInactive = timeSinceActivity / epochDuration;

        // Check if within grace period
        if (epochsInactive <= inactivityThreshold) {
            return base;
        }

        // Calculate effective inactive epochs (after grace period)
        uint256 effectiveInactiveEpochs = epochsInactive - inactivityThreshold;

        // Calculate decay percentage (in basis points)
        uint256 decayPercent = effectiveInactiveEpochs * decayRatePerEpoch;

        // Cap at maximum decay
        if (decayPercent > maxDecayPercent) {
            decayPercent = maxDecayPercent;
        }

        // Apply decay
        uint256 effectiveReputation = (base * (BASIS_POINTS - decayPercent)) /
            BASIS_POINTS;

        return effectiveReputation;
    }

    /**
     * @notice Record activity for a user (resets decay timer)
     * @param user The address to record activity for
     */
    function recordActivity(address user) external onlyOwner {
        lastActivityTimestamp[user] = block.timestamp;
        emit ActivityRecorded(user, block.timestamp);
    }

    /**
     * @notice Set base reputation for a user (also records activity)
     * @param user The address to set reputation for
     * @param amount The new base reputation amount
     */
    function setReputation(address user, uint256 amount) external onlyOwner {
        uint256 oldReputation = baseReputation[user];
        baseReputation[user] = amount;
        lastActivityTimestamp[user] = block.timestamp;

        emit ReputationUpdated(user, oldReputation, amount, block.timestamp);
        emit ActivityRecorded(user, block.timestamp);
    }

    /**
     * @notice Add to user's base reputation (also records activity)
     * @param user The address to add reputation to
     * @param amount The amount to add
     */
    function addReputation(address user, uint256 amount) external onlyOwner {
        uint256 oldReputation = baseReputation[user];
        uint256 newReputation = oldReputation + amount;
        baseReputation[user] = newReputation;
        lastActivityTimestamp[user] = block.timestamp;

        emit ReputationUpdated(
            user,
            oldReputation,
            newReputation,
            block.timestamp
        );
        emit ActivityRecorded(user, block.timestamp);
    }

    /**
     * @notice Deduct from user's base reputation
     * @param user The address to deduct reputation from
     * @param amount The amount to deduct
     */
    function deductReputation(address user, uint256 amount) external onlyOwner {
        uint256 oldReputation = baseReputation[user];
        uint256 newReputation = oldReputation > amount
            ? oldReputation - amount
            : 0;
        baseReputation[user] = newReputation;

        emit ReputationUpdated(
            user,
            oldReputation,
            newReputation,
            block.timestamp
        );
    }

    // ============ Merkle Root Functions ============

    /**
     * @notice Submit a Merkle root for reputation scores at a specific epoch
     * @dev Roots are immutable once committed. Prevents duplicate epoch submissions.
     * @param root The Merkle root of reputation scores
     * @param epoch The epoch number for this root
     */
    function submitReputationRoot(bytes32 root, uint256 epoch) external onlyOwner {
        // Validate root is not zero
        if (root == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Prevent duplicate epoch submissions
        if (epochCommitted[epoch]) {
            revert EpochAlreadyCommitted();
        }

        // Store the root and mark epoch as committed
        reputationRoots[epoch] = root;
        epochCommitted[epoch] = true;

        emit ReputationRootSubmitted(root, epoch, msg.sender, block.timestamp);
    }

    /**
     * @notice Check if an epoch has been committed
     * @param epoch The epoch number to check
     * @return committed True if a root exists for this epoch
     * @dev Note: reputationRoots mapping is public, so use reputationRoots(epoch) to get the root
     */
    function isEpochCommitted(uint256 epoch) external view returns (bool committed) {
        return epochCommitted[epoch];
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the decay rate per epoch
     * @param rate The new decay rate in basis points (e.g., 100 = 1%)
     */
    function setDecayRatePerEpoch(uint256 rate) external onlyOwner {
        if (rate > BASIS_POINTS) revert InvalidDecayRate();
        decayRatePerEpoch = rate;
        emit DecayParametersUpdated(
            rate,
            epochDuration,
            inactivityThreshold,
            maxDecayPercent
        );
    }

    /**
     * @notice Set the epoch duration
     * @param duration The new epoch duration in seconds
     */
    function setEpochDuration(uint256 duration) external onlyOwner {
        if (duration == 0) revert InvalidEpochDuration();
        epochDuration = duration;
        emit DecayParametersUpdated(
            decayRatePerEpoch,
            duration,
            inactivityThreshold,
            maxDecayPercent
        );
    }

    /**
     * @notice Set the inactivity threshold (grace period in epochs)
     * @param threshold The number of epochs before decay starts
     */
    function setInactivityThreshold(uint256 threshold) external onlyOwner {
        inactivityThreshold = threshold;
        emit DecayParametersUpdated(
            decayRatePerEpoch,
            epochDuration,
            threshold,
            maxDecayPercent
        );
    }

    /**
     * @notice Set the maximum decay percentage
     * @param maxDecay The maximum decay in basis points (e.g., 5000 = 50%)
     */
    function setMaxDecayPercent(uint256 maxDecay) external onlyOwner {
        if (maxDecay > BASIS_POINTS) revert InvalidMaxDecayPercent();
        maxDecayPercent = maxDecay;
        emit DecayParametersUpdated(
            decayRatePerEpoch,
            epochDuration,
            inactivityThreshold,
            maxDecay
        );
    }

    // ============ View Functions ============

    /**
     * @notice Get all decay parameters
     * @return rate The decay rate per epoch (basis points)
     * @return duration The epoch duration (seconds)
     * @return threshold The inactivity threshold (epochs)
     * @return maxDecay The maximum decay percentage (basis points)
     */
    function getDecayParameters()
        external
        view
        returns (
            uint256 rate,
            uint256 duration,
            uint256 threshold,
            uint256 maxDecay
        )
    {
        return (
            decayRatePerEpoch,
            epochDuration,
            inactivityThreshold,
            maxDecayPercent
        );
    }

    /**
     * @notice Calculate how much reputation a user would lose at current time
     * @param user The address to query
     * @return decayAmount The amount of reputation lost to decay
     */
    function getDecayAmount(
        address user
    ) external view returns (uint256 decayAmount) {
        uint256 base = baseReputation[user];
        uint256 effective = getEffectiveReputation(user);
        return base - effective;
    }

    /**
     * @notice Check if a user is currently experiencing decay
     * @param user The address to query
     * @return isDecaying True if the user's reputation is being reduced by decay
     */
    function isUserDecaying(
        address user
    ) external view returns (bool isDecaying) {
        return getEffectiveReputation(user) < baseReputation[user];
    }
}
