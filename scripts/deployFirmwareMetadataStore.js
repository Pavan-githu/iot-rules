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
const fs   = require("fs");
const path = require("path");

// Replace a KEY=value line in a conf/env file, preserving all other lines.
function updateKey(filePath, key, value) {
  if (!fs.existsSync(filePath)) return;
  const lines   = fs.readFileSync(filePath, "utf8").split("\n");
  const updated = lines.map(l =>
    l.startsWith(key + "=") ? `${key}=${value}` : l
  );
  fs.writeFileSync(filePath, updated.join("\n"));
  console.log(`  ✎  Updated ${path.basename(filePath)}: ${key}=${value}`);
}

// Replace `export KEY="..."` lines in a shell env file.
function updateExportKey(filePath, key, value) {
  if (!fs.existsSync(filePath)) return;
  const lines   = fs.readFileSync(filePath, "utf8").split("\n");
  const updated = lines.map(l =>
    l.startsWith(`export ${key}=`) ? `export ${key}="${value}"` : l
  );
  fs.writeFileSync(filePath, updated.join("\n"));
  console.log(`  ✎  Updated ${path.basename(filePath)}: export ${key}="${value}"`);
}

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

  // ── Write firmware.conf locally (works on any machine) ────────────────────
  const localConf = path.join(__dirname, "firmware.conf");
  fs.writeFileSync(localConf, [
    "FIRMWARE_CONTRACT="          + addr,
    "FIRMWARE_HSM_PUBKEY=/etc/googlehsmkey/hsm-pubkey.pem",
    "FIRMWARE_CA_CERT=/etc/ssl/certs/ca-certificates.crt",
    "FIRMWARE_TARGET=/usr/bin/iot-gateway",
    "FIRMWARE_STAGING=/tmp/iot-gateway.staging",
    "FIRMWARE_BACKUP=/usr/bin/iot-gateway.bak",
    "FIRMWARE_CHECK_INTERVAL=3600",
  ].join("\n") + "\n");
  console.log("  ✎  Written: " + localConf);

  // Also update source-tree files when running on the main dev PC
  const root     = path.resolve(__dirname, "../..");
  const iotRules = path.resolve(__dirname, "..");
  const srcConf  = path.resolve(__dirname,
      "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/firmware.conf");
  updateKey(srcConf,                                 "FIRMWARE_CONTRACT", addr);
  updateKey(path.join(iotRules, "users.env"),        "CONTRACT_ADDR",     addr);
  updateExportKey(path.join(root, ".env.secrets"),   "CONTRACT_ADDR",     addr);
  console.log();

  console.log("  Copy firmware.conf to the Pi:");
  console.log("  scp " + localConf + " pi@<PI-IP>:/etc/iot-gateway/firmware.conf");
  console.log();
  console.log("  Owner (can call writeFirmwareMetadata):", deployer.address);
  console.log("  This must match the address derived from SIGNER_KEY.");
  console.log("=".repeat(60));
}

main().catch((err) => { console.error(err); process.exit(1); });
