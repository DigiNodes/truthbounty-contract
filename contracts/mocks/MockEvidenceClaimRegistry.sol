// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IClaimRegistry} from "../interfaces/IClaimRegistry.sol";

contract MockEvidenceClaimRegistry is IClaimRegistry {
    mapping(uint256 => Claim) private _claims;
    mapping(uint256 => bool) private _exists;

    function setClaim(uint256 claimId, address creator, uint64 verificationDeadline, ClaimStatus status) external {
        _claims[claimId] = Claim({
            id: claimId,
            creator: creator,
            statement: "",
            evidenceCID: "",
            status: status,
            createdAt: uint64(block.timestamp),
            verificationDeadline: verificationDeadline
        });
        _exists[claimId] = true;
    }

    function setClaimStatus(uint256 claimId, ClaimStatus status) external {
        _claims[claimId].status = status;
    }

    function createClaim(string calldata, string calldata, uint64) external pure returns (uint256) {
        revert("not implemented");
    }

    function updateClaimStatus(uint256, ClaimStatus) external pure {
        revert("not implemented");
    }

    function createCanonicalClaim(address, address, uint256, bytes32, bytes32, uint256)
        external
        pure
        returns (bytes32)
    {
        revert("not implemented");
    }

    function createCanonicalClaim(address, address, uint256, bytes32, bytes32, uint256, uint256)
        external
        pure
        returns (bytes32)
    {
        revert("not implemented");
    }

    function currentConfigVersion() external pure returns (uint256) {
        return 1;
    }

    function setSupportedAsset(address, bool, uint256, uint256) external pure {
        revert("not implemented");
    }

    function isSupportedAsset(address) external pure returns (bool) {
        return false;
    }

    function getAssetBounds(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function computeClaimId(address, uint256, bytes32) external pure returns (bytes32) {
        revert("not implemented");
    }

    function claimIdFor(address, uint256, bytes32) external pure returns (bytes32) {
        revert("not implemented");
    }

    function getCanonicalClaim(bytes32) external pure returns (CanonicalClaim memory) {
        revert("not implemented");
    }

    function claimExists(bytes32) external pure returns (bool) {
        return false;
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        if (!_exists[claimId]) revert ClaimNotFound(claimId);
        return _claims[claimId];
    }

    function claimExists(uint256 claimId) external view returns (bool) {
        return _exists[claimId];
    }

    function totalClaims() external pure returns (uint256) {
        return 0;
    }

    function getClaimCreator(uint256 claimId) external view returns (address) {
        if (!_exists[claimId]) revert ClaimNotFound(claimId);
        return _claims[claimId].creator;
    }

    function getClaimStatus(uint256 claimId) external view returns (ClaimStatus) {
        if (!_exists[claimId]) revert ClaimNotFound(claimId);
        return _claims[claimId].status;
    }
}
