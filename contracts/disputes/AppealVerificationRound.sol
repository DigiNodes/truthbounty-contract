// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../governance/GovernanceOwnable.sol";
import "../governance/GovernanceHooks.sol";
import "../interfaces/IClaimRegistry.sol";
import "../interfaces/IAppealVerificationRound.sol";
import "../IReputationOracle.sol";

/**
 * @title AppealVerificationRound
 * @notice Canonical implementation of TruthBounty V2 Appeal Verification Round Manager (SC-017).
 * @dev Isolates second-round appeal voting from first-round state while enforcing frozen higher
 *      participation parameters and implementing IVerificationSource for downstream aggregation.
 *
 * Invariants:
 *  1. Single Appeal: Every disputed claim can open at most one appeal round.
 *  2. Isolated Storage: Appeal votes do not mutate or overwrite first-round voting state.
 *  3. Immutable Parameters: Round duration, min stake, multiplier, and weight caps freeze at open.
 *  4. One Address One Position: Verifiers may cast exactly one vote per appeal round.
 *  5. Aggregation Ready: Implements IVerificationSource for direct consumption by VerificationAggregator.
 */
contract AppealVerificationRound is
    IAppealVerificationRound,
    AccessControl,
    ReentrancyGuard,
    Pausable,
    GovernanceOwnable
{
    using SafeERC20 for IERC20;

    // =========================================================================
    // Roles & Constants
    // =========================================================================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DISPUTE_ROUTER_ROLE = keccak256("DISPUTE_ROUTER_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_APPEAL_DURATION = 1 hours;
    uint256 public constant MAX_APPEAL_DURATION = 30 days;

    // =========================================================================
    // Errors
    // =========================================================================

    error ZeroClaimId();
    error InvalidDuration(uint256 duration);
    error InvalidMinStake();
    error InvalidMultiplier();
    error ClaimDoesNotExist(uint256 claimId);
    error AppealRoundAlreadyExists(uint256 claimId);
    error AppealRoundNotOpen(uint256 claimId);
    error AppealRoundExpired(uint256 claimId, uint256 currentTimestamp, uint256 deadline);
    error AppealRoundNotExpired(uint256 claimId, uint256 currentTimestamp, uint256 deadline);
    error InsufficientStake(uint256 provided, uint256 requiredStake);
    error AlreadyVotedInAppeal(uint256 claimId, address verifier);
    error IndexOutOfBounds();

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice The ERC20 token used for appeal staking.
    IERC20 public immutable stakingToken;

    /// @notice Canonical Claim Registry contract.
    IClaimRegistry public immutable claimRegistry;

    /// @notice Reputation oracle providing verifier weights.
    IReputationOracle public reputationOracle;

    /// @notice Default configuration applied to new appeal rounds.
    AppealRoundConfig public defaultConfig;

    /// @notice Mapping from claimId to its isolated appeal round.
    mapping(uint256 => AppealRound) private _rounds;

    /// @notice Mapping from claimId to verifier address to appeal vote record.
    mapping(uint256 => mapping(address => AppealVote)) private _votes;

    /// @notice List of verifier addresses that participated in an appeal round.
    mapping(uint256 => address[]) private _roundVoters;

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        address _stakingToken,
        address _claimRegistry,
        address _reputationOracle,
        AppealRoundConfig memory _initialConfig,
        address _governanceController,
        address _initialAdmin
    ) {
        if (_stakingToken == address(0)) revert ZeroAddress();
        if (_claimRegistry == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();
        if (_initialConfig.roundDuration < MIN_APPEAL_DURATION || _initialConfig.roundDuration > MAX_APPEAL_DURATION) {
            revert InvalidDuration(_initialConfig.roundDuration);
        }
        if (_initialConfig.minStakeAmount == 0) revert InvalidMinStake();
        if (_initialConfig.stakeMultiplierBps == 0) revert InvalidMultiplier();

        stakingToken = IERC20(_stakingToken);
        claimRegistry = IClaimRegistry(_claimRegistry);
        reputationOracle = IReputationOracle(_reputationOracle);
        defaultConfig = _initialConfig;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(DISPUTE_ROUTER_ROLE, _initialAdmin);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(DISPUTE_ROUTER_ROLE, ADMIN_ROLE);

        _initializeGovernance(_governanceController, _initialAdmin, _initialAdmin);
    }

    // =========================================================================
    // External Round Management
    // =========================================================================

    /**
     * @inheritdoc IAppealVerificationRound
     */
    function openAppealRound(uint256 claimId) external override whenNotPaused {
        if (claimId == 0) revert ZeroClaimId();
        if (_rounds[claimId].status != AppealRoundStatus.NONE) revert AppealRoundAlreadyExists(claimId);

        IClaimRegistry.Claim memory claim = claimRegistry.getClaim(claimId);
        if (claim.creator == address(0)) revert ClaimDoesNotExist(claimId);

        AppealRoundConfig memory cfg = defaultConfig;
        uint256 deadline = block.timestamp + cfg.roundDuration;

        _rounds[claimId] = AppealRound({
            claimId: claimId,
            status: AppealRoundStatus.OPEN,
            openedAt: block.timestamp,
            deadline: deadline,
            minStakeAmount: cfg.minStakeAmount,
            stakeMultiplierBps: cfg.stakeMultiplierBps,
            maxWeightCap: cfg.maxWeightCap,
            totalTrueStake: 0,
            totalFalseStake: 0,
            totalTrueWeight: 0,
            totalFalseWeight: 0,
            verifierCount: 0
        });

        emit AppealRoundOpened(
            claimId,
            deadline,
            cfg.minStakeAmount,
            cfg.stakeMultiplierBps,
            msg.sender
        );
    }

    /**
     * @inheritdoc IAppealVerificationRound
     */
    function submitAppealVote(
        uint256 claimId,
        bool support,
        uint256 stakeAmount
    ) external override nonReentrant whenNotPaused {
        if (claimId == 0) revert ZeroClaimId();
        AppealRound storage round = _rounds[claimId];

        if (round.status != AppealRoundStatus.OPEN) revert AppealRoundNotOpen(claimId);
        if (block.timestamp >= round.deadline) revert AppealRoundExpired(claimId, block.timestamp, round.deadline);
        if (stakeAmount < round.minStakeAmount) revert InsufficientStake(stakeAmount, round.minStakeAmount);

        AppealVote storage existingVote = _votes[claimId][msg.sender];
        if (existingVote.voted) revert AlreadyVotedInAppeal(claimId, msg.sender);

        // Calculate reputation weight multiplier
        uint256 reputationScore = 1e18; // baseline 1.0
        if (address(reputationOracle) != address(0)) {
            try reputationOracle.getReputationScore(msg.sender) returns (uint256 score) {
                if (score > 0) reputationScore = score;
            } catch {}
        }

        // effectiveWeight = (stakeAmount * reputationScore / 1e18) * stakeMultiplierBps / 10000
        uint256 baseWeighted = (stakeAmount * reputationScore) / 1e18;
        uint256 effectiveWeight = (baseWeighted * round.stakeMultiplierBps) / BPS_DENOMINATOR;

        if (round.maxWeightCap > 0 && effectiveWeight > round.maxWeightCap) {
            effectiveWeight = round.maxWeightCap;
        }

        // Custody stake tokens into contract
        stakingToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // Record vote
        _votes[claimId][msg.sender] = AppealVote({
            voted: true,
            support: support,
            stakeAmount: stakeAmount,
            effectiveStake: effectiveWeight,
            timestamp: block.timestamp
        });

        _roundVoters[claimId].push(msg.sender);
        round.verifierCount++;

        if (support) {
            round.totalTrueStake += stakeAmount;
            round.totalTrueWeight += effectiveWeight;
        } else {
            round.totalFalseStake += stakeAmount;
            round.totalFalseWeight += effectiveWeight;
        }

        emit AppealVoteSubmitted(claimId, msg.sender, support, stakeAmount, effectiveWeight);
    }

    /**
     * @inheritdoc IAppealVerificationRound
     */
    function closeAppealRound(uint256 claimId) external override nonReentrant whenNotPaused {
        if (claimId == 0) revert ZeroClaimId();
        AppealRound storage round = _rounds[claimId];

        if (round.status != AppealRoundStatus.OPEN) revert AppealRoundNotOpen(claimId);
        if (block.timestamp < round.deadline) revert AppealRoundNotExpired(claimId, block.timestamp, round.deadline);

        round.status = AppealRoundStatus.CLOSED;

        emit AppealRoundClosed(
            claimId,
            round.totalTrueWeight,
            round.totalFalseWeight,
            round.verifierCount,
            msg.sender
        );
    }

    // =========================================================================
    // IVerificationSource Implementation (for VerificationAggregator compatibility)
    // =========================================================================

    function getClaimVoterCount(uint256 claimId) external view override returns (uint256) {
        return _roundVoters[claimId].length;
    }

    function getClaimVoterAt(uint256 claimId, uint256 index) external view override returns (address) {
        if (index >= _roundVoters[claimId].length) revert IndexOutOfBounds();
        return _roundVoters[claimId][index];
    }

    function getVoteData(uint256 claimId, address verifier)
        external
        view
        override
        returns (bool voted, bool support, uint256 effectiveStake)
    {
        AppealVote storage v = _votes[claimId][verifier];
        return (v.voted, v.support, v.effectiveStake);
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    function getAppealRound(uint256 claimId) external view override returns (AppealRound memory) {
        return _rounds[claimId];
    }

    function getAppealVote(uint256 claimId, address verifier) external view override returns (AppealVote memory) {
        return _votes[claimId][verifier];
    }

    function isAppealOpen(uint256 claimId) external view override returns (bool) {
        AppealRound storage round = _rounds[claimId];
        return (round.status == AppealRoundStatus.OPEN && block.timestamp < round.deadline);
    }

    // =========================================================================
    // Governance Controls
    // =========================================================================

    function setDefaultConfig(AppealRoundConfig calldata newConfig) external onlyGovernanceOrAdmin {
        if (newConfig.roundDuration < MIN_APPEAL_DURATION || newConfig.roundDuration > MAX_APPEAL_DURATION) {
            revert InvalidDuration(newConfig.roundDuration);
        }
        if (newConfig.minStakeAmount == 0) revert InvalidMinStake();
        if (newConfig.stakeMultiplierBps == 0) revert InvalidMultiplier();

        defaultConfig = newConfig;

        emit DefaultAppealConfigUpdated(
            newConfig.roundDuration,
            newConfig.minStakeAmount,
            newConfig.stakeMultiplierBps,
            newConfig.maxWeightCap
        );
    }

    function setReputationOracle(address newOracle) external onlyGovernanceOrAdmin {
        reputationOracle = IReputationOracle(newOracle);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
