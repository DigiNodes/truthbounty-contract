// WHAT THIS DEPLOYS:
//   Staking — Lock tokens for a configurable duration
//
// DEPENDS ON:
//   TruthBountyModule (needs the token address)
//
// CONFIGURABLE PARAMETERS:
//   lockDuration — How long stakes are locked (default: 1 day = 86400 seconds)
//
// USAGE:
//   # Deploy with default 1-day lock:
//   npx hardhat ignition deploy ignition/modules/Staking.ts --network optimism_sepolia
//
//   # Deploy with custom lock (e.g., 7 days):
//   npx hardhat ignition deploy ignition/modules/Staking.ts --network optimism_sepolia \
//     --parameters '{"StakingModule": {"lockDuration": 604800}}'

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import TruthBountyModule from "./TruthBounty";

const StakingModule = buildModule("StakingModule", (m) => {
  // ─────────────────────────────────────────────
  // 1. Import the token from TruthBountyModule
  // ─────────────────────────────────────────────
  //
  // m.useModule() reuses the TruthBountyModule deployment.
  // If TruthBountyModule was already deployed, it reads the
  // existing addresses. If not, it deploys it first.
  //
  const { token } = m.useModule(TruthBountyModule);

  // ─────────────────────────────────────────────
  // 2. Configurable parameters
  // ─────────────────────────────────────────────
  //
  // lockDuration: How long tokens are locked after staking.
  // Default: 86400 seconds = 1 day
  // Override via --parameters flag or parameters file.
  //
  const lockDuration = m.getParameter("lockDuration", 86_400);

  // ─────────────────────────────────────────────
  // 3. Deploy Staking contract
  // ─────────────────────────────────────────────
  //
  // Constructor: constructor(address _stakingToken, uint256 _initialLockDuration)
  //
  const staking = m.contract("Staking", [token, lockDuration]);

  return { staking, token };
});

export default StakingModule;