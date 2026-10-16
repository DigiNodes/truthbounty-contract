// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DeploymentAttestationRegistry
 * @notice Append-only, on-chain release metadata for the canonical protocol.
 *
 * @dev The governance authority records an exact artifact and module-address
 *      manifest. Once recorded, a release can never be overwritten or deleted.
 *
 *      Source publication verification evidence (explorer response, fallback
 *      evidence, compiler settings, and constructor arguments) is bound to the
 *      release manifest so that explorer success is never treated as code
 *      correctness. Verification inputs are derived from canonical build
 *      metadata and must not be hand-edited.
 *
 *      The registry allows indexers and other contracts to independently
 *      verify deployment metadata without trusting an off-chain API or
 *      deployer database.
 */
contract DeploymentAttestationRegistry {
    uint256 public constant MAX_MODULES = 32;

    /// @notice Maximum number of linked libraries recorded per module.
    uint256 public constant MAX_LIBRARIES_PER_MODULE = 16;

    /// @notice Maximum length of a flattened-source rejection reason.
    uint256 public constant MAX_REASON_LENGTH = 256;

    struct Attestation {
        bytes32 releaseId;
        uint256 chainId;
        bytes32 artifactDigest;
        uint64 configurationVersion;
        bytes32[] moduleIds;
        address[] moduleAddresses;
        uint64 recordedAt;
    }

    struct SourceVerification {
        bytes32 releaseId;
        bytes32 moduleId;
        address moduleAddress;
        bytes32 buildInputDigest;
        bytes32 compilerSettingsDigest;
        bytes32 constructorArgsDigest;
        bytes32 proxyImplementationDigest;
        bytes32[] libraryDigests;
        bool explorerVerified;
        bool fallbackUsed;
        bool flattenedSourceRejected;
        uint64 recordedAt;
    }

    /// @notice Address authorized to publish deployment attestations.
    address public immutable governanceAuthority;

    /// @notice Number of attestations successfully recorded.
    uint256 public attestationCount;

    mapping(bytes32 => Attestation) private _attestations;
    mapping(bytes32 => bool) public hasAttestation;

    mapping(bytes32 => mapping(bytes32 => SourceVerification))
        private _sourceVerifications;
    mapping(bytes32 => mapping(bytes32 => bool)) public hasSourceVerification;

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
    error UnknownModule(bytes32 releaseId, bytes32 moduleId);
    error SourceVerificationAlreadyExists(
        bytes32 releaseId,
        bytes32 moduleId
    );
    error InvalidBuildInputDigest();
    error InvalidCompilerSettingsDigest();
    error InvalidConstructorArgsDigest();
    error InvalidProxyImplementationDigest();
    error TooManyLibraries(uint256 supplied, uint256 maximum);
    error ZeroLibraryDigest(uint256 index);
    error ReasonTooLong(uint256 length, uint256 maximum);
    error FlattenedSourceNotRejected();
    error MissingVerificationEvidence();

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

    event SourceVerificationRecorded(
        bytes32 indexed releaseId,
        bytes32 indexed moduleId,
        address indexed moduleAddress,
        bytes32 buildInputDigest,
        bytes32 compilerSettingsDigest,
        bytes32 constructorArgsDigest,
        bytes32 proxyImplementationDigest,
        bytes32[] libraryDigests,
        bool explorerVerified,
        bool fallbackUsed,
        bool flattenedSourceRejected,
        uint64 recordedAt
    );

    constructor(address governanceAuthority_) {
        if (governanceAuthority_ == address(0)) {
            revert ZeroGovernanceAuthority();
        }

        governanceAuthority = governanceAuthority_;
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

        if (releaseId == bytes32(0)) {
            revert InvalidReleaseId();
        }

        if (artifactDigest == bytes32(0)) {
            revert InvalidArtifactDigest();
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
     * @notice Record source publication verification evidence for a module.
     *
     * @dev Only the configured governance authority may attest. The module
     *      must already be part of the release manifest. All digests must be
     *      derived from canonical build inputs; no hand-edited arguments are
     *      accepted. Flattened-source submissions must be explicitly rejected
     *      before evidence is recorded. Explorer success is recorded as
     *      evidence only and never as a correctness assertion.
     */
    function recordSourceVerification(
        bytes32 releaseId,
        bytes32 moduleId,
        bytes32 buildInputDigest,
        bytes32 compilerSettingsDigest,
        bytes32 constructorArgsDigest,
        bytes32 proxyImplementationDigest,
        bytes32[] calldata libraryDigests,
        bool explorerVerified,
        bool fallbackUsed,
        bool flattenedSourceRejected
    ) external {
        if (msg.sender != governanceAuthority) {
            revert Unauthorized(msg.sender);
        }

        _requireAttestation(releaseId);

        if (moduleId == bytes32(0)) {
            revert ZeroModuleId(0);
        }

        if (buildInputDigest == bytes32(0)) {
            revert InvalidBuildInputDigest();
        }

        if (compilerSettingsDigest == bytes32(0)) {
            revert InvalidCompilerSettingsDigest();
        }

        if (constructorArgsDigest == bytes32(0)) {
            revert InvalidConstructorArgsDigest();
        }

        if (proxyImplementationDigest == bytes32(0)) {
            revert InvalidProxyImplementationDigest();
        }

        if (libraryDigests.length > MAX_LIBRARIES_PER_MODULE) {
            revert TooManyLibraries(
                libraryDigests.length,
                MAX_LIBRARIES_PER_MODULE
            );
        }

        if (!flattenedSourceRejected) {
            revert FlattenedSourceNotRejected();
        }

        if (!explorerVerified && !fallbackUsed) {
            revert MissingVerificationEvidence();
        }

        if (hasSourceVerification[releaseId][moduleId]) {
            revert SourceVerificationAlreadyExists(releaseId, moduleId);
        }

        (address moduleAddress, bool found) = _findModule(
            releaseId,
            moduleId
        );

        if (!found) {
            revert UnknownModule(releaseId, moduleId);
        }

        uint256 libraryCount = libraryDigests.length;

        for (uint256 i; i < libraryCount; ++i) {
            if (libraryDigests[i] == bytes32(0)) {
                revert ZeroLibraryDigest(i);
            }
        }

        SourceVerification storage verification = _sourceVerifications[
            releaseId
        ][moduleId];

        verification.releaseId = releaseId;
        verification.moduleId = moduleId;
        verification.moduleAddress = moduleAddress;
        verification.buildInputDigest = buildInputDigest;
        verification.compilerSettingsDigest = compilerSettingsDigest;
        verification.constructorArgsDigest = constructorArgsDigest;
        verification.proxyImplementationDigest = proxyImplementationDigest;
        verification.explorerVerified = explorerVerified;
        verification.fallbackUsed = fallbackUsed;
        verification.flattenedSourceRejected = flattenedSourceRejected;
        verification.recordedAt = uint64(block.timestamp);

        for (uint256 i; i < libraryCount; ++i) {
            verification.libraryDigests.push(libraryDigests[i]);
        }

        hasSourceVerification[releaseId][moduleId] = true;

        emit SourceVerificationRecorded(
            releaseId,
            moduleId,
            moduleAddress,
            buildInputDigest,
            compilerSettingsDigest,
            constructorArgsDigest,
            proxyImplementationDigest,
            libraryDigests,
            explorerVerified,
            fallbackUsed,
            flattenedSourceRejected,
            verification.recordedAt
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
     * @notice Returns the source verification evidence for a module.
     */
    function getSourceVerification(
        bytes32 releaseId,
        bytes32 moduleId
    ) external view returns (SourceVerification memory) {
        _requireAttestation(releaseId);

        if (!hasSourceVerification[releaseId][moduleId]) {
            revert UnknownModule(releaseId, moduleId);
        }

        return _sourceVerifications[releaseId][moduleId];
    }

    /**
     * @notice Returns whether a module has recorded source verification.
     */
    function sourceVerificationExists(
        bytes32 releaseId,
        bytes32 moduleId
    ) external view returns (bool) {
        return hasSourceVerification[releaseId][moduleId];
    }

    /**
     * @notice Returns the configured governance authority.
     */
    function getGovernanceAuthority() external view returns (address) {
        return governanceAuthority;
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
     * @dev Locates a module address within a release manifest.
     */
    function _findModule(
        bytes32 releaseId,
        bytes32 moduleId
    ) internal view returns (address moduleAddress, bool found) {
        Attestation storage attestation = _attestations[releaseId];

        uint256 length = attestation.moduleIds.length;

        for (uint256 i; i < length; ++i) {
            if (attestation.moduleIds[i] == moduleId) {
                return (attestation.moduleAddresses[i], true);
            }
        }

        return (address(0), false);
    }
}