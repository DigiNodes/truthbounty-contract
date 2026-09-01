// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface IEvidence is IV2Module {
    event EvidenceSubmitted(uint256 indexed evidenceId, uint256 indexed claimId, address indexed submitter, bytes32 contentHash);
    event EvidenceStatusChanged(uint256 indexed evidenceId, IV2Types.EvidenceStatus previousStatus, IV2Types.EvidenceStatus newStatus, address indexed actor);
    function submitEvidence(uint256 claimId, bytes32 contentHash, bytes calldata metadata) external returns (uint256 evidenceId);
    function setEvidenceStatus(uint256 evidenceId, IV2Types.EvidenceStatus status) external;
    function getEvidence(uint256 evidenceId) external view returns (IV2Types.Evidence memory);
    function claimEvidence(uint256 claimId, uint256 cursor, uint256 limit) external view returns (uint256[] memory evidenceIds, uint256 nextCursor);
}
