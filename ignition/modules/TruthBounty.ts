// ignition/modules/TruthBounty.ts
//
// WHAT THIS DEPLOYS:
//   1. TruthBountyToken  — The ERC20 token (no constructor args)
//   2. TruthBounty       — The main claim/vote/settlement contract
//
// DEPLOYMENT ORDER:
//   Token first → then TruthBounty (needs token address)
//   → then wires them: token.setSettlementContract(truthBounty)
//
// WHY BOTH IN ONE MODULE:
//   They're in the same .sol file and tightly coupled.
//   TruthBounty is useless without the token, and the token
//   needs TruthBounty's address for the settlement permission.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TruthBountyModule = buildModule("TruthBountyModule", (m) => {
  // ─────────────────────────────────────────────
  // 1. Deploy the ERC20 token
  // ─────────────────────────────────────────────
  //
  // Constructor: constructor() ERC20("TruthBounty", "BOUNTY") Ownable(msg.sender)
  // - No arguments needed
  // - Mints 10,000,000 BOUNTY to the deployer
  //
  const token = m.contract("TruthBountyToken", []);

  // ─────────────────────────────────────────────
  // 2. Deploy the main TruthBounty contract
  // ─────────────────────────────────────────────
  //
  // Constructor: constructor(address _bountyToken)
  // - Needs the token address
  // - Sets deployer as owner
  //
  const truthBounty = m.contract("TruthBounty", [token], {
    // Hardhat Ignition automatically waits for `token` to be
    // deployed before deploying this. The dependency is implicit
    // from passing `token` as a constructor arg.
  });

  // ─────────────────────────────────────────────
  // 3. Post-deploy wiring
  // ─────────────────────────────────────────────
  //
  // token.setSettlementContract(truthBounty.address)
  //
  // This gives TruthBounty permission to call slashVerifier()
  // on the token contract.
  //
  m.call(token, "setSettlementContract", [truthBounty], {
    id: "wire_settlement_contract",
  });

  return { token, truthBounty };
});

export default TruthBountyModule;
