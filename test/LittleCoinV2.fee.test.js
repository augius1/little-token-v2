// test/LittleCoinV2.test.js

const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("LittleCoinV2 – Unit & Integration Tests", function () {
  const INITIAL_SUPPLY = ethers.parseEther("1000000000");
  const DELAY = 2 * 24 * 3600; // 2 days

  // ─── UNIT TESTS ─────────────────────────────────────────────────────────────
  describe("Unit tests", function () {
    let token;
    let owner, timelockSigner, charity, liquidity, reward, recipient;

    beforeEach(async () => {
      [owner, timelockSigner, charity, liquidity, reward, recipient] = await ethers.getSigners();
      const LittleCoin = await ethers.getContractFactory("LittleCoinV2");
      token = await LittleCoin.deploy(
        timelockSigner.address,
        charity.address,
        liquidity.address,
        reward.address,
        INITIAL_SUPPLY
      );
      await token.waitForDeployment();
    });

    describe("Fee logic & rounding", function () {
      it("assigns dust to charity on minimal transfers", async () => {
        await token.connect(timelockSigner).setTotalFeeBP(300);
        await expect(() =>
          token.connect(owner).transfer(recipient.address, 34n)
        ).to.changeTokenBalances(
          token,
          [owner, charity, recipient],
          [-34n, 1n, 33n]
        );
      });

      it("reverts setTotalFeeBP above MAX_FEE_BP", async () => {
        await expect(
          token.connect(timelockSigner).setTotalFeeBP(1001)
        ).to.be.revertedWith("Exceeds max fee");
      });
    });

    describe("Access control", function () {
      it("reverts when non-FEE_ADMIN_ROLE calls setFeeDistribution", async () => {
        await expect(
          token.connect(owner).setFeeDistribution(2500, 2500, 2500, 2500)
        ).to.be.revertedWith(/AccessControl: account .* is missing role .*/);
      });

      it("allows timelock to update charity wallet", async () => {
        const newAddr = ethers.Wallet.createRandom().address;
        await token.connect(timelockSigner).updateCharityWallet(newAddr);
        expect(await token.charityWallet()).to.equal(newAddr);
      });

      it("grantRole & revokeRole flows work", async () => {
        const MINTER = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
        await token.connect(timelockSigner).grantRole(MINTER, owner.address);
        expect(await token.hasRole(MINTER, owner.address)).to.be.true;
        await token.connect(timelockSigner).revokeRole(MINTER, owner.address);
        expect(await token.hasRole(MINTER, owner.address)).to.be.false;
      });
    });

    describe("Pausable behavior", function () {
      it("blocks transfers when paused", async () => {
        await token.connect(timelockSigner).pause();
        await expect(
          token.connect(owner).transfer(recipient.address, 1n)
        ).to.be.revertedWith("Pausable: paused");
      });

      it("reverts unpause when not paused", async () => {
        await expect(
          token.connect(timelockSigner).unpause()
        ).to.be.revertedWith("Pausable: not paused");
      });
    });

    describe("Capped supply & mint/burn", function () {
      it("mints exactly to cap", async () => {
        const remaining = (await token.cap()) - (await token.totalSupply());
        await token.connect(timelockSigner).mint(owner.address, remaining);
        expect(await token.totalSupply()).to.equal(await token.cap());
      });

      it("reverts mint beyond cap", async () => {
        await expect(
          token.connect(timelockSigner).mint(owner.address, 1n)
        ).to.be.revertedWith("ERC20Capped: cap exceeded");
      });

      it("burn decreases totalSupply", async () => {
        await token.connect(owner).burn(ethers.parseEther("10"));
        expect(await token.totalSupply()).to.equal(
          INITIAL_SUPPLY - ethers.parseEther("10")
        );
      });
    });

    describe("ERC20 edge cases", function () {
      it("reverts transferFrom when allowance insufficient", async () => {
        await token.connect(owner).approve(recipient.address, 100);
        await expect(
          token
            .connect(recipient)
            .transferFrom(owner.address, recipient.address, 101)
        ).to.be.revertedWith("Allowance exceeded");
      });

      it("reverts transfer to zero address", async () => {
        await expect(
          token.connect(owner).transfer(ethers.ZeroAddress, 1n)
        ).to.be.revertedWith("ERC20: transfer to the zero address");
      });
    });
  });

  // ─── INTEGRATION TESTS ───────────────────────────────────────────────────────
  describe("Integration / Governance Flows", function () {
    let timelockCtr, token;
    let owner, charity, liquidity, reward;

    beforeEach(async () => {
      [owner, charity, liquidity, reward] = await ethers.getSigners();
      const Timelock = await ethers.getContractFactory("LittleCoinTimelock");
      timelockCtr = await Timelock.deploy(
        [owner.address],
        [owner.address],
        owner.address
      );
      await timelockCtr.waitForDeployment();
      const LittleCoin = await ethers.getContractFactory("LittleCoinV2");
      token = await LittleCoin.deploy(
        timelockCtr.target,
        charity.address,
        liquidity.address,
        reward.address,
        INITIAL_SUPPLY
      );
      await token.waitForDeployment();
    });

    it("governance: schedule + execute zero-fee and wallet update", async () => {
      const zeroFeeData = token.interface.encodeFunctionData("setTotalFeeBP", [0]);
      const salt1 = ethers.keccak256(ethers.toUtf8Bytes("zero-fee"));
      await timelockCtr.schedule(
        token.target,
        0,
        zeroFeeData,
        ethers.ZeroHash,
        salt1,
        DELAY
      );
      await network.provider.send("evm_increaseTime", [DELAY + 1]);
      await network.provider.send("evm_mine");
      await timelockCtr.execute(
        token.target,
        0,
        zeroFeeData,
        ethers.ZeroHash,
        salt1
      );
      expect(await token.totalFeeBP()).to.equal(0);
      const newCharity = ethers.Wallet.createRandom().address;
      const updData = token.interface.encodeFunctionData("updateCharityWallet", [newCharity]);
      const salt2 = ethers.keccak256(ethers.toUtf8Bytes("update-charity"));
      await timelockCtr.schedule(
        token.target,
        0,
        updData,
        ethers.ZeroHash,
        salt2,
        DELAY
      );
      await network.provider.send("evm_increaseTime", [DELAY + 1]);
      await network.provider.send("evm_mine");
      await timelockCtr.execute(
        token.target,
        0,
        updData,
        ethers.ZeroHash,
        salt2
      );
      expect(await token.charityWallet()).to.equal(newCharity);
      await expect(() =>
        token.connect(owner).transfer(charity, ethers.parseEther("1"))
      ).to.changeTokenBalances(
        token,
        [owner, charity],
        [ethers.parseEther("-1"), ethers.parseEther("1")]
      );
    });

    it("reverts scheduling by non-proposer", async () => {
      const data = token.interface.encodeFunctionData("setTotalFeeBP", [0]);
      await expect(
        timelockCtr.connect(charity).schedule(
          token.target,
          0,
          data,
          ethers.ZeroHash,
          ethers.keccak256(ethers.toUtf8Bytes("bad")),
          DELAY
        )
      ).to.be.revertedWith(/AccessControl: account .* is missing role .*/);
    });

    it("reverts execute before delay elapses", async () => {
      const data = token.interface.encodeFunctionData("setTotalFeeBP", [0]);
      const id = ethers.keccak256(ethers.toUtf8Bytes("governance"));
      await timelockCtr.connect(owner).schedule(
        token.target,
        0,
        data,
        ethers.ZeroHash,
        id,
        DELAY
      );
      await network.provider.send("evm_increaseTime", [DELAY - 2]);
      await network.provider.send("evm_mine");
      // expecting a revert due to insufficient delay
      await expect(
        timelockCtr.connect(owner).execute(
          token.target,
          0,
          data,
          ethers.ZeroHash,
          id
        )
      ).to.be.reverted;
    });
  });
});
