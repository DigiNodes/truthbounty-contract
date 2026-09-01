// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface ISlashing is IV2Module {
    event SlashProposed(bytes32 indexed proposalId, uint256 indexed claimId, address indexed verifier, uint256 amount, bytes32 reason);
    event SlashExecuted(bytes32 indexed proposalId, address indexed verifier, uint256 amount);
    function proposeSlash(uint256 claimId, address verifier, uint256 amount, bytes32 reason) external returns (bytes32 proposalId);
    function executeSlash(bytes32 proposalId) external;
    function slashAmount(bytes32 proposalId) external view returns (uint256);
}
