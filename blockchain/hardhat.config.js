require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: { enabled: true, runs: 200 },
        },
    },
    networks: {
        // Local Hardhat in-process node (default for `npx hardhat test`)
        hardhat: {
            chainId: 1337,
        },
        // External Hardhat node: `npx hardhat node`
        // hostname: "0.0.0.0" makes it reachable from RPi3 (not just localhost).
        // On OVHcloud VPS this allows the RPi3 to connect over the internet.
        // ALWAYS restrict with a firewall (ufw) so only the RPi3 IP can reach :8545.
        localhost: {
            url: "http://0.0.0.0:8545",
            chainId: 1337,
        },
        // VPS deployment target — same as localhost but explicit
        // Used when running: npx hardhat run deploy.js --network vps
        vps: {
            url: "http://127.0.0.1:8545",   // deploy from VPS itself
            chainId: 1337,
        },
        // Sepolia public testnet (set SEPOLIA_RPC_URL and DEPLOYER_PRIVKEY in .env)
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL || "",
            accounts: process.env.DEPLOYER_PRIVKEY ? [process.env.DEPLOYER_PRIVKEY] : [],
            chainId: 11155111,
        },
    },
    // Tell `npx hardhat node` to listen on all interfaces (0.0.0.0)
    // so the RPi3 can reach it from a different machine.
    // This is safe ONLY when combined with a ufw firewall rule.
    mocha: {
        timeout: 40000,
    },
    paths: {
        sources:   "..",           // scans iot-rules/blockchain/ and iot-rules/contracts/
        artifacts: "./artifacts",
        cache:     "./cache",
        tests:     "./test",
    },
};
