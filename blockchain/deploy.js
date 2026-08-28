/**
 * deploy.js  –  Hardhat deployment script for:
 *                 1. IoTAuthLog.sol           (audit log + global lockout)
 *                 2. CommitRevealOTP.sol      (commit-reveal second factor)
 *                 3. FirmwareMetadataStore.sol (firmware metadata on-chain store)
 *
 * Usage:
 *   npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
 *   npx hardhat compile
 *   npx hardhat node                                         (terminal 1)
 *   npx hardhat run deploy.js --network localhost            (terminal 2)
 *   npx hardhat run deploy.js --network sepolia              (testnet)
 *
 * After deployment copy the printed config block into:
 *   /etc/iot-gateway/blockchain.conf  on the RPi3
 */

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

async function main() {
    const [deployer, rpi3Device] = await ethers.getSigners();
    const deviceAddr = rpi3Device ? rpi3Device.address : deployer.address;

    console.log("==============================================");
    console.log("  Deploying RaceIoT Blockchain Contracts");
    console.log("==============================================");
    console.log("Deployer (owner) :", deployer.address);
    console.log("RPi3 device acct :", deviceAddr);

    // ── 1. Deploy IoTAuthLog (audit log + global lockout) ─────────────────────
    console.log("\n[1/2] Deploying IoTAuthLog...");
    const IoTAuthLog    = await ethers.getContractFactory("IoTAuthLog");
    const authLog       = await IoTAuthLog.deploy();
    await authLog.waitForDeployment();
    const authLogAddr   = await authLog.getAddress();
    console.log("  ✅ IoTAuthLog deployed at      :", authLogAddr);

    // ── 2. Deploy CommitRevealOTP (commit-reveal second factor) ───────────────
    console.log("\n[2/2] Deploying CommitRevealOTP...");
    const CommitReveal  = await ethers.getContractFactory("CommitRevealOTP");
    const commitReveal  = await CommitReveal.deploy();
    await commitReveal.waitForDeployment();
    const commitRevealAddr = await commitReveal.getAddress();
    console.log("  ✅ CommitRevealOTP deployed at :", commitRevealAddr);

    // ── Authorize the RPi3 device on both contracts ────────────────────────────
    if (rpi3Device) {
        console.log("\nAuthorizing RPi3 device on both contracts...");

        let tx = await authLog.authorizeDevice(rpi3Device.address);
        await tx.wait();
        console.log("  ✅ IoTAuthLog    authorized device:", rpi3Device.address);

        tx = await commitReveal.authorizeDevice(rpi3Device.address);
        await tx.wait();
        console.log("  ✅ CommitReveal  authorized device:", rpi3Device.address);
    } else {
        console.log("\nℹ  Single signer – deployer is already authorized on both contracts.");
    }

    // ── Write blockchain.conf locally (works on any machine) ──────────────────
    const NODE_IP  = process.env.NODE_IP || "192.168.1.6";
    const localConf = path.join(__dirname, "blockchain.conf");
    fs.writeFileSync(localConf, [
        "BLOCKCHAIN_RPC_URL=http://" + NODE_IP + ":8545",
        "BLOCKCHAIN_AUTHLOG_CONTRACT=" + authLogAddr,
        "BLOCKCHAIN_DEVICE_ADDR="      + deviceAddr,
        "BLOCKCHAIN_CHAIN_ID=1337",
    ].join("\n") + "\n");
    console.log("\n  ✎  Written: " + localConf);

    // Also update source-tree copy when running on the main dev PC
    const srcConf = path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/blockchain.conf");
    updateKey(srcConf, "BLOCKCHAIN_AUTHLOG_CONTRACT", authLogAddr);
    updateKey(srcConf, "BLOCKCHAIN_DEVICE_ADDR",      deviceAddr);

    // ── Print summary ─────────────────────────────────────────────────────────
    console.log("\n");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  STEP 1 COMPLETE");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  IoTAuthLog      :", authLogAddr);
    console.log("  CommitRevealOTP :", commitRevealAddr);
    console.log("  RPi3 device     :", deviceAddr);
    console.log("");
    console.log("  Copy blockchain.conf to the Pi:");
    console.log("  scp " + localConf + " pi@<PI-IP>:/etc/iot-gateway/blockchain.conf");
    console.log("");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  STEP 2 — run from iot-rules/ to deploy FirmwareMetadataStore:");
    console.log("  npx hardhat run scripts/deployFirmwareMetadataStore.js --network localhost");
    console.log("════════════════════════════════════════════════════════════");
}

main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
});
