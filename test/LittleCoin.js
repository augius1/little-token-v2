// test/LittleCoinV2.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LittleCoinV2", function () {
  let token;
  let timelock;
  let owner, charity, liquidity, reward;

  // 1 billion tokens, 18 decimals
  const INITIAL_SUPPLY = ethers.parseUnits("1000000000", 18);
  const CAP            = INITIAL_SUPPLY;

  beforeEach(async function () {
    [owner, charity, liquidity, reward] = await ethers.getSigners();

    // Deploy OpenZeppelin TimelockController (now takes 4 args)
    const Timelock = await ethers.getContractFactory(
      "@openzeppelin/contracts/governance/TimelockController.sol:TimelockController"
    );
    timelock = await Timelock.deploy(
      /* minDelay */    1,
      /* proposers */   [ owner.address ],
      /* executors */   [ owner.address ],
      /* admin */       owner.address      // ← newly added
    );
    await timelock.waitForDeployment();

    // Deploy your LittleCoinV2, pointing at the timelock as the sole governor
    const LittleCoin = await ethers.getContractFactory("LittleCoinV2");
    token = await LittleCoin.deploy(
      timelock.target,       // your timelock (use .address if you’re on v5)
      charity.address,
      liquidity.address,
      reward.address,
      CAP
    );
    await token.waitForDeployment();
  });

  it("mints initial supply to deployer", async function () {
    const totalSupply  = await token.totalSupply();
    const ownerBalance = await token.balanceOf(owner.address);

    expect(totalSupply).to.equal(INITIAL_SUPPLY);
    expect(ownerBalance).to.equal(INITIAL_SUPPLY);
  });

  // …add any further tests here
});
