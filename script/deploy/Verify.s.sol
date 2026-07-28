// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./DeployBase.s.sol";
import "../../contracts/TruthBountyWeighted.sol";
import "../../contracts/staking.sol";
import "../../contracts/TruthBountyClaims.sol";
import "../../contracts/deployment/MigrationManager.sol";

contract Verify is DeployBase {
    function verifyDeployment(
        address _migrationManager,
        address _token,
        address _oracle,
        address _bounty,
        address _staking,
        address _claims
    ) external {
        MigrationManager mm = MigrationManager(_migrationManager);
        ITruthBountyWeighted bounty = ITruthBountyWeighted(_bounty);
        IStaking staking = IStaking(_staking);
        ITruthBountyClaims claims = ITruthBountyClaims(_claims);

        console2.log("=== Deployment Verification ===");
        bool allOk = true;

        if (_token == address(0)) { console2.log("FAIL: Token not deployed"); allOk = false; }
        if (_oracle == address(0)) { console2.log("FAIL: Oracle not deployed"); allOk = false; }
        if (_bounty == address(0)) { console2.log("FAIL: Bounty not deployed"); allOk = false; }
        if (_staking == address(0)) { console2.log("FAIL: Staking not deployed"); allOk = false; }
        if (_claims == address(0)) { console2.log("FAIL: Claims not deployed"); allOk = false; }

        try bounty.bountyToken() returns (address bt) {
            if (bt == _token) console2.log("OK: Bounty token address matches");
            else { console2.log("FAIL: Bounty token mismatch"); allOk = false; }
        } catch { console2.log("FAIL: Cannot query bounty token"); allOk = false; }

        try bounty.reputationOracle() returns (address ro) {
            if (ro == _oracle) console2.log("OK: Bounty oracle address matches");
            else { console2.log("FAIL: Bounty oracle mismatch"); allOk = false; }
        } catch { console2.log("FAIL: Cannot query oracle"); allOk = false; }

        try staking.stakingToken() returns (address st) {
            if (st == _token) console2.log("OK: Staking token address matches");
            else { console2.log("FAIL: Staking token mismatch"); allOk = false; }
        } catch { console2.log("FAIL: Cannot query staking token"); allOk = false; }

        try claims.bountyToken() returns (address ct) {
            if (ct == _token) console2.log("OK: Claims token address matches");
            else { console2.log("FAIL: Claims token mismatch"); allOk = false; }
        } catch { console2.log("FAIL: Cannot query claims token"); allOk = false; }

        if (allOk) {
            mm.verifyDeployment(true, true);
            console2.log("=== VERIFICATION PASSED ===");
        } else {
            console2.log("=== VERIFICATION FAILED ===");
        }
    }
}

interface ITruthBountyWeighted {
    function bountyToken() external view returns (address);
    function reputationOracle() external view returns (address);
}

interface IStaking {
    function stakingToken() external view returns (address);
}

interface ITruthBountyClaims {
    function bountyToken() external view returns (address);
}