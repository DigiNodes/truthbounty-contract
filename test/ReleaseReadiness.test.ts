import { expect } from "chai";
import { auditReleaseReadiness } from "../scripts/auditReleaseReadiness";
import { validateStorageLayouts } from "../scripts/validateStorageLayouts";

describe("Canonical Release Readiness & Legacy Exclusion Suite (V2-SC-040)", function () {
    it("should pass all release readiness audit checks", async function () {
        const result = await auditReleaseReadiness();
        expect(result.passed).to.be.true;
        expect(result.legacyCheck).to.be.true;
        expect(result.issues).to.be.empty;
    });

    it("should classify TruthBountyClaims as DEPRECATED", async function () {
        const result = await auditReleaseReadiness();
        expect(result.contractClassification["TruthBountyClaims.sol"]).to.equal("DEPRECATED");
    });

    it("should classify TruthBountyWeighted as TRANSITIONAL_NON_CANONICAL", async function () {
        const result = await auditReleaseReadiness();
        expect(result.contractClassification["TruthBountyWeighted.sol"]).to.equal("TRANSITIONAL_NON_CANONICAL");
    });

    it("should validate all storage layouts without error", async function () {
        await validateStorageLayouts();
    });
});
