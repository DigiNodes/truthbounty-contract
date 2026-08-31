import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * @title CanonicalV2DeploymentModule (SC-031)
 * @notice Canonical Hardhat Ignition deployment composition for TruthBounty Protocol V2.
 * @dev Deploys, configures, and wires the approved canonical V2 suite in strict dependency order.
 *      Excludes legacy contracts (e.g. TruthBountyClaims) and ensures deployer roles are finalized.
 */
const CanonicalV2Module = buildModule("CanonicalV2Module", (m) => {
  // Account parameter defaults
  const deployer = m.getAccount(0);

  // Initial parameters
  const initialSupply = m.getParameter("initialSupply", ethers.parseEther("10000000").toString());
  const minVerificationCount = m.getParameter("minVerificationCount", 1n);
  const minTotalWeight = m.getParameter("minTotalWeight", 0n);
  const minConfidenceBps = m.getParameter("minConfidenceBps", 0n);
  const challengeWindowDuration = m.getParameter("challengeWindowDuration", 3 * 24 * 3600); // 3 days
  const appealDuration = m.getParameter("appealDuration", 3 * 24 * 3600); // 3 days
  const minAppealStake = m.getParameter("minAppealStake", ethers.parseEther("200").toString());
  const appealMultiplierBps = m.getParameter("appealMultiplierBps", 15000n); // 1.5x
  const maxWeightCap = m.getParameter("maxWeightCap", ethers.parseEther("100000").toString());

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
