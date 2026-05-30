// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/TruthBountyWeighted.sol";
import "../../contracts/MockReputationOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("UnitTestToken", "UTT") {
        _mint(msg.sender, type(uint128).max);
    }
}

contract TimingHandler is Test {
    TruthBountyWeighted public truthBounty;
    MockERC20 public token;
    MockReputationOracle public oracle;

    constructor() {
        oracle = new MockReputationOracle();
        token = new MockERC20();

        truthBounty = new TruthBountyWeighted(
            address(token),
            address(oracle),
            msg.sender,
            msg.sender // Governance controller
        );
    }

    function setConfirmationDelay(uint256 newDelay) public {
        vm.prank(msg.sender); // Admin/Governance
        try truthBounty.setConfirmationDelay(newDelay) {} catch {}
    }
    
    function setVerificationWindowDuration(uint256 newDuration) public {
        vm.prank(msg.sender); // Admin/Governance
        try truthBounty.setVerificationWindowDuration(newDuration) {} catch {}
    }
}

contract TimingInvariantTest is StdInvariant, Test {
    TimingHandler public handler;
    TruthBountyWeighted public truthBounty;

    function setUp() public {
        handler = new TimingHandler();
        truthBounty = handler.truthBounty();

        targetContract(address(handler));
    }

    /**
     * @notice Invariant: confirmationDelay is always >= 5 minutes for reorg protection
     */
    function invariant_ConfirmationDelaySufficientForReorgs() public view {
        uint256 delay = truthBounty.confirmationDelay();
        assertGe(delay, 5 minutes, "confirmationDelay must be at least 5 minutes");
    }
    
    /**
     * @notice Invariant: verificationWindowDuration is always >= 1 days
     */
    function invariant_VerificationWindowDurationSufficient() public view {
        uint256 duration = truthBounty.verificationWindowDuration();
        assertGe(duration, 1 days, "verificationWindowDuration must be at least 1 day");
    }
}
