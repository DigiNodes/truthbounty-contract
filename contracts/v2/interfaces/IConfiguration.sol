// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IConfiguration is IV2Module {
    event ParameterUpdated(bytes32 indexed key, uint256 oldValue, uint256 newValue, address indexed actor);
    event AddressParameterUpdated(bytes32 indexed key, address indexed oldValue, address indexed newValue, address actor);
    function getUint(bytes32 key) external view returns (uint256);
    function getAddress(bytes32 key) external view returns (address);
    function setUint(bytes32 key, uint256 value) external;
    function setAddress(bytes32 key, address value) external;
}
