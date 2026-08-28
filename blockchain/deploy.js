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

async function main() {
    const [deployer, rpi3Device] = await ethers.getSigners();
    const deviceAddr = rpi3Device ? rpi3Device.address : deployer.address;

    console.log("==============================================");
    console.log("  Deploying RaceIoT Blockchain Contracts");
    console.log("==============================================");
    console.log("Deployer (owner) :", deployer.address);
    console.log("RPi3 device acct :", deviceAddr);

    // ── 1. Deploy IoTAuthLog (audit log + global lockout) ─────────────────────
    console.log("\n[1/3] Deploying IoTAuthLog...");
    const IoTAuthLog    = await ethers.getContractFactory("IoTAuthLog");
    const authLog       = await IoTAuthLog.deploy();
    await authLog.waitForDeployment();
    const authLogAddr   = await authLog.getAddress();
    console.log("  ✅ IoTAuthLog deployed at      :", authLogAddr);

    // ── 2. Deploy CommitRevealOTP (commit-reveal second factor) ───────────────
    console.log("\n[2/3] Deploying CommitRevealOTP...");
    const CommitReveal  = await ethers.getContractFactory("CommitRevealOTP");
    const commitReveal  = await CommitReveal.deploy();
    await commitReveal.waitForDeployment();
    const commitRevealAddr = await commitReveal.getAddress();
    console.log("  ✅ CommitRevealOTP deployed at :", commitRevealAddr);

    // ── 3. Deploy FirmwareMetadataStore (firmware metadata on-chain store) ──────
    console.log("\n[3/3] Deploying FirmwareMetadataStore...");
    const FirmwareMetadataStore  = await ethers.getContractFactory("FirmwareMetadataStore");
    const firmwareMeta           = await FirmwareMetadataStore.deploy();
    await firmwareMeta.waitForDeployment();
    const firmwareMetaAddr       = await firmwareMeta.getAddress();
    console.log("  ✅ FirmwareMetadataStore deployed at:", firmwareMetaAddr);

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

    // ── Print the config blocks for the RPi3 ─────────────────────────────────
    const NODE_IP = process.env.NODE_IP || "<NODE-IP>";
    console.log("\n");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  DEPLOYMENT COMPLETE — copy these addresses to the RPi3");
    console.log("════════════════════════════════════════════════════════════");
    console.log("");
    console.log("  Each contract has its own unique address (never shared):");
    console.log("    IoTAuthLog           →  " + authLogAddr);
    console.log("    CommitRevealOTP      →  " + commitRevealAddr);
    console.log("    FirmwareMetadataStore→  " + firmwareMetaAddr);
    console.log("    RPi3 device wallet   →  " + deviceAddr);
    console.log("");
    console.log("────────────────────────────────────────────────────────────");
    console.log("  [1/2] /etc/iot-gateway/blockchain.conf  (auth logging)");
    console.log("────────────────────────────────────────────────────────────");
    console.log("BLOCKCHAIN_RPC_URL=http://" + NODE_IP + ":8545");
    console.log("BLOCKCHAIN_AUTHLOG_CONTRACT=" + authLogAddr);
    console.log("BLOCKCHAIN_DEVICE_ADDR="      + deviceAddr);
    console.log("BLOCKCHAIN_CHAIN_ID=1337");
    console.log("");
    console.log("────────────────────────────────────────────────────────────");
    console.log("  [2/2] /etc/iot-gateway/firmware.conf  (OTA firmware)");
    console.log("────────────────────────────────────────────────────────────");
    console.log("FIRMWARE_CONTRACT=" + firmwareMetaAddr);
    console.log("");
    console.log("════════════════════════════════════════════════════════════");
    console.log("  Replace <NODE-IP> with your node's IP (e.g. 192.168.1.6).");
    console.log("  WARNING: restarting `npx hardhat node` deploys new addresses");
    console.log("           — re-run this script and update both config files.");
    console.log("════════════════════════════════════════════════════════════");
}

main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
});
