// scripts/upgrade_box.js
const { ethers, upgrades } = require("hardhat");

const PROXY = "0xc1EF10880B3aadf07ea45dc8E9D7B4457F4eBD20";

async function main() {
  const BoxV2 = await ethers.getContractFactory("BoxV2");
  console.log("Upgrading Box...");
  await upgrades.upgradeProxy(PROXY, BoxV2);
  console.log("Box upgraded");
}

main();
