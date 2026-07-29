export const TRUTH_BOUNTY_ABI = [
  "event ClaimCreated(uint256 indexed claimId, address indexed submitter, string content, uint256 verificationWindowEnd)",
  "event VoteCast(uint256 indexed claimId, address indexed verifier, bool support, uint256 rawStake, uint256 effectiveStake, uint256 reputationScore)",
  "event ClaimSettled(uint256 indexed claimId, bool passed, uint256 totalWeightedFor, uint256 totalWeightedAgainst, uint256 totalRewards, uint256 totalSlashed)",
  "event RewardsDistributed(uint256 indexed claimId, address indexed verifier, uint256 amount)",
  "event StakeSlashed(uint256 indexed claimId, address indexed verifier, uint256 amount)",
  "event StakeDeposited(address indexed verifier, uint256 amount)",
  "event StakeWithdrawn(address indexed verifier, uint256 amount)",
  "event ClaimWiped(uint256 indexed claimId, address indexed admin, string reason)",
];

export const REPUTATION_DECAY_ABI = [
  "event ReputationUpdated(address indexed user, uint256 oldReputation, uint256 newReputation, uint256 timestamp)",
  "event ActivityRecorded(address indexed user, uint256 timestamp)",
  "event ReputationDecayed(address indexed verifier, uint256 previousScore, uint256 newScore)",
  "event DecayConfigUpdated(uint256 decayInterval, uint256 decayPercentage, uint256 minimumReputation, bool enabled)",
];

export const REPUTATION_SNAPSHOT_ABI = [
  "event ReputationSnapshotRecorded(address indexed user, uint256 reputationScore, uint256 timestamp)",
  "event ReputationStalenessValidated(address indexed user, uint256 expectedReputation, uint256 actualReputation, uint256 maxDrift)",
];

export interface KnownEvent {
  contract: string;
  event: string;
  signature: string;
  abi: string;
}

export function getEventSignatures(): KnownEvent[] {
  return [
    ...TRUTH_BOUNTY_ABI.map((abi) => ({
      contract: "TruthBountyWeighted",
      event: extractEventName(abi),
      signature: abi,
      abi,
    })),
    ...REPUTATION_DECAY_ABI.map((abi) => ({
      contract: "ReputationDecay",
      event: extractEventName(abi),
      signature: abi,
      abi,
    })),
    ...REPUTATION_SNAPSHOT_ABI.map((abi) => ({
      contract: "ReputationSnapshot",
      event: extractEventName(abi),
      signature: abi,
      abi,
    })),
  ];
}

function extractEventName(abi: string): string {
  const match = abi.match(/^event\s+(\w+)/);
  if (!match) throw new Error(`Invalid event ABI: ${abi}`);
  return match[1];
}
