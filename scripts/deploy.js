// scripts/deploy.js
require("dotenv").config();
const { ethers } = require("hardhat");
const path = require("path");

// === RUNNING UPDATED DEPLOY SCRIPT ===
console.log("=== RUNNING UPDATED DEPLOY SCRIPT ===");

async function main() {
  // ─── Preliminary clean reminder ───
  // If you haven’t yet: rm -rf cache artifacts && npx hardhat compile

  // ─── Load signer and wallets ───
  const [deployer] = await ethers.getSigners();
  const CHAR = process.env.CHARITY_WALLET;
  const LIQ  = process.env.LIQUIDITY_WALLET;
  const REW  = process.env.REWARD_WALLET;

  console.log("Deployer:", deployer.address);
  console.log("Charity:", CHAR);
  console.log("Liquidity:", LIQ);
  console.log("Reward:", REW);

  // ─── Inspect artifact JSON ABI ───
  const artifactPath = path.join(__dirname, "../artifacts/contracts/littlecoin.sol/LittleCoinV2.json");
  const artifact = require(artifactPath);
  const ctorAbi = artifact.abi.find(item => item.type === "constructor");
  console.log("ABI constructor inputs:", ctorAbi.inputs);

  // ─── Inspect factory signature ───
  const LittleCoin = await ethers.getContractFactory(
    "contracts/littlecoin.sol:LittleCoinV2"
  );
  console.log(
    "Factory expects:",
    LittleCoin.interface.deploy.inputs.map(i => `${i.type} ${i.name}`)
  );

  // ─── Deploy TimelockController (OZ v5 requires 4 args) ───
  const Timelock = await ethers.getContractFactory(
    "@openzeppelin/contracts/governance/TimelockController.sol:TimelockController"
  );
  const timelock = await Timelock.deploy(
    1,                         // minDelay
    [deployer.address],        // proposers
    [deployer.address],        // executors
    deployer.address           // admin (new required 4th arg)
  );
  await timelock.waitForDeployment();
  console.log("TimelockController @", timelock.target);

  // ─── Prepare deploy args and log them ───
  const cap  = ethers.parseUnits("1000000000", 18);
  const args = [timelock.target, CHAR, LIQ, REW, cap];
  console.log(
    "Deploy args:", args,
    `(count: ${args.length})`,
    "raw types:",
    args.map(a => Object.prototype.toString.call(a))
  );

  // ─── Deploy LittleCoinV2 ───
  console.log("Calling deploy(...args) now...");
  const littleCoin = await LittleCoin.deploy(...args);
  await littleCoin.waitForDeployment();
  console.log("LittleCoinV2 @", littleCoin.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
