// scripts/checkConstructor.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // Grab the LittleCoinV2 factory
  const Factory = await ethers.getContractFactory("LittleCoinV2");
  
  // Print out exactly what its constructor expects
  console.log("LittleCoinV2 constructor parameters:");
  console.table(Factory.interface.deploy.inputs);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
