// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface IVerification is IV2Module {
    event VerificationSubmitted(uint256 indexed verificationId, uint256 indexed claimId, address indexed verifier, bool supportsClaim, uint256 stake);
    function submitVerification(uint256 claimId, bool supportsClaim, bytes calldata rationale) external returns (uint256 verificationId);
    function getVerification(uint256 verificationId) external view returns (IV2Types.Verification memory);
    function claimVerifications(uint256 claimId, uint256 cursor, uint256 limit) external view returns (uint256[] memory ids, uint256 nextCursor);
}
