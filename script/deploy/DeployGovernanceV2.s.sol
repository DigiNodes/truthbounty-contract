// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernedModuleRegistry} from "../../contracts/governance/v2/GovernedModuleRegistry.sol";
import {TruthBountyGovernanceToken} from "../../contracts/governance/v2/TruthBountyGovernanceToken.sol";
import {TruthBountyGovernor} from "../../contracts/governance/v2/TruthBountyGovernor.sol";
import {GovernanceGuardian} from "../../contracts/governance/v2/GovernanceGuardian.sol";
import {GovernanceRoleTopology} from "../../contracts/governance/v2/GovernanceRoleTopology.sol";

/**
 * @title DeployGovernanceV2
 * @notice Deploys V2 governor, timelock, governance token, module registry, and guardian.
 */
contract DeployGovernanceV2 is Script {
    struct GovernanceConfig {
        address admin;
        address guardian;
        uint256 timelockMinDelay;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
        uint256 tokenSupply;
    }

    function run() external {
        GovernanceConfig memory cfg = GovernanceConfig({
            admin: vm.envAddress("ADMIN_ADDRESS"),
            guardian: vm.envAddress("GUARDIAN_ADDRESS"),
            timelockMinDelay: vm.envOr("TIMELOCK_MIN_DELAY", uint256(2 days)),
            votingDelay: uint48(vm.envOr("GOV_VOTING_DELAY", uint256(1 days))),
            votingPeriod: uint32(vm.envOr("GOV_VOTING_PERIOD", uint256(3 days))),
            proposalThreshold: vm.envOr("GOV_PROPOSAL_THRESHOLD", uint256(100_000 ether)),
            quorumNumerator: vm.envOr("GOV_QUORUM_NUMERATOR", uint256(4)),
            tokenSupply: vm.envOr("GOV_TOKEN_SUPPLY", uint256(1_000_000_000 ether))
        });

        vm.startBroadcast(cfg.admin);

        GovernedModuleRegistry registry = new GovernedModuleRegistry(cfg.admin);
        TruthBountyGovernanceToken token = new TruthBountyGovernanceToken(cfg.admin, cfg.tokenSupply);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(cfg.timelockMinDelay, proposers, executors, cfg.admin);

        TruthBountyGovernor governor = new TruthBountyGovernor(
            token,
            timelock,
            registry,
            cfg.guardian,
            cfg.votingDelay,
            cfg.votingPeriod,
            cfg.proposalThreshold,
            cfg.quorumNumerator
        );

        GovernanceGuardian guardianContract = new GovernanceGuardian(cfg.admin, cfg.guardian, governor);

        GovernanceRoleTopology.configure(timelock, governor, cfg.guardian, cfg.timelockMinDelay);
        GovernanceRoleTopology.finalizeTimelockAdmin(timelock, cfg.admin);

        timelock.grantRole(registry.REGISTRY_ADMIN_ROLE(), address(timelock));

        governor.publishManifest();

        vm.stopBroadcast();

        console2.log("GovernedModuleRegistry", address(registry));
        console2.log("TruthBountyGovernanceToken", address(token));
        console2.log("TimelockController", address(timelock));
        console2.log("TruthBountyGovernor", address(governor));
        console2.log("GovernanceGuardian", address(guardianContract));
    }
}
