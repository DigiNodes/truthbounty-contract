/**
 * Ignition deployment module for FeeManager (SC-028)
 *
 * Usage:
 *   # Local hardhat network
 *   npx hardhat ignition deploy ignition/modules/FeeManager.ts
 *
 *   # Optimism Sepolia (testnet)
 *   npx hardhat ignition deploy ignition/modules/FeeManager.ts \
 *     --network optimismSepolia \
 *     --parameters ignition/parameters/fee_manager_sepolia.json
 *
 *   # Optimism Mainnet
 *   npx hardhat ignition deploy ignition/modules/FeeManager.ts \
 *     --network optimismMainnet \
 *     --parameters ignition/parameters/fee_manager_mainnet.json
 *
 * Required parameters (override via parameters JSON):
 *   feeToken_            - ERC20 fee token address
 *   initialAdmin         - Admin address
 *   governanceController - Governance controller address (address(0) to disable)
 *   treasuryReserve      - Treasury reserve recipient
 *   securityFund         - Security fund recipient
 *   ecosystemFund        - Ecosystem fund recipient
 *   contributorIncentives - Contributor incentives recipient
 *   emergencyReserve     - Emergency reserve recipient
 */

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const FeeManagerModule = buildModule("FeeManagerModule", (m) => {
    // ── Parameters ─────────────────────────────────────────────────────────────
    // These defaults are for local hardhat testing only.
    // Override via a parameters JSON file for real deployments.

    const feeToken            = m.getParameter<string>("feeToken_");
    const initialAdmin        = m.getParameter<string>("initialAdmin");
    const governanceController = m.getParameter<string>(
        "governanceController",
        "0x0000000000000000000000000000000000000000"
    );
    const treasuryReserve      = m.getParameter<string>("treasuryReserve");
    const securityFund         = m.getParameter<string>("securityFund");
    const ecosystemFund        = m.getParameter<string>("ecosystemFund");
    const contributorIncentives = m.getParameter<string>("contributorIncentives");
    const emergencyReserve     = m.getParameter<string>("emergencyReserve");

    // ── Deploy ─────────────────────────────────────────────────────────────────

    const feeManager = m.contract("FeeManager", [
        feeToken,
        initialAdmin,
        governanceController,
        treasuryReserve,
        securityFund,
        ecosystemFund,
        contributorIncentives,
        emergencyReserve,
    ]);

    return { feeManager };
});

export default FeeManagerModule;
