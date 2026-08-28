/**
 * deployAll.js  —  Deploy all 3 RaceIoT contracts in a single run.
 *
 * Run from iot-rules/:
 *   npx hardhat run scripts/deployAll.js --network localhost
 *
 * Generates two ready-to-scp conf files:
 *   scripts/blockchain.conf  →  scp to pi@<PI-IP>:/etc/iot-gateway/blockchain.conf
 *   scripts/firmware.conf    →  scp to pi@<PI-IP>:/etc/iot-gateway/firmware.conf
 *
 * Optional env var:
 *   NODE_IP   IP of the Hardhat node visible to the Pi  (default: 192.168.1.6)
 */

require("dotenv").config();
const { ethers } = require("hardhat");
const fs   = require("fs");
const path = require("path");

// Update a KEY=value line in any conf/env file, preserving all other lines.
function updateKey(filePath, key, value) {
    if (!fs.existsSync(filePath)) return;
    const updated = fs.readFileSync(filePath, "utf8").split("\n")
        .map(l => l.startsWith(key + "=") ? `${key}=${value}` : l);
    fs.writeFileSync(filePath, updated.join("\n"));
    console.log(`  ✎  Updated ${path.basename(filePath)}: ${key}=${value}`);
}

function updateExportKey(filePath, key, value) {
    if (!fs.existsSync(filePath)) return;
    const updated = fs.readFileSync(filePath, "utf8").split("\n")
        .map(l => l.startsWith(`export ${key}=`) ? `export ${key}="${value}"` : l);
    fs.writeFileSync(filePath, updated.join("\n"));
    console.log(`  ✎  Updated ${path.basename(filePath)}: export ${key}="${value}"`);
}

async function main() {
    const [deployer, rpi3Device] = await ethers.getSigners();
    const deviceAddr = rpi3Device ? rpi3Device.address : deployer.address;

    console.log("==============================================");
    console.log("  Deploying ALL RaceIoT Contracts");
    console.log("==============================================");
    console.log("  Deployer :", deployer.address);
    console.log("  RPi3     :", deviceAddr);

    // ── 1. IoTAuthLog ──────────────────────────────────────────────────────────
    console.log("\n[1/3] Deploying IoTAuthLog...");
    const authLog     = await (await ethers.getContractFactory("IoTAuthLog")).deploy();
    await authLog.waitForDeployment();
    const authLogAddr = await authLog.getAddress();
    console.log("  ✅ IoTAuthLog deployed at           :", authLogAddr);

    // ── 2. CommitRevealOTP ─────────────────────────────────────────────────────
    console.log("\n[2/3] Deploying CommitRevealOTP...");
    const commitReveal     = await (await ethers.getContractFactory("CommitRevealOTP")).deploy();
    await commitReveal.waitForDeployment();
    const commitRevealAddr = await commitReveal.getAddress();
    console.log("  ✅ CommitRevealOTP deployed at      :", commitRevealAddr);

    // ── 3. FirmwareMetadataStore ───────────────────────────────────────────────
    console.log("\n[3/3] Deploying FirmwareMetadataStore...");
    const firmwareMeta     = await (await ethers.getContractFactory("FirmwareMetadataStore")).deploy();
    await firmwareMeta.waitForDeployment();
    const firmwareMetaAddr = await firmwareMeta.getAddress();
    console.log("  ✅ FirmwareMetadataStore deployed at:", firmwareMetaAddr);

    // ── Authorize RPi3 device on auth contracts ────────────────────────────────
    if (rpi3Device) {
        console.log("\n  Authorizing RPi3 device...");
        await (await authLog.authorizeDevice(rpi3Device.address)).wait();
        console.log("  ✅ IoTAuthLog    authorized:", rpi3Device.address);
        await (await commitReveal.authorizeDevice(rpi3Device.address)).wait();
        console.log("  ✅ CommitReveal  authorized:", rpi3Device.address);
    }

    // ── Write conf files locally (works on any machine) ───────────────────────
    const NODE_IP  = process.env.NODE_IP || "192.168.1.6";
    const bcConf   = path.join(__dirname, "blockchain.conf");
    const fwConf   = path.join(__dirname, "firmware.conf");

    fs.writeFileSync(bcConf, [
        "BLOCKCHAIN_RPC_URL=http://"        + NODE_IP + ":8545",
        "BLOCKCHAIN_AUTHLOG_CONTRACT="      + authLogAddr,
        "BLOCKCHAIN_COMMITREVEAL_CONTRACT=" + commitRevealAddr,
        "BLOCKCHAIN_DEVICE_ADDR="           + deviceAddr,
        "BLOCKCHAIN_CHAIN_ID=1337",
    ].join("\n") + "\n");
    console.log("\n  ✎  Written: " + bcConf);

    fs.writeFileSync(fwConf, [
        "FIRMWARE_CONTRACT="                + firmwareMetaAddr,
        "FIRMWARE_HSM_PUBKEY=/etc/googlehsmkey/hsm-pubkey.pem",
        "FIRMWARE_CA_CERT=/etc/ssl/certs/ca-certificates.crt",
        "FIRMWARE_TARGET=/usr/bin/iot-gateway",
        "FIRMWARE_STAGING=/tmp/iot-gateway.staging",
        "FIRMWARE_BACKUP=/usr/bin/iot-gateway.bak",
        "FIRMWARE_CHECK_INTERVAL=3600",
    ].join("\n") + "\n");
    console.log("  ✎  Written: " + fwConf);

    // Also update source-tree files when running on the main dev PC
    const root = path.resolve(__dirname, "../..");
    updateKey(path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/blockchain.conf"),
        "BLOCKCHAIN_AUTHLOG_CONTRACT", authLogAddr);
    updateKey(path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/blockchain.conf"),
        "BLOCKCHAIN_DEVICE_ADDR", deviceAddr);
    updateKey(path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/firmware.conf"),
        "FIRMWARE_CONTRACT", firmwareMetaAddr);
    updateKey(path.join(__dirname, "../users.env"),       "CONTRACT_ADDR", firmwareMetaAddr);
    updateExportKey(path.join(root, ".env.secrets"),      "CONTRACT_ADDR", firmwareMetaAddr);

    // ── Summary ────────────────────────────────────────────────────────────────
    console.log("\n════════════════════════════════════════════════════════════");
    console.log("  ALL 3 CONTRACTS DEPLOYED");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  1. IoTAuthLog            :", authLogAddr);
    console.log("  2. CommitRevealOTP       :", commitRevealAddr);
    console.log("  3. FirmwareMetadataStore :", firmwareMetaAddr);
    console.log("");
    console.log("  Copy both conf files to the Pi:");
    console.log("  scp " + bcConf + " pi@<PI-IP>:/etc/iot-gateway/blockchain.conf");
    console.log("  scp " + fwConf + " pi@<PI-IP>:/etc/iot-gateway/firmware.conf");
    console.log("════════════════════════════════════════════════════════════");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
