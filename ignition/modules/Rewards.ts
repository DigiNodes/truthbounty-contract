// WHAT THIS DEPLOYS:
//   TruthBountyClaims — Batched claim settlement contract
//
// DEPENDS ON:
//   TruthBountyModule (needs the token address)
//
// NOTE:
//   The contract in Rewards.sol is named "TruthBountyClaims".
//   This module deploys that contract.
//
// IMPORTANT POST-DEPLOY STEP:
//   After deployment, the owner must transfer BOUNTY tokens
//   to the TruthBountyClaims contract so it can pay out claims.
//   This is NOT automated because the amount depends on your
//   operational budget.
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import TruthBountyModule from "./TruthBounty";

const RewardsModule = buildModule("RewardsModule", (m) => {
  // ─────────────────────────────────────────────
  // 1. Import the token from TruthBountyModule
  // ─────────────────────────────────────────────
  const { token } = m.useModule(TruthBountyModule);

  // ─────────────────────────────────────────────
  // 2. Deploy TruthBountyClaims
  // ─────────────────────────────────────────────
  //
  // Constructor: constructor(address _tokenAddress)
  //
  const rewards = m.contract("TruthBountyClaims", [token]);

  return { rewards, token };
});

export default RewardsModule;