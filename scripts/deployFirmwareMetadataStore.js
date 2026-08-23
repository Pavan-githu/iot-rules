/**
 * deployFirmwareMetadataStore.js
 * -------------------------------
 * Deploys FirmwareMetadataStore.sol to the localhost Hardhat node.
 *
 * Usage:
 *   cd iot-rules
 *   source ../.env.secrets        # sets RPC_URL and SIGNER_KEY
 *   npx hardhat run scripts/deployFirmwareMetadataStore.js --network localhost
 *
 * After deployment, copy the printed CONTRACT_ADDR and update .env.secrets.
 */

require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  Deploying FirmwareMetadataStore");
  console.log("=".repeat(60));
  console.log("  Deployer  :", deployer.address);
  console.log("  Network   :", (await ethers.provider.getNetwork()).name);
  console.log("  ChainId   :", (await ethers.provider.getNetwork()).chainId.toString());

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("  Balance   :", ethers.formatEther(balance), "ETH");
  console.log();

  const Factory  = await ethers.getContractFactory("FirmwareMetadataStore");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const addr = await contract.getAddress();

  console.log("  ✔  Contract deployed at:", addr);
  console.log();
  console.log("  Update .env.secrets:");
  console.log(`  export CONTRACT_ADDR="${addr}"`);
  console.log();
  console.log("  Owner (can call writeFirmwareMetadata):", deployer.address);
  console.log("  This must match the address derived from SIGNER_KEY.");
  console.log("=".repeat(60));
}

main().catch((err) => { console.error(err); process.exit(1); });
