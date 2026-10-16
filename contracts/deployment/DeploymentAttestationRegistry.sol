// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DeploymentAttestationRegistry
 * @notice Append-only, on-chain release metadata for the canonical protocol.
 *
 * @dev The governance authority records an exact artifact and module-address
 *      manifest. Once recorded, a release can never be overwritten or deleted.
 *
 *      The registry allows indexers and other contracts to independently
 *      verify deployment metadata without trusting an off-chain API or
 *      deployer database.
 */
contract DeploymentAttestationRegistry {
    uint256 public constant MAX_MODULES = 32;
    uint256 public constant MAX_RELEASE_ID_LENGTH = 64;
    bytes32 public constant DEPLOYMENT_DOMAIN = keccak256("truthbounty.deployment.v2");

    struct Attestation {
        bytes32 releaseId;
        uint256 chainId;
        bytes32 artifactDigest;
        uint64 configurationVersion;
        bytes32[] moduleIds;
        address[] moduleAddresses;
        uint64 recordedAt;
    }

    /// @notice Address authorized to publish deployment attestations.
    address public immutable governanceAuthority;

    /// @notice Address of the deployer that must be revoked after role transfer.
    address public immutable deployer;

    /// @notice Number of attestations successfully recorded.
    uint256 public attestationCount;

    mapping(bytes32 => Attestation) private _attestations;
    mapping(bytes32 => bool) public hasAttestation;
    mapping(address => bool) public revokedDeployers;

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
    error DuplicateModuleId(bytes32 moduleId);
    error AttestationAlreadyExists(bytes32 releaseId);
    error ModuleIndexOutOfBounds(
        bytes32 releaseId,
        uint256 index,
        uint256 length
    );
    error ZeroDeployer();
    error DeployerAlreadyRevoked(address deployer);
    error DeployerStillAuthorized(address deployer);
    error InvalidReleaseIdLength(uint256 supplied, uint256 maximum);

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

    event DeployerRevoked(address indexed deployer, address indexed governanceAuthority, uint64 revokedAt);

    constructor(address governanceAuthority_, address deployer_) {
        if (governanceAuthority_ == address(0)) {
            revert ZeroGovernanceAuthority();
        }

        if (deployer_ == address(0)) {
            revert ZeroDeployer();
        }

        governanceAuthority = governanceAuthority_;
        deployer = deployer_;
    }

    /**
     * @notice Publish an immutable deployment manifest for this chain.
     *
     * @dev Only the configured governance authority may attest.
     *
     *      The supplied chain ID must match the execution chain.
     *      Every module ID and address must be non-zero.
     *      Module IDs must be unique within the release.
     *      A release ID can never be replaced.
     */
    function attestDeployment(
        bytes32 releaseId,
        uint256 chainId,
        bytes32 artifactDigest,
        uint64 configurationVersion,
        bytes32[] calldata moduleIds,
        address[] calldata moduleAddresses
    ) external {
        if (msg.sender != governanceAuthority) {
            revert Unauthorized(msg.sender);
        }

        if (revokedDeployers[msg.sender]) {
            revert Unauthorized(msg.sender);
        }

        if (releaseId == bytes32(0)) {
            revert InvalidReleaseId();
        }

        if (artifactDigest == bytes32(0)) {
            revert InvalidArtifactDigest();
        }

        if (_releaseIdLength(releaseId) > MAX_RELEASE_ID_LENGTH) {
            revert InvalidReleaseIdLength(_releaseIdLength(releaseId), MAX_RELEASE_ID_LENGTH);
        }

        if (chainId != block.chainid) {
            revert InvalidChainId(block.chainid, chainId);
        }

        if (configurationVersion == 0) {
            revert InvalidConfigurationVersion();
        }

        if (moduleIds.length != moduleAddresses.length) {
            revert ModuleArrayLengthMismatch();
        }

        if (moduleIds.length > MAX_MODULES) {
            revert TooManyModules(moduleIds.length, MAX_MODULES);
        }

        if (hasAttestation[releaseId]) {
            revert AttestationAlreadyExists(releaseId);
        }

        uint256 length = moduleIds.length;

        for (uint256 i; i < length; ++i) {
            bytes32 moduleId = moduleIds[i];

            if (moduleId == bytes32(0)) {
                revert ZeroModuleId(i);
            }

            if (moduleAddresses[i] == address(0)) {
                revert ZeroModuleAddress(i);
            }

            // Prevent duplicate module IDs within the same deployment.
            for (uint256 j; j < i; ++j) {
                if (moduleIds[j] == moduleId) {
                    revert DuplicateModuleId(moduleId);
                }
            }
        }

        Attestation storage attestation = _attestations[releaseId];

        attestation.releaseId = releaseId;
        attestation.chainId = chainId;
        attestation.artifactDigest = artifactDigest;
        attestation.configurationVersion = configurationVersion;
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

    /**
     * @notice Returns the complete attestation for a release.
     */
    function getAttestation(
        bytes32 releaseId
    ) external view returns (Attestation memory) {
        _requireAttestation(releaseId);
        return _attestations[releaseId];
    }

    /**
     * @notice Returns whether a release has been attested.
     */
    function attestationExists(
        bytes32 releaseId
    ) external view returns (bool) {
        return hasAttestation[releaseId];
    }

    /**
     * @notice Returns the number of modules registered for a release.
     */
    function getModuleCount(
        bytes32 releaseId
    ) external view returns (uint256) {
        _requireAttestation(releaseId);
        return _attestations[releaseId].moduleIds.length;
    }

    /**
     * @notice Returns a module ID and address at a specific index.
     */
    function getModule(
        bytes32 releaseId,
        uint256 index
    ) external view returns (bytes32 moduleId, address moduleAddress) {
        _requireAttestation(releaseId);

        Attestation storage attestation = _attestations[releaseId];

        uint256 length = attestation.moduleIds.length;

        if (index >= length) {
            revert ModuleIndexOutOfBounds(releaseId, index, length);
        }

        return (
            attestation.moduleIds[index],
            attestation.moduleAddresses[index]
        );
    }

    /**
     * @notice Returns the configured governance authority.
     */
    function getGovernanceAuthority() external view returns (address) {
        return governanceAuthority;
    }

    /**
     * @notice Returns the deployer address recorded at construction.
     */
    function getDeployer() external view returns (address) {
        return deployer;
    }

    /**
     * @notice Revokes deployer authority so it retains no privileged access.
     *
     * @dev Only the governance authority may revoke. Once revoked, the
     *      deployer can never publish attestations again.
     */
    function revokeDeployer(address deployer_) external {
        if (msg.sender != governanceAuthority) {
            revert Unauthorized(msg.sender);
        }

        if (deployer_ == address(0)) {
            revert ZeroDeployer();
        }

        if (revokedDeployers[deployer_]) {
            revert DeployerAlreadyRevoked(deployer_);
        }

        revokedDeployers[deployer_] = true;

        emit DeployerRevoked(deployer_, msg.sender, uint64(block.timestamp));
    }

    /**
     * @notice Returns whether a deployer has been revoked.
     */
    function isDeployerRevoked(address deployer_) external view returns (bool) {
        return revokedDeployers[deployer_];
    }

    /**
     * @dev Reverts when the requested release does not exist.
     */
    function _requireAttestation(bytes32 releaseId) internal view {
        if (!hasAttestation[releaseId]) {
            revert InvalidReleaseId();
        }
    }

    /**
     * @dev Returns the byte length of a release ID by trimming trailing zeros.
     */
    function _releaseIdLength(bytes32 releaseId) internal pure returns (uint256) {
        uint256 length = 32;

        while (length > 0 && releaseId[length - 1] == 0) {
            --length;
        }

        return length;
    }
}