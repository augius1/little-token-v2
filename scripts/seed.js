// scripts/seed.js
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Seeding from account:", deployer.address);
  
    // Deploy your LittleCoinV2
    const LittleCoin = await ethers.getContractFactory("LittleCoinV2");
    const token = await LittleCoin.deploy(
      deployer.address,               // daoTimelock
      process.env.CHARITY_WALLET,     // charity
      process.env.LIQUIDITY_WALLET,   // liquidity
      process.env.REWARD_WALLET,      // reward
      ethers.parseUnits("1000000000", 18) // cap
    );
    await token.waitForDeployment();
  
    console.log("Deployed LittleCoinV2 at:", token.target);
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  