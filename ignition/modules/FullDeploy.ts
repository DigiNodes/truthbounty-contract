// WHAT THIS DOES:
//   Deploys the ENTIRE system in one command:
//     1. TruthBountyToken
//     2. TruthBounty (+ wires settlement permission)
//     3. Staking
//     4. TruthBountyClaims (Rewards)
//
// USAGE:
//   npx hardhat ignition deploy ignition/modules/FullDeploy.ts --network optimism_sepolia
//
// WHY THIS EXISTS:
//   Individual modules are good for upgrading one contract.
//   This is good for fresh deployments where you want everything at once.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import TruthBountyModule from "./TruthBounty";
import StakingModule from "./Staking";
import RewardsModule from "./Rewards";

const FullDeployModule = buildModule("FullDeployModule", (m) => {
  // Each useModule call reuses shared dependencies (the token).
  // TruthBountyModule deploys once, Staking and Rewards reference it.
  const { token, truthBounty } = m.useModule(TruthBountyModule);
  const { staking } = m.useModule(StakingModule);
  const { rewards } = m.useModule(RewardsModule);

  return { token, truthBounty, staking, rewards };
});

export default FullDeployModule;