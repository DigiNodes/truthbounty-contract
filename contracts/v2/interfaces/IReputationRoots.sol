// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IReputationRoots is IV2Module {
    event RootProposed(uint256 indexed epoch, bytes32 indexed root, address indexed proposer);
    event RootAccepted(uint256 indexed epoch, bytes32 indexed root);
    function proposeRoot(uint256 epoch, bytes32 root, string calldata uri) external;
    function acceptRoot(uint256 epoch) external;
    function rootAt(uint256 epoch) external view returns (bytes32 root, bool accepted);
    function verify(uint256 epoch, address account, uint256 score, bytes32[] calldata proof) external view returns (bool);
}
