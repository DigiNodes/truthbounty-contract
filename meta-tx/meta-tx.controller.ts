import { Controller, Post, Body } from "@nestjs/common";
import { MetaTxService } from "./meta-tx.service";

@Controller("meta-tx")
export class MetaTxController {
  constructor(private readonly service: MetaTxService) {}

  @Post("relay")
  async relay(@Body("signature") signature: string, @Body("requestData") requestData: string) {
    return this.service.relayTransaction(signature, requestData);
  }
}
