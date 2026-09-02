import { ethers } from "hardhat";
import type { ClaimRegistry } from "../typechain-types";

/**
 * Deploy ClaimRegistry with its required ParameterVersionRegistry (sc-014).
 */
export async function deployClaimRegistry(adminAddress: string): Promise<ClaimRegistry> {
    const ParamFactory = await ethers.getContractFactory("ParameterVersionRegistry");
    const paramRegistry = await ParamFactory.deploy(adminAddress, adminAddress);
    await paramRegistry.waitForDeployment();

    const ClaimRegistryFactory = await ethers.getContractFactory("ClaimRegistry");
    const registry = (await ClaimRegistryFactory.deploy(
        adminAddress,
        await paramRegistry.getAddress()
    )) as ClaimRegistry;
    await registry.waitForDeployment();

    return registry;
}
