// State variable — add near your other storage declarations
uint256 private snapshotCounter;

// Replace your existing createSnapshot function
function createSnapshot(bytes32 merkleRoot) external onlyOwner returns (uint256 snapshotId) {
    snapshotId = ++snapshotCounter; // pre-increment guarantees starting from 1, never 0
    require(snapshots[snapshotId].root == bytes32(0), "Snapshot ID already exists");
    snapshots[snapshotId] = Snapshot({
        root: merkleRoot,
        timestamp: block.timestamp
    });
    emit SnapshotCreated(snapshotId, merkleRoot, block.timestamp);
}