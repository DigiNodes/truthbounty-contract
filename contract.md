📘 TruthBounty Smart Contract Architecture
📚 Overview

The TruthBounty system is composed of multiple smart contracts that work together to enable decentralized claim validation, staking, reward distribution, and reputation tracking.

The architecture is modular to ensure:

Separation of concerns
Upgradeability
Governance control
Transparent data flow between contracts

Each contract has a clearly defined responsibility and interacts with others through well-structured interfaces.

🧩 Core Contracts
1. Staking Contract

The Staking Contract is responsible for managing user deposits (stakes) into the system.

Responsibilities:
Accept and lock user tokens
Track individual user stakes
Provide staking weight for decision-making processes
Role in the System:

Staking acts as a signal of commitment and credibility. Users with higher stakes may have more influence in claim validation or reward distribution.

Interactions:
Sends staking data to the Claim Settlement Contract for validation logic
Provides stake weight to the Reward Contract for reward calculations
2. Claim Settlement Contract

This is the core logic contract of the TruthBounty system.

Responsibilities:
Handle submission of claims
Coordinate validation processes
Determine claim outcomes (valid / invalid)
Role in the System:

It acts as the decision engine, ensuring that claims are processed fairly and consistently.

Interactions:
Receives stake context from the Staking Contract
Queries the Reputation Anchor for user credibility
Triggers payouts in the Reward Contract once a claim is resolved
3. Reward Contract

The Reward Contract manages all incentive distribution within the system.

Responsibilities:
Calculate rewards based on:
Claim outcomes
Stake weight
Distribute tokens to eligible users
Role in the System:

It ensures that participants are fairly incentivized for honest and valuable contributions.

Interactions:
Receives execution triggers from the Claim Settlement Contract
Uses staking data from the Staking Contract
Transfers rewards to users
4. Reputation Anchor

The Reputation Anchor maintains a persistent record of user credibility.

Responsibilities:
Track user performance over time
Update reputation scores based on:
Claim accuracy
Participation behavior
Role in the System:

It introduces a trust layer that improves system integrity by rewarding honest actors and penalizing malicious behavior.

Interactions:
Supplies reputation scores to the Claim Settlement Contract
Updates user reputation after claim outcomes
5. Governance Contract

The Governance Contract enables decentralized control of the protocol.

Responsibilities:
Manage protocol parameters (e.g., reward rates, staking limits)
Control system rules and logic updates
Facilitate proposal creation and voting
Role in the System:

It ensures the system evolves through DAO-driven decisions, rather than centralized control.

Interactions:
Updates configuration across:
Staking Contract
Reward Contract
Claim Settlement Contract
Reputation Anchor
🔄 Data Flow Between Contracts

The system follows a structured interaction flow:

User Participation
A user stakes tokens via the Staking Contract
The same or another user submits a claim via the Claim Settlement Contract
Validation Phase
Claim Settlement retrieves:
Stake weight from the Staking Contract
Reputation score from the Reputation Anchor
The claim is evaluated based on these inputs
Resolution
The Claim Settlement Contract determines the outcome
Reward Distribution
If valid, the Reward Contract distributes incentives
Rewards are calculated using stake weight and participation
Reputation Update
The Reputation Anchor updates user scores based on the result