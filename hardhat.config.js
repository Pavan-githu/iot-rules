require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    amoy: {
      url: "https://rpc-amoy.polygon.technology",
      chainId: 80002,
      accounts: [process.env.ADMIN_PRIVATE_KEY],
    },
  },
};