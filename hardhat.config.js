require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      viaIR: true,
      optimizer: { enabled: true, runs: 200 },
    },
  },
  paths: {
    sources: ".",        // scans iot-rules/contracts/ and iot-rules/blockchain/
  },
  networks: {
    // Local Hardhat node — start with: npx hardhat node --hostname 0.0.0.0
    localhost: {
      url: process.env.RPC_URL || "http://192.168.1.6:8545",
      chainId: 1337,
      accounts: process.env.SIGNER_KEY ? [process.env.SIGNER_KEY] : "remote",
    },
    amoy: {
      url: "https://rpc-amoy.polygon.technology",
      chainId: 80002,
      accounts: process.env.SIGNER_KEY ? [process.env.SIGNER_KEY] : [],
    },
  },
};