// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ReleaseReproducibility
/// @notice V2-SC-129 — pure, stateless helpers that pin the approved release
///         toolchain and validate release-manifest fields fail-closed.
/// @dev This library carries NO settlement, treasury, configuration, or upgrade
///      authority. It holds no storage, emits no events, performs no calls, and
///      moves no value. Every function is `pure`; identical inputs always yield
///      identical outputs, so verification is replayable by any observer.
///
///      The approved toolchain is solc 0.8.28, EVM version `cancun`, `viaIR`
///      enabled, and the optimizer enabled with exactly 200 runs — matching
///      `hardhat.config.ts`, `foundry.toml`, and
///      `deployments/releases/v2-sc-129-release-manifest.json`.
///      Canonical V2 modules link NO external libraries; any link reference or
///      zero-address library dependency is rejected.
library ReleaseReproducibility {
    /// @notice Approved solc version components.
    uint8 internal constant EXPECTED_SOLC_MAJOR = 0;
    uint8 internal constant EXPECTED_SOLC_MINOR = 8;
    uint8 internal constant EXPECTED_SOLC_PATCH = 28;

    /// @notice Approved optimizer run count.
    uint256 internal constant EXPECTED_OPTIMIZER_RUNS = 200;

    /// @notice keccak256("cancun") — the approved EVM version, as a hash so the
    ///         check stays in pure value space without string comparison.
    bytes32 internal constant EXPECTED_EVM_VERSION_HASH = keccak256("cancun");

    /// @notice Approved solc version packed as major * 1_000_000 + minor * 1_000 + patch.
    uint256 internal constant EXPECTED_SOLC_VERSION_CODE = 8028;

    /// @notice Approved SPDX license identifier hash for release inputs.
    /// @dev keccak256("MIT") — release inputs must declare an approved license.
    bytes32 internal constant EXPECTED_LICENSE_HASH = keccak256("MIT");

    /// @notice Maximum permitted length for a pinned source identifier.
    /// @dev Bounds the preimage space so attestation inputs stay canonical.
    uint256 internal constant MAX_SOURCE_IDENTIFIER_LENGTH = 256;

    /// @notice Maximum permitted length for a pinned artifact identifier.
    /// @dev Bounds the preimage space so attestation inputs stay canonical.
    uint256 internal constant MAX_ARTIFACT_IDENTIFIER_LENGTH = 256;

    /// @notice Compiler settings did not match the approved release toolchain.
    /// @param expectedSolcVersionCode Packed expected solc version.
    /// @param actualSolcVersionCode Packed actual solc version.
    error UnexpectedSolcVersion(uint256 expectedSolcVersionCode, uint256 actualSolcVersionCode);

    /// @notice Optimizer run count did not match the approved release toolchain.
    error UnexpectedOptimizerRuns(uint256 expectedRuns, uint256 actualRuns);

    /// @notice Optimizer was disabled; the release requires it enabled.
    error OptimizerDisabled();

    /// @notice `viaIR` was disabled; the release requires it enabled.
    error ViaIRDisabled();

    /// @notice EVM version hash did not match `keccak256("cancun")`.
    error EvmVersionMismatch(bytes32 expectedHash, bytes32 actualHash);

    /// @notice A library dependency resolved to the zero address.
    error ZeroLibraryAddress(string libName);

    /// @notice Build output still contains unresolved link references.
    /// @param count Number of unresolved link references found.
    error UnexpectedLinkReference(uint256 count);

    /// @notice A pinned source hash was empty.
    error EmptySourceHash(string source);

    /// @notice A pinned bytecode hash was empty.
    error EmptyBytecodeHash(string artifact);

    /// @notice Recomputed release digest did not match the approved manifest digest.
    error DigestMismatch(bytes32 expectedDigest, uint256 actualDigest);

    /// @notice A release input declared a disallowed or missing license.
    /// @param source Identifier of the offending release input.
    /// @param actualLicenseHash Hash of the declared license identifier.
    error DisallowedLicense(string source, bytes32 actualLicenseHash);

    /// @notice A release input was not pinned to an immutable revision.
    /// @param source Identifier of the offending release input.
    error UnpinnedSource(string source);

    /// @notice A release input identifier exceeded the canonical length bound.
    /// @param source Identifier of the offending release input.
    /// @param length Observed identifier length.
    error SourceIdentifierTooLong(string source, uint256 length);

    /// @notice An artifact identifier exceeded the canonical length bound.
    /// @param artifact Identifier of the offending artifact.
    /// @param length Observed identifier length.
    error ArtifactIdentifierTooLong(string artifact, uint256 length);

    /// @notice A release input carried a secret-like marker and must not enter artifacts.
    /// @param source Identifier of the offending release input.
    error SecretInArtifact(string source);

    /// @notice Pack `(major, minor, patch)` into a single comparable version code.
    /// @dev Rejects components that would overflow the packing scheme fail-closed.
    function packSolcVersion(uint256 major, uint256 minor, uint256 patch) internal pure returns (uint256) {
        if (major > 255 || minor > 999 || patch > 999) {
            revert UnexpectedSolcVersion(EXPECTED_SOLC_VERSION_CODE, type(uint256).max);
        }
        return major * 1_000_000 + minor * 1_000 + patch;
    }

    /// @notice Validate compiler settings against the approved release toolchain.
    /// @dev Fail-closed: any deviation reverts with a typed error. No state, no authority.
    function validateCompiler(
        uint256 major,
        uint256 minor,
        uint256 patch,
        bool optimizerEnabled,
        uint256 runs,
        bool viaIR,
        bytes32 evmVersionHash
    ) internal pure {
        uint256 actual = packSolcVersion(major, minor, patch);
        if (actual != EXPECTED_SOLC_VERSION_CODE) {
            revert UnexpectedSolcVersion(EXPECTED_SOLC_VERSION_CODE, actual);
        }
        if (!optimizerEnabled) revert OptimizerDisabled();
        if (runs != EXPECTED_OPTIMIZER_RUNS) revert UnexpectedOptimizerRuns(EXPECTED_OPTIMIZER_RUNS, runs);
        if (!viaIR) revert ViaIRDisabled();
        if (evmVersionHash != EXPECTED_EVM_VERSION_HASH) {
            revert EvmVersionMismatch(EXPECTED_EVM_VERSION_HASH, evmVersionHash);
        }
    }

    /// @notice Reject a zero-address library dependency fail-closed.
    function validateLibraryAddress(address dependency) internal pure {
        if (dependency == address(0)) revert ZeroLibraryAddress("unknown");
    }

    /// @notice Reject a named library dependency that resolves to the zero address.
    function validateNamedLibrary(string memory libName, address dependency) internal pure {
        if (dependency == address(0)) revert ZeroLibraryAddress(libName);
    }

    /// @notice Reject build output that still carries unresolved link references.
    /// @dev Canonical V2 modules link no external libraries, so any nonzero
    ///      count is a reproducibility failure (unlinked `__$..$__` placeholders
    ///      would make deployed bytecode non-deterministic).
    function assertNoLinkReferences(uint256 linkReferenceCount) internal pure {
        if (linkReferenceCount != 0) revert UnexpectedLinkReference(linkReferenceCount);
    }

    /// @notice Require a pinned source hash to be nonzero (fail-closed on empty pins).
    function requireSourceHash(string memory source, bytes32 sourceHash) internal pure {
        if (sourceHash == bytes32(0)) revert EmptySourceHash(source);
    }

    /// @notice Require a pinned bytecode hash to be nonzero (fail-closed on empty pins).
    function requireBytecodeHash(string memory artifact, bytes32 bytecodeHash) internal pure {
        if (bytecodeHash == bytes32(0)) revert EmptyBytecodeHash(artifact);
    }

    /// @notice Require a release input to declare an approved license.
    /// @dev Fail-closed: missing or disallowed licenses revert with a typed error.
    function requireApprovedLicense(string memory source, bytes32 licenseHash) internal pure {
        if (licenseHash != EXPECTED_LICENSE_HASH) revert DisallowedLicense(source, licenseHash);
    }

    /// @notice Require a release input to be pinned to an immutable revision.
    /// @dev A zero revision hash indicates an unpinned (mutable) input and reverts.
    function requirePinnedSource(string memory source, bytes32 revisionHash) internal pure {
        if (revisionHash == bytes32(0)) revert UnpinnedSource(source);
    }

    /// @notice Require a source identifier to stay within the canonical length bound.
    function requireSourceIdentifier(string memory source) internal pure {
        uint256 length = bytes(source).length;
        if (length == 0 || length > MAX_SOURCE_IDENTIFIER_LENGTH) {
            revert SourceIdentifierTooLong(source, length);
        }
    }

    /// @notice Require an artifact identifier to stay within the canonical length bound.
    function requireArtifactIdentifier(string memory artifact) internal pure {
        uint256 length = bytes(artifact).length;
        if (length == 0 || length > MAX_ARTIFACT_IDENTIFIER_LENGTH) {
            revert ArtifactIdentifierTooLong(artifact, length);
        }
    }

    /// @notice Reject release inputs that carry secret-like markers.
    /// @dev Fail-closed guard so no secret material can enter published artifacts.
    function requireNoSecret(string memory source, bool secretDetected) internal pure {
        if (secretDetected) revert SecretInArtifact(source);
    }

    /// @notice Validate a full release input record fail-closed.
    /// @dev Composes the individual checks so callers cannot skip any pin.
    function validateReleaseInput(
        string memory source,
        bytes32 revisionHash,
        bytes32 licenseHash,
        bytes32 sourceHash,
        bool secretDetected
    ) internal pure {
        requireSourceIdentifier(source);
        requirePinnedSource(source, revisionHash);
        requireApprovedLicense(source, licenseHash);
        requireSourceHash(source, sourceHash);
        requireNoSecret(source, secretDetected);
    }

    /// @notice Compute the deterministic release digest over toolchain pins,
    ///         source hashes, and bytecode hashes.
    /// @dev `abi.encode` (not `pack`) keeps field boundaries unambiguous so the
    ///      digest has exactly one preimage parse. Pure and replayable.
    function releaseDigest(
        uint256 solcVersionCode,
        bool optimizerEnabled,
        uint256 optimizerRuns,
        bool viaIR,
        bytes32 evmVersionHash,
        bytes32[] memory sourceHashes,
        bytes32[] memory bytecodeHashes
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                solcVersionCode, optimizerEnabled, optimizerRuns, viaIR, evmVersionHash, sourceHashes, bytecodeHashes
            )
        );
    }

    /// @notice Check a recomputed digest against the approved manifest digest.
    function checkDigest(bytes32 expectedDigest, bytes32 actualDigest) internal pure {
        if (expectedDigest != actualDigest) revert DigestMismatch(expectedDigest, uint256(actualDigest));
    }
}
