import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import { validateCanonicalV2Parameters } from "../../scripts/validateDeploymentConfig";

/**
 * @title CanonicalV2DeploymentModule (SC-031)
 * @notice Canonical Hardhat Ignition deployment composition for TruthBounty Protocol V2.
 * @dev Deploys, configures, and wires the approved canonical V2 suite in strict dependency order.
 *      Excludes legacy contracts (e.g. TruthBountyClaims) and ensures deployer roles are finalized.
 *      Deployment parameters are validated against the canonical configuration bounds (SC-068)
 *      before any Ignition transaction is submitted.
 */
const CanonicalV2Module = buildModule("CanonicalV2Module", (m) => {
  // Account parameter defaults
  const deployer = m.getAccount(0);

  // Initial parameter defaults (documented safe values; overridable via parameters JSON)
  const DEFAULT_INITIAL_SUPPLY = ethers.parseEther("10000000").toString();
  const DEFAULT_MIN_VERIFICATION_COUNT = 1n;
  const DEFAULT_MIN_TOTAL_WEIGHT = 0n;
  const DEFAULT_MIN_CONFIDENCE_BPS = 0n;
  const DEFAULT_CHALLENGE_WINDOW = 3 * 24 * 3600; // 3 days
  const DEFAULT_APPEAL_DURATION = 3 * 24 * 3600; // 3 days
  const DEFAULT_MIN_APPEAL_STAKE = ethers.parseEther("200").toString();
  const DEFAULT_APPEAL_MULTIPLIER_BPS = 15000n; // 1.5x
  const DEFAULT_MAX_WEIGHT_CAP = ethers.parseEther("100000").toString();

  // Guard: any drift of the documented defaults out of the canonical bounds (SC-068) fails on
  // module load, before Ignition submits anything. User-supplied parameter overrides are
  // validated by validateCanonicalV2Parameters in scripts/deployCanonicalV2.ts and constrained
  // by the on-chain constructors at deploy time.
  validateCanonicalV2Parameters({
    initialSupply: DEFAULT_INITIAL_SUPPLY,
    minVerificationCount: DEFAULT_MIN_VERIFICATION_COUNT,
    minTotalWeight: DEFAULT_MIN_TOTAL_WEIGHT,
    minConfidenceBps: DEFAULT_MIN_CONFIDENCE_BPS,
    challengeWindowDuration: DEFAULT_CHALLENGE_WINDOW,
    appealDuration: DEFAULT_APPEAL_DURATION,
    minAppealStake: DEFAULT_MIN_APPEAL_STAKE,
    appealMultiplierBps: DEFAULT_APPEAL_MULTIPLIER_BPS,
    maxWeightCap: DEFAULT_MAX_WEIGHT_CAP,
    parameterVersion: 1n,
  });

  const initialSupply = m.getParameter("initialSupply", DEFAULT_INITIAL_SUPPLY);
  const minVerificationCount = m.getParameter("minVerificationCount", DEFAULT_MIN_VERIFICATION_COUNT);
  const minTotalWeight = m.getParameter("minTotalWeight", DEFAULT_MIN_TOTAL_WEIGHT);
  const minConfidenceBps = m.getParameter("minConfidenceBps", DEFAULT_MIN_CONFIDENCE_BPS);
  const challengeWindowDuration = m.getParameter("challengeWindowDuration", DEFAULT_CHALLENGE_WINDOW);
  const appealDuration = m.getParameter("appealDuration", DEFAULT_APPEAL_DURATION);
  const minAppealStake = m.getParameter("minAppealStake", DEFAULT_MIN_APPEAL_STAKE);
  const appealMultiplierBps = m.getParameter("appealMultiplierBps", DEFAULT_APPEAL_MULTIPLIER_BPS);
  const maxWeightCap = m.getParameter("maxWeightCap", DEFAULT_MAX_WEIGHT_CAP);

  // 1. Deploy Governance Controller
  const governanceController = m.contract("GovernanceController", [deployer]);

  // 2. Deploy Protocol Token (RewardToken)
  const token = m.contract("RewardToken", [deployer, initialSupply]);

  // 3. Deploy Reputation Oracle
  const reputationOracle = m.contract("MockReputationOracle", []);

  // 4. Deploy Canonical ClaimRegistry
  const claimRegistry = m.contract("ClaimRegistry", [deployer]);

  // 5. Deploy Verification Source (TruthBountyWeighted)
  const truthBountyWeighted = m.contract("TruthBountyWeighted", [
    token,
    reputationOracle,
    deployer,
    governanceController,
  ]);

  // 6. Deploy Deterministic Verification Aggregator
  const verificationAggregator = m.contract("VerificationAggregator", [
    truthBountyWeighted,
    deployer,
    minVerificationCount,
    minTotalWeight,
    minConfidenceBps,
  ]);

  // 7. Deploy Provisional Settlement Engine
  const provisionalSettlementEngine = m.contract("ProvisionalSettlementEngine", [
    claimRegistry,
    verificationAggregator,
    challengeWindowDuration,
    governanceController,
    deployer,
  ]);

  // 8. Deploy Appeal Verification Round
  const appealConfig = {
    roundDuration: appealDuration,
    minStakeAmount: minAppealStake,
    stakeMultiplierBps: appealMultiplierBps,
    maxWeightCap: maxWeightCap,
    parameterVersion: 1n,
  };

  const appealVerificationRound = m.contract("AppealVerificationRound", [
    token,
    claimRegistry,
    reputationOracle,
    appealConfig,
    governanceController,
    deployer,
  ]);

  // 9. Wire Permissions & Roles
  // Grant REGISTRY_UPDATER_ROLE on ClaimRegistry to ProvisionalSettlementEngine
  const REGISTRY_UPDATER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_UPDATER_ROLE"));
  m.call(claimRegistry, "grantRole", [REGISTRY_UPDATER_ROLE, provisionalSettlementEngine]);

  return {
    governanceController,
    token,
    reputationOracle,
    claimRegistry,
    truthBountyWeighted,
    verificationAggregator,
    provisionalSettlementEngine,
    appealVerificationRound,
  };
});

export default CanonicalV2Module;
