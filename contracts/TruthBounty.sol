// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TruthBounty is ERC20, Ownable {
    struct Bounty {
        address creator;
        string ipfsHash; // Link to the truth verification task details
        uint256 rewardAmount;
        bool resolved;
        address verifier;
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public bountyCount;

    mapping(address => uint256) public stakes;
    uint256 public totalStaked;

    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 rewardAmount);
    event BountyResolved(uint256 indexed bountyId, address indexed verifier, uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    constructor() ERC20("TruthBounty", "BOUNTY") Ownable(msg.sender) {
        _mint(msg.sender, 10_000_000 * 10 ** decimals()); // Initial supply
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Staking Mechanism
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        _transfer(msg.sender, address(this), amount);
        stakes[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Insufficient stake");
        stakes[msg.sender] -= amount;
        totalStaked -= amount;
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    // Bounty Management
    function createBounty(string calldata ipfsHash, uint256 rewardAmount) external {
        require(rewardAmount > 0, "Reward must be > 0");
        _transfer(msg.sender, address(this), rewardAmount);

        bounties[bountyCount] = Bounty({
            creator: msg.sender,
            ipfsHash: ipfsHash,
            rewardAmount: rewardAmount,
            resolved: false,
            verifier: address(0)
        });

        emit BountyCreated(bountyCount, msg.sender, rewardAmount);
        bountyCount++;
    }

    function resolveBounty(uint256 bountyId, address verifier) external onlyOwner {
        Bounty storage bounty = bounties[bountyId];
        require(!bounty.resolved, "Already resolved");
        require(verifier != address(0), "Invalid verifier");

        bounty.resolved = true;
        bounty.verifier = verifier;

        _transfer(address(this), verifier, bounty.rewardAmount);

        emit BountyResolved(bountyId, verifier, bounty.rewardAmount);
    }
}