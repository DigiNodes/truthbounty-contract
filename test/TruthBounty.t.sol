function test_sameBlockSnapshotsHaveDistinctIds() public {
    bytes32 root1 = keccak256("root1");
    bytes32 root2 = keccak256("root2");

    // Both calls happen in same block (no vm.roll between them)
    uint256 id1 = contract.createSnapshot(root1);
    uint256 id2 = contract.createSnapshot(root2);

    assertTrue(id1 != id2, "IDs must be distinct");
    assertEq(contract.getSnapshot(id1).root, root1);
    assertEq(contract.getSnapshot(id2).root, root2);
}