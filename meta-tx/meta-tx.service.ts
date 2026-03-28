import { ethers } from "ethers";

export class MetaTxService {
  async relayTransaction(userSignature: string, requestData: string) {
    // Verify user signature
    const signer = ethers.utils.verifyMessage(requestData, userSignature);

    // Submit transaction via relayer wallet
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const relayer = new ethers.Wallet(process.env.RELAYER_KEY!, provider);

    const contract = new ethers.Contract(
      process.env.CONTRACT_ADDRESS!,
      require("./abi/MetaTxExample.json"),
      relayer
    );

    return contract.executeMetaTx(requestData, userSignature);
  }
}
