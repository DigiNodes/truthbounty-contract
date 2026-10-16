// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BoundedStaticCall} from "./BoundedStaticCall.sol";

/// @notice Safe ERC20 operations that never copy unbounded token returndata.
library BoundedSafeERC20 {
    /// @notice Maximum gas forwarded to each ERC20 operation.
    /// @dev Generous for standard tokens while limiting hostile-token gas griefing.
    uint256 internal constant ERC20_CALL_GAS_LIMIT = 250_000;
    /// @notice The token reverted, returned malformed data, or reported failure.
    /// @dev Selector matches OpenZeppelin SafeERC20FailedOperation(address).
    error SafeERC20FailedOperation(address token);

    /// @notice A no-return token call targeted an address without code.
    /// @dev Selector matches OpenZeppelin AddressEmptyCode(address).
    error AddressEmptyCode(address target);

    /// @notice The observed token balance delta did not match the requested amount.
    /// @dev Raised by `safeTransferFromExact` and `safeTransferExact` when a token is not
    ///      exact-transfer (e.g. fee-on-transfer, rebasing, or a false-reporting token).
    error TokenTransferMismatch(address token, uint256 expected, uint256 observed);

    /// @notice Calls `transfer` and validates only the bounded optional return word.
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.transfer, (to, value)));
    }

    /// @notice Calls `transferFrom` and validates only the bounded optional return word.
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.transferFrom, (from, to, value)));
    }

    /// @notice Calls `transferFrom` and requires the observed recipient balance delta to equal `value`.
    /// @dev Rejects fee-on-transfer, rebasing, false-reporting, and any token whose observed
    ///      delta differs from the requested amount. The balance is re-read after the
    ///      transfer so a reentrant hook cannot fake the delta.
    function safeTransferFromExact(IERC20 token, address from, address to, uint256 value) internal {
        uint256 beforeBalance = _balanceOf(token);
        _callOptionalReturn(token, abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        uint256 afterBalance = _balanceOf(token);
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != value) {
            revert TokenTransferMismatch(address(token), value, afterBalance > beforeBalance ? afterBalance - beforeBalance : 0);
        }
    }

    /// @notice Calls `transfer` and requires the observed recipient balance delta to equal `value`.
    function safeTransferExact(IERC20 token, address to, uint256 value) internal {
        uint256 beforeBalance = _balanceOf(token);
        _callOptionalReturn(token, abi.encodeCall(IERC20.transfer, (to, value)));
        uint256 afterBalance = _balanceOf(token);
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != value) {
            revert TokenTransferMismatch(address(token), value, afterBalance > beforeBalance ? afterBalance - beforeBalance : 0);
        }
    }

    /// @notice Increases an allowance while bounding token return-data copying.
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        (bool success, uint256 currentAllowance, uint256 returnSize) = BoundedStaticCall.staticcallWord(
            address(token),
            abi.encodeCall(IERC20.allowance, (address(this), spender))
        );
        if (!success || returnSize != 32) revert SafeERC20FailedOperation(address(token));
        uint256 newAllowance = currentAllowance + value;
        _callOptionalReturn(token, abi.encodeCall(IERC20.approve, (spender, newAllowance)));
    }

    /// @notice Decreases an allowance while bounding token return-data copying.
    /// @dev Mirrors OpenZeppelin SafeERC20.safeDecreaseAllowance semantics: the
    ///      allowance is reduced by `value` and the call reverts if `value`
    ///      exceeds the current allowance, instead of underflowing.
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        (bool success, uint256 currentAllowance, uint256 returnSize) = BoundedStaticCall.staticcallWord(
            address(token),
            abi.encodeCall(IERC20.allowance, (address(this), spender))
        );
        if (!success || returnSize != 32) revert SafeERC20FailedOperation(address(token));
        if (value > currentAllowance) revert SafeERC20FailedOperation(address(token));
        uint256 newAllowance = currentAllowance - value;
        _callOptionalReturn(token, abi.encodeCall(IERC20.approve, (spender, newAllowance)));
    }

    /// @notice Reads the current token balance of this contract with a bounded static call.
    function _balanceOf(IERC20 token) private view returns (uint256) {
        (bool success, uint256 balance, uint256 returnSize) = BoundedStaticCall.staticcallWord(
            address(token),
            abi.encodeCall(IERC20.balanceOf, (address(this)))
        );
        if (!success || returnSize != 32) revert SafeERC20FailedOperation(address(token));
        return balance;
    }

    function _callOptionalReturn(IERC20 token, bytes memory callData) private {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        address tokenAddress = address(token);

        assembly {
            let output := mload(0x40)
            mstore(0x40, add(output, 0x20))
            success := call(ERC20_CALL_GAS_LIMIT, tokenAddress, 0, add(callData, 0x20), mload(callData), output, 0x20)
            returnSize := returndatasize()
            returnValue := mload(output)
        }

        if (!success) revert SafeERC20FailedOperation(tokenAddress);
        if (returnSize == 0) {
            if (tokenAddress.code.length == 0) revert AddressEmptyCode(tokenAddress);
            return;
        }
        if (returnSize < 32 || returnValue != 1) revert SafeERC20FailedOperation(tokenAddress);
    }
}
