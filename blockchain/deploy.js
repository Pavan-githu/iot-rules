/**
 * deploy.js  –  Deploys all 3 RaceIoT contracts in one shot:
 *                 1. IoTAuthLog.sol            (audit log + global lockout)
 *                 2. CommitRevealOTP.sol       (commit-reveal OTP second factor)
 *                 3. FirmwareMetadataStore.sol (firmware metadata + OEM→Fleet approval)
 *
 * Usage:
 *   npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
 *   npx hardhat compile
 *   npx hardhat node --hostname 0.0.0.0          (terminal 1)
 *   npx hardhat run blockchain/deploy.js --network localhost  (terminal 2)
 *
 * Optional env vars:
 *   NODE_IP   IP of the Hardhat node visible to the Pi  (default: 192.168.1.6)
 *
 * After deployment copy the printed config block into:
 *   /etc/iot-gateway/blockchain.conf  on the RPi3
 */

const { ethers } = require("hardhat");
const fs   = require("fs");
const path = require("path");

function updateKey(filePath, key, value) {
    if (!fs.existsSync(filePath)) return;
    const lines   = fs.readFileSync(filePath, "utf8").split("\n");
    const updated = lines.map(l =>
        l.startsWith(key + "=") ? `${key}=${value}` : l
    );
    fs.writeFileSync(filePath, updated.join("\n"));
    console.log(`  ✎  Updated ${path.basename(filePath)}: ${key}=${value}`);
}

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
    const [deployer, rpi3Device] = await ethers.getSigners();
    const deviceAddr = rpi3Device ? rpi3Device.address : deployer.address;

    console.log("==============================================");
    console.log("  Deploying RaceIoT Blockchain Contracts");
    console.log("==============================================");
    console.log("Deployer (owner) :", deployer.address);
    console.log("RPi3 device acct :", deviceAddr);

    // ── 1. IoTAuthLog ──────────────────────────────────────────────────────────
    console.log("\n[1/2] Deploying IoTAuthLog...");
    const authLog     = await (await ethers.getContractFactory("IoTAuthLog")).deploy();
    await authLog.waitForDeployment();
    const authLogAddr = await authLog.getAddress();
    console.log("  ✅ IoTAuthLog deployed at           :", authLogAddr);

    // ── 2. CommitRevealOTP ─────────────────────────────────────────────────────
    console.log("\n[2/2] Deploying CommitRevealOTP...");
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
        console.log("\nAuthorizing RPi3 device on auth contracts...");
        let tx = await authLog.authorizeDevice(rpi3Device.address);
        await tx.wait();
        console.log("  ✅ IoTAuthLog    authorized device:", rpi3Device.address);

        tx = await commitReveal.authorizeDevice(rpi3Device.address);
        await tx.wait();
        console.log("  ✅ CommitReveal  authorized device:", rpi3Device.address);
    } else {
        console.log("\nℹ  Single signer — deployer is already authorized on auth contracts.");
    }

    // ── Write blockchain.conf ──────────────────────────────────────────────────
    const NODE_IP   = process.env.NODE_IP || "172.20.10.3";
    const localConf = path.join(__dirname, "blockchain.conf");
    fs.writeFileSync(localConf, [
        "BLOCKCHAIN_RPC_URL=http://"        + NODE_IP + ":8545",
        "BLOCKCHAIN_AUTHLOG_CONTRACT="      + authLogAddr,
        "BLOCKCHAIN_COMMITREVEAL_CONTRACT=" + commitRevealAddr,
        "BLOCKCHAIN_DEVICE_ADDR="           + deviceAddr,
        "BLOCKCHAIN_CHAIN_ID=1337",
    ].join("\n") + "\n");

    // Write firmware.conf locally for scp to Pi
    const fwConf = path.join(__dirname, "firmware.conf");
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
    console.log("\n  ✎  Written: " + localConf);

    // Update source-tree blockchain.conf baked into the Pi image
    const srcConf = path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/blockchain.conf");
    updateKey(srcConf, "BLOCKCHAIN_AUTHLOG_CONTRACT",      authLogAddr);
    updateKey(srcConf, "BLOCKCHAIN_COMMITREVEAL_CONTRACT", commitRevealAddr);
    updateKey(srcConf, "BLOCKCHAIN_DEVICE_ADDR",           deviceAddr);

    // Also update source-tree firmware.conf and env files if on the main dev PC
    const srcFwConf  = path.resolve(__dirname,
        "../../sources/meta-userapp-package/recipes-apps/iot-gateway/files/firmware.conf");
    const envSecrets = path.resolve(__dirname, "../../.env.secrets");
    const usersEnv   = path.resolve(__dirname, "../users.env");
    updateKey(srcFwConf, "FIRMWARE_CONTRACT", firmwareMetaAddr);
    updateKey(usersEnv,  "CONTRACT_ADDR",     firmwareMetaAddr);
    updateExportKey(envSecrets, "CONTRACT_ADDR", firmwareMetaAddr);

    // ── Summary ────────────────────────────────────────────────────────────────
    console.log("\n════════════════════════════════════════════════════════════");
    console.log("  ALL 3 CONTRACTS DEPLOYED");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  1. IoTAuthLog            :", authLogAddr);
    console.log("  2. CommitRevealOTP       :", commitRevealAddr);
    console.log("  3. FirmwareMetadataStore :", firmwareMetaAddr);
    console.log("");
    console.log("  Copy both conf files to the Pi:");
    console.log("  scp " + localConf + " pi@<PI-IP>:/etc/iot-gateway/blockchain.conf");
    console.log("  scp " + fwConf   + " pi@<PI-IP>:/etc/iot-gateway/firmware.conf");
    console.log("════════════════════════════════════════════════════════════");
}

main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
});
