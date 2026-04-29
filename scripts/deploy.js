require("dotenv").config();
const { ethers } = require("hardhat");

const ADMIN_ADDRESS  = "0xPaste_Your_Admin_MetaMask_Address_Here";
const USER_A_ADDRESS = "0xPaste_Your_UserA_MetaMask_Address_Here";
const USER_B_ADDRESS = "0xPaste_Your_UserB_MetaMask_Address_Here";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);

  const Factory  = await ethers.getContractFactory("IoTUsers");
  const contract = await Factory.deploy(ADMIN_ADDRESS, USER_A_ADDRESS, USER_B_ADDRESS);
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  console.log("Contract deployed at:", contractAddress);

  const [admin, userA, userB] = await contract.getAllAddresses();
  console.log("\nStored on-chain:");
  console.log("  Admin  :", admin);
  console.log("  User A :", userA);
  console.log("  User B :", userB);

  console.log("\nView at: https://amoy.polygonscan.com/address/" + contractAddress);
}

main().catch((err) => { console.error(err); process.exit(1); });