import { RewardsService, createRewardsService } from "./rewards.service";

/**
 * RewardsController
 *
 * Exposes reward operations as callable handler methods.
 * Designed to be mounted in a NestJS or Express app.
 *
 * POST /rewards/claims          — createClaim
 * GET  /rewards/claims/:id      — getClaim
 * GET  /rewards/claims/:id/result — getSettlementResult
 * GET  /rewards/votes/:id/:addr — getVote
 * POST /rewards/claims/:id/settle  — settleClaim
 * POST /rewards/claims/:id/claim   — claimRewards
 * GET  /rewards/stake/:addr     — getVerifierStake
 */
export class RewardsController {
  private service: RewardsService;

  constructor(service?: RewardsService) {
    this.service = service ?? createRewardsService();
  }

  async createClaim(content: string) {
    if (!content?.trim()) throw new Error("content is required");
    return this.service.createClaim(content);
  }

  async getClaim(claimId: string) {
    this._requireClaimId(claimId);
    return this.service.getClaim(claimId);
  }

  async getSettlementResult(claimId: string) {
    this._requireClaimId(claimId);
    return this.service.getSettlementResult(claimId);
  }

  async getVote(claimId: string, verifier: string) {
    this._requireClaimId(claimId);
    if (!verifier) throw new Error("verifier address is required");
    return this.service.getVote(claimId, verifier);
  }

  async settleClaim(claimId: string) {
    this._requireClaimId(claimId);
    return this.service.settleClaim(claimId);
  }

  async claimRewards(claimId: string) {
    this._requireClaimId(claimId);
    return this.service.claimRewards(claimId);
  }

  async getVerifierStake(verifier: string) {
    if (!verifier) throw new Error("verifier address is required");
    return this.service.getVerifierStake(verifier);
  }

  private _requireClaimId(claimId: string) {
    if (claimId === undefined || claimId === null || claimId === "") {
      throw new Error("claimId is required");
    }
  }
}
