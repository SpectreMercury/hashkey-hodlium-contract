const { expect } = require("chai");
const { ethers } = require("hardhat");
const { upgrades } = require("hardhat");

describe("HashKeyChain Staking - Initialization & Basic", function () {
  let staking, stHSK, owner, addr1, addr2;
  const minStakeAmount = ethers.parseEther("100");
  
  // Stake types
  const FIXED_30_DAYS = 0;
  const FIXED_90_DAYS = 1;
  const FIXED_180_DAYS = 2;
  const FIXED_365_DAYS = 3;
  
  before(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // Deploy contract
    const HashKeyChainStaking = await ethers.getContractFactory("HashKeyChainStaking");
    staking = await upgrades.deployProxy(HashKeyChainStaking, [
      ethers.parseEther("0.01"), // hskPerBlock
      (await ethers.provider.getBlockNumber()) + 10, // startBlock
      ethers.parseEther("0.1"),  // maxHskPerBlock
      minStakeAmount,
      ethers.parseEther("1000"), // annualBudget
      2 // blockTime
    ]);
    
    await staking.waitForDeployment();
    
    // Get stHSK contract
    const stHSKAddress = await staking.stHSK();
    const StHSK = await ethers.getContractFactory("StHSK");
    stHSK = StHSK.attach(stHSKAddress);
    
    // Add rewards
    await owner.sendTransaction({
      to: await staking.getAddress(),
      value: ethers.parseEther("10")
    });
  });

  describe("Initialization", function() {
    it("Should initialize with correct values", async function() {
      const [factor30_weighted, factor30_total] = await staking.calculateCorrectionFactor(0);
      const ratio30 = totalWeightedShares > 0 ? (factor30_weighted * 10000 / factor30_total) : 0;
      console.log('30天的 质押占 总池子的百分比 * 10000 =', ratio30);
      
      const [factor90_weighted, factor90_total] = await staking.calculateCorrectionFactor(1);
      const ratio90 = factor90_total > 0 ? (factor90_weighted * 10000 / factor90_total) : 0;
      console.log('90天的 质押占 总池子的百分比 * 10000 =', ratio90);
      
      const [factor180_weighted, factor180_total] = await staking.calculateCorrectionFactor(2);
      const ratio180 = factor180_total > 0 ? (factor180_weighted * 10000 / factor180_total) : 0;
      console.log('180天的 质押占 总池子的百分比 * 10000 =', ratio180);
      
      const [factor365_weighted, factor365_total] = await staking.calculateCorrectionFactor(3);
      const ratio365 = factor365_total > 0 ? (factor365_weighted * 10000 / factor365_total) : 0;
      console.log('365天的 质押占 总池子的百分比 * 10000 =', ratio365);
      
      const [factorFlex_weighted, factorFlex_total] = await staking.calculateCorrectionFactor(4);
      const ratioFlex = factorFlex_total > 0 ? (factorFlex_weighted * 10000 / factorFlex_total) : 0;
      console.log('灵活的 质押占 总池子的百分比 * 10000 =', ratioFlex);
      
      expect(await staking.minStakeAmount()).to.equal(minStakeAmount);
      expect(await stHSK.totalSupply()).to.equal(0);
    });
    
    it("Should set correct bonuses", async function() {
      expect(await staking.stakingBonus(FIXED_30_DAYS)).to.equal(0);
      expect(await staking.stakingBonus(FIXED_90_DAYS)).to.equal(80);
      expect(await staking.stakingBonus(FIXED_180_DAYS)).to.equal(200);
      expect(await staking.stakingBonus(FIXED_365_DAYS)).to.equal(400);
    });
  });

}); 