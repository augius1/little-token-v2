const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LittleCoinV2 + Treasury Integration", function () {
  let deployer, timelockSigner, user, receiver;
  let token, treasury;

  // Only cap matters for deployment here
  const CAP = ethers.parseUnits("2000000000", 18);

  // Category identifiers
  const CHARITY   = ethers.keccak256(ethers.toUtf8Bytes("CHARITY"));
  const LIQUIDITY = ethers.keccak256(ethers.toUtf8Bytes("LIQUIDITY"));
  const REWARD    = ethers.keccak256(ethers.toUtf8Bytes("REWARD"));

  beforeEach(async function () {
    [deployer, timelockSigner, user, receiver] = await ethers.getSigners();

    // 1) Deploy LittleCoinV2 with timelockSigner as DAO
    const TokenFactory = await ethers.getContractFactory("LittleCoinV2");
    token = await TokenFactory.deploy(
      timelockSigner.address,   // DAO timelock
      deployer.address,         // charity wallet (will redirect)
      deployer.address,         // liquidity wallet
      deployer.address,         // reward wallet
      CAP
    );
    await token.waitForDeployment();

    // 2) Deploy Treasury connected to token + DAO
    const TreasuryFactory = await ethers.getContractFactory("Treasury");
    treasury = await TreasuryFactory.deploy(
      token.target,
      timelockSigner.address
    );
    await treasury.waitForDeployment();

    // 3) Point token’s fees at our on-chain Treasury
    await token.connect(timelockSigner).updateCharityWallet(treasury.target);
    await token.connect(timelockSigner).updateLiquidityWallet(treasury.target);
    await token.connect(timelockSigner).updateRewardWallet(treasury.target);
  });

  it("routes transfer fees into Treasury buckets", async function () {
    // Reactivate fees for `user`
    await token.connect(timelockSigner).setFeeExempt(user.address, false);

    // Mint 1 000 tokens and transfer 100 → receiver
    await token.connect(timelockSigner).mint(user.address, ethers.parseUnits("1000", 18));
    const transferAmount = ethers.parseUnits("100", 18);
    await token.connect(user).transfer(receiver.address, transferAmount);

    // Read fee BPs
    const feeBP  = await token.totalFeeBP();
    const cBP    = await token.charityFeeBP();
    const lBP    = await token.liquidityFeeBP();
    const rBP    = await token.rewardFeeBP();

    // Calculate shares
    const totalFee       = transferAmount * feeBP   / 10000n;
    const charityShare   = totalFee      * cBP      / 10000n;
    const liquidityShare = totalFee      * lBP      / 10000n;
    const rewardShare    = totalFee      * rBP      / 10000n;

    // Assert on-chain deposits match
    expect(await treasury.balances(CHARITY)).to.equal(charityShare);
    expect(await treasury.balances(LIQUIDITY)).to.equal(liquidityShare);
    expect(await treasury.balances(REWARD)).to.equal(rewardShare);
  });

  it("allows only DAO to distribute from Treasury", async function () {
    // Seed one 50 LTC transfer’s fees into CHARITY
    await token.connect(timelockSigner).setFeeExempt(user.address, false);
    await token.connect(timelockSigner).mint(user.address, ethers.parseUnits("50", 18));
    await token.connect(user).transfer(deployer.address, ethers.parseUnits("50", 18));

    // Non-DAO must revert
    await expect(
      treasury.connect(user).distribute(
        CHARITY,
        receiver.address,
        ethers.parseUnits("10", 18)
      )
    ).to.be.revertedWith("AccessControl");

    // Debug: log what’s actually in the bucket
    const deposited = await treasury.balances(CHARITY);
    console.log(">>> DEBUG: treasury.balances(CHARITY) =", deposited.toString());

    // DAO distributes exactly that amount
    await treasury
      .connect(timelockSigner)
      .distribute(CHARITY, receiver.address, deposited);

    // Debug: log receiver’s balance after distribution
    const recBal = await token.balanceOf(receiver.address);
    console.log(">>> DEBUG: receiver.token.balanceOf() =", recBal.toString());

    // Final assertion against the on-chain value
    expect(recBal).to.equal(deposited);
  });
});
