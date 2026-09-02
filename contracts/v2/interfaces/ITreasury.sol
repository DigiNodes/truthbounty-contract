// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface ITreasury is IV2Module {
    event FundsDeposited(address indexed from, uint256 amount, bytes32 indexed bucket);
    event FundsWithdrawn(address indexed to, uint256 amount, bytes32 indexed bucket);
    function deposit(bytes32 bucket, uint256 amount) external;
    function withdraw(bytes32 bucket, address to, uint256 amount) external;
    function balanceOf(bytes32 bucket) external view returns (uint256);
}
