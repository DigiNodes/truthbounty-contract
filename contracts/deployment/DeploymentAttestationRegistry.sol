// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DeploymentAttestationRegistry
 * @notice Append-only, on-chain release metadata for the canonical protocol.
 * @dev The governance authority records an exact artifact and module-address
 *      manifest. The registry never overwrites a release, so indexers can
 *      reconcile a deployment without trusting an API or deployer database.
 */
contract DeploymentAttestationRegistry {
    uint256 public constant MAX_MODULES = 32;

    struct Attestation {
        bytes32 releaseId;
        uint256 chainId;
        bytes32 artifactDigest;
        uint64 configurationVersion;
        bytes32[] moduleIds;
        address[] moduleAddresses;
        address governanceAuthority;
        uint64 recordedAt;
    }

    address public immutable governanceAuthority;
    uint256 public attestationCount;

    mapping(bytes32 => Attestation) private _attestations;
    mapping(bytes32 => bool) public hasAttestation;

    error ZeroGovernanceAuthority();
    error Unauthorized(address caller);
    error InvalidReleaseId();
    error InvalidArtifactDigest();
    error InvalidChainId(uint256 expected, uint256 supplied);
    error InvalidConfigurationVersion();
    error ModuleArrayLengthMismatch();
    error TooManyModules(uint256 supplied, uint256 maximum);
    error ZeroModuleId(uint256 index);
    error ZeroModuleAddress(uint256 index);
    error AttestationAlreadyExists(bytes32 releaseId);

    event DeploymentAttested(
        bytes32 indexed releaseId,
        uint256 indexed chainId,
        bytes32 indexed artifactDigest,
        uint64 configurationVersion,
        bytes32[] moduleIds,
        address[] moduleAddresses,
        address governanceAuthority,
        uint64 recordedAt
    );

    constructor(address governanceAuthority_) {
        if (governanceAuthority_ == address(0)) revert ZeroGovernanceAuthority();
        governanceAuthority = governanceAuthority_;
    }

    /**
     * @notice Publish an immutable deployment manifest for this chain.
     * @dev Only the configured governance authority may attest. The supplied
     *      chain id must match the execution chain and every module entry must
     *      be non-zero. A release id can never be replaced.
     */
    function attestDeployment(
        bytes32 releaseId,
        uint256 chainId,
        bytes32 artifactDigest,
        uint64 configurationVersion,
        bytes32[] calldata moduleIds,
        address[] calldata moduleAddresses
    ) external {
        if (msg.sender != governanceAuthority) revert Unauthorized(msg.sender);
        if (releaseId == bytes32(0)) revert InvalidReleaseId();
        if (artifactDigest == bytes32(0)) revert InvalidArtifactDigest();
        if (chainId != block.chainid) revert InvalidChainId(block.chainid, chainId);
        if (configurationVersion == 0) revert InvalidConfigurationVersion();
        if (moduleIds.length != moduleAddresses.length) revert ModuleArrayLengthMismatch();
        if (moduleIds.length > MAX_MODULES) {
            revert TooManyModules(moduleIds.length, MAX_MODULES);
        }
        if (hasAttestation[releaseId]) revert AttestationAlreadyExists(releaseId);

        uint256 length = moduleIds.length;
        for (uint256 i; i < length; ++i) {
            if (moduleIds[i] == bytes32(0)) revert ZeroModuleId(i);
            if (moduleAddresses[i] == address(0)) revert ZeroModuleAddress(i);
        }

        Attestation storage attestation = _attestations[releaseId];
        attestation.releaseId = releaseId;
        attestation.chainId = chainId;
        attestation.artifactDigest = artifactDigest;
        attestation.configurationVersion = configurationVersion;
        attestation.governanceAuthority = governanceAuthority;
        attestation.recordedAt = uint64(block.timestamp);

        for (uint256 i; i < length; ++i) {
            attestation.moduleIds.push(moduleIds[i]);
            attestation.moduleAddresses.push(moduleAddresses[i]);
        }

        hasAttestation[releaseId] = true;
        ++attestationCount;

        emit DeploymentAttested(
            releaseId,
            chainId,
            artifactDigest,
            configurationVersion,
            moduleIds,
            moduleAddresses,
            governanceAuthority,
            attestation.recordedAt
        );
    }

    function getAttestation(bytes32 releaseId) external view returns (Attestation memory) {
        if (!hasAttestation[releaseId]) revert InvalidReleaseId();
        return _attestations[releaseId];
    }

    function getModuleCount(bytes32 releaseId) external view returns (uint256) {
        if (!hasAttestation[releaseId]) revert InvalidReleaseId();
        return _attestations[releaseId].moduleIds.length;
    }

    function getModule(bytes32 releaseId, uint256 index) external view returns (bytes32, address) {
        if (!hasAttestation[releaseId]) revert InvalidReleaseId();
        Attestation storage attestation = _attestations[releaseId];
        return (attestation.moduleIds[index], attestation.moduleAddresses[index]);
    }
}
