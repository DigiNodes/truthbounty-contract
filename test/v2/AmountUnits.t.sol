// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/v2/libraries/V2AmountUnits.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DecimalsToken is ERC20 {
    uint8 private immutable _dec;

    constructor(uint8 dec) ERC20("Dec", "DEC") {
        _dec = dec;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}

contract NoDecimalsToken { }

contract AmountUnitsHarness {
    function decimalsOf(address asset) external view returns (uint8) {
        return V2AmountUnits.decimalsOf(asset);
    }

    function toNormalized(uint256 amount, uint8 dec) external pure returns (uint256) {
        return V2AmountUnits.toNormalized(amount, dec);
    }

    function fromNormalized(uint256 amount, uint8 dec) external pure returns (uint256) {
        return V2AmountUnits.fromNormalized(amount, dec);
    }
}

contract AmountUnitsTest is Test {
    AmountUnitsHarness internal h;

    function setUp() public {
        h = new AmountUnitsHarness();
    }

    function test_ReadsNon18Decimals() public {
        assertEq(h.decimalsOf(address(new DecimalsToken(6))), 6);
        assertEq(h.decimalsOf(address(new DecimalsToken(0))), 0);
        assertEq(h.decimalsOf(address(new DecimalsToken(24))), 24);
    }

    function test_RejectsMissingOrOutOfRangeDecimals() public {
        address eoa = address(0xBEEF);
        vm.expectRevert(abi.encodeWithSelector(V2AmountUnits.UnsupportedDecimals.selector, eoa));
        h.decimalsOf(eoa);

        address noDec = address(new NoDecimalsToken());
        vm.expectRevert(abi.encodeWithSelector(V2AmountUnits.UnsupportedDecimals.selector, noDec));
        h.decimalsOf(noDec);

        address big = address(new DecimalsToken(37));
        vm.expectRevert(abi.encodeWithSelector(V2AmountUnits.UnsupportedDecimals.selector, big));
        h.decimalsOf(big);

        vm.expectRevert(abi.encodeWithSelector(V2AmountUnits.DecimalsOutOfRange.selector, uint8(37)));
        h.toNormalized(1, 37);
    }

    function test_ConvertsUsdcStyleUnits() public view {
        assertEq(h.toNormalized(1e6, 6), 1e18);
        assertEq(h.fromNormalized(1e18, 6), 1e6);
        assertEq(h.fromNormalized(1e12 - 1, 6), 0); // sub-unit dust rounds down
        assertEq(h.toNormalized(1e24, 24), 1e18);
        assertEq(h.toNormalized(1e6 - 1, 24), 0);
        assertEq(h.toNormalized(5, 18), 5);
    }

    function testFuzz_RoundTripNeverInflates(uint128 amount, uint8 dec) public view {
        dec = uint8(bound(dec, 0, 36));
        uint256 back = h.fromNormalized(h.toNormalized(amount, dec), dec);
        assertLe(back, amount);
        if (dec <= 18) assertEq(back, amount);
    }
}
