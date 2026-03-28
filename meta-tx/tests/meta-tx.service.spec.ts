import { MetaTxService } from "../meta-tx.service";

describe("MetaTxService", () => {
  const service = new MetaTxService();

  it("should verify signature and relay transaction", async () => {
    const fakeSig = "0x123";
    const fakeRequest = "transfer to 0xabc amount 10";
    // Mock ethers verifyMessage
    jest.spyOn(require("ethers").utils, "verifyMessage").mockReturnValue("0xUser");

    await expect(service.relayTransaction(fakeSig, fakeRequest)).resolves.not.toThrow();
  });
});
