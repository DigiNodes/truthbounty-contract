// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

contract DeployBase is Script {
    struct DeploymentConfig {
        string environment;
        address admin;
        address governanceController;
        uint256 verificationWindowDuration;
        uint256 minStakeAmount;
        uint256 settlementThresholdPercent;
        uint256 rewardPercent;
        uint256 slashPercent;
        uint256 confirmationDelay;
        uint256 minReputationScore;
        uint256 maxReputationScore;
        uint256 defaultReputationScore;
        uint256 stakingLockDuration;
    }

    DeploymentConfig public config;
    string public deployEnv;

    function loadConfig(string memory env) internal {
        deployEnv = env;

        if (keccak256(bytes(env)) == keccak256(bytes("local"))) {
            config = DeploymentConfig({
                environment: "local",
                admin: vm.envAddress("DEPLOYER_ADDRESS"),
                governanceController: address(0),
                verificationWindowDuration: 7 days,
                minStakeAmount: 100 ether,
                settlementThresholdPercent: 60,
                rewardPercent: 80,
                slashPercent: 20,
                confirmationDelay: 1 hours,
                minReputationScore: 0.1 ether,
                maxReputationScore: 10 ether,
                defaultReputationScore: 1 ether,
                stakingLockDuration: 1 days
            });
        } else if (keccak256(bytes(env)) == keccak256(bytes("testnet"))) {
            config = DeploymentConfig({
                environment: "testnet",
                admin: vm.envAddress("ADMIN_ADDRESS"),
                governanceController: vm.envOr("GOVERNANCE_CONTROLLER", address(0)),
                verificationWindowDuration: vm.envOr("VERIFICATION_WINDOW", uint256(7 days)),
                minStakeAmount: vm.envOr("MIN_STAKE", uint256(100 ether)),
                settlementThresholdPercent: 60,
                rewardPercent: 80,
                slashPercent: 20,
                confirmationDelay: 1 hours,
                minReputationScore: 0.1 ether,
                maxReputationScore: 10 ether,
                defaultReputationScore: 1 ether,
                stakingLockDuration: vm.envOr("STAKING_LOCK_DURATION", uint256(7 days))
            });
        } else if (keccak256(bytes(env)) == keccak256(bytes("mainnet"))) {
            config = DeploymentConfig({
                environment: "mainnet",
                admin: vm.envAddress("ADMIN_ADDRESS"),
                governanceController: vm.envOr("GOVERNANCE_CONTROLLER", address(0)),
                verificationWindowDuration: vm.envOr("VERIFICATION_WINDOW", uint256(7 days)),
                minStakeAmount: vm.envOr("MIN_STAKE", uint256(100 ether)),
                settlementThresholdPercent: 60,
                rewardPercent: 80,
                slashPercent: 20,
                confirmationDelay: 1 hours,
                minReputationScore: 0.1 ether,
                maxReputationScore: 10 ether,
                defaultReputationScore: 1 ether,
                stakingLockDuration: vm.envOr("STAKING_LOCK_DURATION", uint256(30 days))
            });
        } else {
            revert(string(abi.encodePacked("Unknown environment: ", env)));
        }
    }

    function saveDeployment(string memory artifactName, string memory content) internal {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployments/", deployEnv, "/", artifactName));
        vm.writeFile(path, content);
        console2.log("Saved artifact:", path);
    }

    function generateManifest(
        string memory version,
        address migrationManager,
        address token,
        address oracle,
        address bounty,
        address staking,
        address slashing,
        address claims
    ) internal view returns (string memory) {
        return generateManifestWithGovernance(
            version,
            migrationManager,
            token,
            oracle,
            bounty,
            staking,
            slashing,
            claims,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function generateManifestWithGovernance(
        string memory version,
        address migrationManager,
        address token,
        address oracle,
        address bounty,
        address staking,
        address slashing,
        address claims,
        address governanceToken,
        address timelock,
        address governor,
        address moduleRegistry,
        address governanceGuardian
    ) internal view returns (string memory) {
        return string(abi.encodePacked(
            '{\n',
            '  "protocolVersion": "', version, '",\n',
            '  "environment": "', deployEnv, '",\n',
            '  "deployTimestamp": ', vm.toString(block.timestamp), ',\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "gitCommit": "', vm.envOr("GIT_COMMIT", string("unknown")), '",\n',
            '  "contracts": {\n',
            '    "MigrationManager": "', vm.toString(migrationManager), '",\n',
            '    "TruthBountyToken": "', vm.toString(token), '",\n',
            '    "ReputationOracle": "', vm.toString(oracle), '",\n',
            '    "TruthBountyWeighted": "', vm.toString(bounty), '",\n',
            '    "Staking": "', vm.toString(staking), '",\n',
            '    "VerifierSlashing": "', vm.toString(slashing), '",\n',
            '    "TruthBountyClaims": "', vm.toString(claims), '",\n',
            '    "TruthBountyGovernanceToken": "', vm.toString(governanceToken), '",\n',
            '    "TimelockController": "', vm.toString(timelock), '",\n',
            '    "TruthBountyGovernor": "', vm.toString(governor), '",\n',
            '    "GovernedModuleRegistry": "', vm.toString(moduleRegistry), '",\n',
            '    "GovernanceGuardian": "', vm.toString(governanceGuardian), '"\n',
            '  },\n',
            '  "governance": {\n',
            '    "votingDelay": ', vm.envOr("GOV_VOTING_DELAY", uint256(86400)), ',\n',
            '    "votingPeriod": ', vm.envOr("GOV_VOTING_PERIOD", uint256(259200)), ',\n',
            '    "proposalThreshold": "', vm.toString(vm.envOr("GOV_PROPOSAL_THRESHOLD", uint256(100_000 ether))), '",\n',
            '    "quorumNumerator": ', vm.envOr("GOV_QUORUM_NUMERATOR", uint256(4)), ',\n',
            '    "timelockMinDelay": ', vm.envOr("TIMELOCK_MIN_DELAY", uint256(172800)), '\n',
            '  }\n',
            '}'
        ));
    }
}