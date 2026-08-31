// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "./IReputationOracle.sol";
import "./governance/GovernanceOwnable.sol";

contract ReputationSnapshotEngine is AccessControl, Pausable {
    using Checkpoints for Checkpoints.Trace256;

    bytes32 public constant SNAPSHOT_ROLE   = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant ENGINE_ROLE     = keccak256("ENGINE_ROLE");
    bytes32 public constant PAUSER_ROLE     = keccak256("PAUSER_ROLE");

    struct SnapshotEntry {
        address verifier;
        uint256 reputationScore;
        uint256 blockNumber;
        uint256 timestamp;
    }

    struct SnapshotMetadata {
        uint256 id;
        uint256 entryCount;
        uint256 createdAt;
        uint256 createdBlock;
        bool finalized;
    }

    uint256 private _snapshotCounter;

    mapping(uint256 => SnapshotMetadata) public snapshotMeta;

    mapping(uint256 => SnapshotEntry[]) private _snapshotEntries;

    mapping(uint256 => mapping(address => bool)) private _entryIncluded;

    mapping(address => Checkpoints.Trace256) private _reputationHistory;

    mapping(uint256 => address[]) private _snapshotVerifiers;

    event VerifierSnapshotRecorded(
        address indexed verifier,
        uint256 indexed snapshotId,
        uint256 reputationScore,
        uint256 blockNumber,
        uint256 timestamp
    );

    event GlobalSnapshotCreated(
        uint256 indexed snapshotId,
        uint256 entryCount,
        uint256 createdAt,
        uint256 createdBlock
    );

    event ReputationCheckpointed(
        address indexed verifier,
        uint256 reputationScore,
        uint256 blockNumber
    );

    event SnapshotFinalized(uint256 indexed snapshotId, uint256 entryCount);

    error SnapshotAlreadyFinalized(uint256 snapshotId);
    error InvalidSnapshot(uint256 snapshotId);
    error EmptySnapshot();
    error ZeroAddress();
    error DuplicateEntry(uint256 snapshotId, address verifier);
    error VerifierNotInSnapshot(uint256 snapshotId, address verifier);

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SNAPSHOT_ROLE,      admin);
        _grantRole(ENGINE_ROLE,        admin);
        _grantRole(PAUSER_ROLE,        admin);
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function checkpointReputation(
        address verifier,
        uint256 reputationScore
    ) external onlyRole(ENGINE_ROLE) whenNotPaused {
        if (verifier == address(0)) revert ZeroAddress();

        _reputationHistory[verifier].push(block.number, reputationScore);

        emit ReputationCheckpointed(verifier, reputationScore, block.number);
    }

    function createGlobalSnapshot(
        address[] calldata verifiers,
        IReputationOracle oracle
    )
        external
        onlyRole(SNAPSHOT_ROLE)
        whenNotPaused
        returns (uint256 snapshotId)
    {
        uint256 length = verifiers.length;
        if (length == 0) revert EmptySnapshot();

        snapshotId = ++_snapshotCounter;
        uint256 blockNum = block.number;
        uint256 ts = block.timestamp;

        SnapshotEntry[] storage entries = _snapshotEntries[snapshotId];

        for (uint256 i = 0; i < length; i++) {
            address verifier = verifiers[i];
            if (verifier == address(0)) revert ZeroAddress();
            if (_entryIncluded[snapshotId][verifier]) revert DuplicateEntry(snapshotId, verifier);

            _entryIncluded[snapshotId][verifier] = true;
            _snapshotVerifiers[snapshotId].push(verifier);

            uint256 score;
            if (address(oracle) != address(0)) {
                try oracle.getReputationScore(verifier) returns (uint256 s) {
                    score = s;
                } catch {
                    score = 0;
                }
            } else {
                (score, ) = _getCheckpointAtBlock(verifier, blockNum);
            }

            entries.push(SnapshotEntry({
                verifier:        verifier,
                reputationScore: score,
                blockNumber:     blockNum,
                timestamp:       ts
            }));
        }

        snapshotMeta[snapshotId] = SnapshotMetadata({
            id:          snapshotId,
            entryCount:  length,
            createdAt:   ts,
            createdBlock: blockNum,
            finalized:   true
        });

        emit GlobalSnapshotCreated(snapshotId, length, ts, blockNum);
    }

    function recordProtocolSnapshot(
        address verifier,
        uint256 reputationScore
    )
        external
        onlyRole(ENGINE_ROLE)
        whenNotPaused
        returns (uint256 snapshotId)
    {
        if (verifier == address(0)) revert ZeroAddress();

        snapshotId = ++_snapshotCounter;
        uint256 blockNum = block.number;
        uint256 ts = block.timestamp;

        _reputationHistory[verifier].push(blockNum, reputationScore);

        _snapshotEntries[snapshotId].push(SnapshotEntry({
            verifier:        verifier,
            reputationScore: reputationScore,
            blockNumber:     blockNum,
            timestamp:       ts
        }));

        _entryIncluded[snapshotId][verifier] = true;
        _snapshotVerifiers[snapshotId].push(verifier);

        snapshotMeta[snapshotId] = SnapshotMetadata({
            id:          snapshotId,
            entryCount:  1,
            createdAt:   ts,
            createdBlock: blockNum,
            finalized:   true
        });

        emit VerifierSnapshotRecorded(verifier, snapshotId, reputationScore, blockNum, ts);
        emit GlobalSnapshotCreated(snapshotId, 1, ts, blockNum);
    }

    function getSnapshot(
        uint256 snapshotId
    )
        external
        view
        returns (SnapshotMetadata memory meta, SnapshotEntry[] memory entries)
    {
        meta = snapshotMeta[snapshotId];
        if (meta.id == 0) revert InvalidSnapshot(snapshotId);
        entries = _snapshotEntries[snapshotId];
    }

    function getSnapshotAtBlock(
        address verifier,
        uint256 blockNumber
    )
        external
        view
        returns (uint256 reputationScore, bool found)
    {
        return _getCheckpointAtBlock(verifier, blockNumber);
    }

    function getLatestSnapshot(
        address verifier
    )
        external
        view
        returns (uint256 reputationScore, uint256 blockNumber)
    {
        (bool exists, uint256 key, uint256 value) = _reputationHistory[verifier].latestCheckpoint();
        if (!exists) return (0, 0);
        return (value, key);
    }

    function getVerifierSnapshots(
        address verifier,
        uint256 fromBlock,
        uint256 toBlock
    )
        external
        view
        returns (uint256[] memory blockNumbers, uint256[] memory scores)
    {
        uint256 len = _reputationHistory[verifier].length();
        uint256 count;
        for (uint256 i = 0; i < len; i++) {
            Checkpoints.Checkpoint256 memory cp = _reputationHistory[verifier].at(uint32(i));
            if (cp._key >= fromBlock && cp._key <= toBlock) {
                count++;
            }
        }

        blockNumbers = new uint256[](count);
        scores = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < len; i++) {
            Checkpoints.Checkpoint256 memory cp = _reputationHistory[verifier].at(uint32(i));
            if (cp._key >= fromBlock && cp._key <= toBlock) {
                blockNumbers[idx] = cp._key;
                scores[idx] = cp._value;
                idx++;
            }
        }
    }

    function getVerifierCheckpointCount(address verifier) external view returns (uint256) {
        return _reputationHistory[verifier].length();
    }

    function getVerifierCheckpointAt(
        address verifier,
        uint256 pos
    )
        external
        view
        returns (uint256 blockNumber, uint256 reputationScore)
    {
        Checkpoints.Checkpoint256 memory cp = _reputationHistory[verifier].at(uint32(pos));
        return (cp._key, cp._value);
    }

    function getSnapshotEntry(
        uint256 snapshotId,
        address verifier
    )
        external
        view
        returns (SnapshotEntry memory entry)
    {
        if (snapshotMeta[snapshotId].id == 0) revert InvalidSnapshot(snapshotId);
        if (!_entryIncluded[snapshotId][verifier]) revert VerifierNotInSnapshot(snapshotId, verifier);
        SnapshotEntry[] storage entries = _snapshotEntries[snapshotId];
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].verifier == verifier) {
                return entries[i];
            }
        }
        revert VerifierNotInSnapshot(snapshotId, verifier);
    }

    function isVerifierInSnapshot(uint256 snapshotId, address verifier) external view returns (bool) {
        return _entryIncluded[snapshotId][verifier];
    }

    function latestSnapshotId() external view returns (uint256) {
        return _snapshotCounter;
    }

    function getSnapshotVerifierCount(uint256 snapshotId) external view returns (uint256) {
        return _snapshotVerifiers[snapshotId].length;
    }

    function getSnapshotVerifierAt(
        uint256 snapshotId,
        uint256 index
    )
        external
        view
        returns (address verifier, uint256 reputationScore, uint256 blockNumber, uint256 timestamp)
    {
        if (index >= _snapshotVerifiers[snapshotId].length) revert InvalidSnapshot(snapshotId);
        SnapshotEntry storage entry = _snapshotEntries[snapshotId][index];
        return (entry.verifier, entry.reputationScore, entry.blockNumber, entry.timestamp);
    }

    function getSnapshotPage(
        uint256 snapshotId,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (SnapshotEntry[] memory page)
    {
        SnapshotEntry[] storage entries = _snapshotEntries[snapshotId];
        uint256 total = entries.length;
        if (offset >= total) return new SnapshotEntry[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        page = new SnapshotEntry[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = entries[i];
        }
    }

    function _getCheckpointAtBlock(
        address verifier,
        uint256 blockNumber
    )
        internal
        view
        returns (uint256 reputationScore, bool found)
    {
        uint256 len = _reputationHistory[verifier].length();
        if (len == 0) return (0, false);

        uint256 value = _reputationHistory[verifier].upperLookup(blockNumber);
        if (value == 0) {
            (bool exists,, uint256 latestVal) = _reputationHistory[verifier].latestCheckpoint();
            if (!exists) return (0, false);
            if (latestVal == 0) {
                for (uint256 i = 0; i < len; i++) {
                    Checkpoints.Checkpoint256 memory cp = _reputationHistory[verifier].at(uint32(i));
                    if (cp._key <= blockNumber) {
                        if (cp._value > 0) return (cp._value, true);
                        return (0, true);
                    }
                }
                return (0, false);
            }
            return (latestVal, true);
        }
        return (value, true);
    }
}