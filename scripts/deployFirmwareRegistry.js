/**
 * deployFirmwareRegistry.js
 * --------------------------
 * Deploys IoTFirmwareRegistry.sol to the network configured in hardhat.config.js.
 *
 * Usage:
 *   cd iot-rules
 *   npx hardhat run scripts/deployFirmwareRegistry.js --network amoy
 *
 * After deployment, copy the printed contract address and set:
 *   export CONTRACT_ADDR="0x..."
 * before running deploy_firmware.py
 */

require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // ── Deployer info ──────────────────────────────────────────────────────────
  const [deployer] = await ethers.getSigners();
  console.log("=".repeat(60));
  console.log("  Deploying IoTFirmwareRegistry");
  console.log("=".repeat(60));
  console.log("  Deployer (build server wallet) :", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(
    "  Deployer balance                :",
    ethers.formatEther(balance),
    "MATIC"
  );
  console.log();

  if (balance === 0n) {
    console.error(
      "ERROR: Deployer wallet has 0 MATIC.\n" +
      "Fund it from the Polygon Amoy faucet:\n" +
      "  https://faucet.polygon.technology/"
    );
    process.exit(1);
  }

  // ── Deploy ─────────────────────────────────────────────────────────────────
  console.log("  Deploying contract...");
  const Factory  = await ethers.getContractFactory("IoTFirmwareRegistry");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  console.log("  Contract deployed at            :", contractAddress);

  // ── Verify owner ───────────────────────────────────────────────────────────
  const owner = await contract.owner();
  console.log("  Owner (must match deployer)     :", owner);
  console.log("  Firmware count (should be 0)    :", (await contract.getFirmwareCount()).toString());

  // ── Print export command ───────────────────────────────────────────────────
  console.log();
  console.log("=".repeat(60));
  console.log("  NEXT STEP — copy and run this:");
  console.log();
  console.log(`  export CONTRACT_ADDR="${contractAddress}"`);
  console.log();
  console.log("  Then run the firmware pipeline:");
  console.log("  python3 scripts/deploy_firmware.py");
  console.log("=".repeat(60));

  // ── Polygonscan link ───────────────────────────────────────────────────────
  console.log();
  console.log(
    "  View on Polygonscan:\n" +
    `  https://amoy.polygonscan.com/address/${contractAddress}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
