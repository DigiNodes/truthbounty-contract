// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TruthBountyToken is ERC20 {
    address public owner;
    address public settlementContract;

    uint256 public slashPercentage; // e.g. 10 = 10%

    mapping(address => uint256) public verifierStake;

    event StakeDeposited(address indexed verifier, uint256 amount);
    event StakeWithdrawn(address indexed verifier, uint256 amount);
    event VerifierSlashed(
        address indexed verifier,
        uint256 slashedAmount,
        uint256 remainingStake
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == settlementContract, "Unauthorized slashing");
        _;
    }

    constructor() ERC20("TruthBounty", "BOUNTY") {
        owner = msg.sender;
        slashPercentage = 10; // default 10%
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }


    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }


    function stake(uint256 amount) external {
        require(amount > 0, "Invalid amount");

        _transfer(msg.sender, address(this), amount);
        verifierStake[msg.sender] += amount;

        emit StakeDeposited(msg.sender, amount);
    }

    function withdrawStake(uint256 amount) external {
        require(verifierStake[msg.sender] >= amount, "Insufficient stake");

        verifierStake[msg.sender] -= amount;
        _transfer(address(this), msg.sender, amount);

        emit StakeWithdrawn(msg.sender, amount);
    }


    function slashVerifier(address verifier) external onlySettlement {
        uint256 stake = verifierStake[verifier];
        require(stake > 0, "No stake to slash");

        uint256 slashedAmount = (stake * slashPercentage) / 100;
        verifierStake[verifier] -= slashedAmount;

        _burn(address(this), slashedAmount);

        emit VerifierSlashed(
            verifier,
            slashedAmount,
            verifierStake[verifier]
        );
    }


    function setSlashPercentage(uint256 percentage) external onlyOwner {
        require(percentage <= 100, "Invalid percentage");
        slashPercentage = percentage;
    }

    function setSettlementContract(address settlement) external onlyOwner {
        settlementContract = settlement;
    }
}
