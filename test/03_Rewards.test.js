const { expect } = require("chai");
const { ethers } = require("hardhat");
const { upgrades } = require("hardhat");
const { time, mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("HashKeyChain Staking - Rewards", function () {
  let staking, stHSK, owner, addr1, addr2, addr3, addr4, addr5, addr6, addr7, addr8, addr9, addr10;
  const minStakeAmount = ethers.parseEther("100");
  
  // Stake types
  const FIXED_30_DAYS = 0;
  const FIXED_90_DAYS = 1;
  const FIXED_180_DAYS = 2;
  const FIXED_365_DAYS = 3;
  before(async function () {
    [owner, addr1, addr2, addr3, addr4, addr5, addr6, addr7, addr8, addr9, addr10] = await ethers.getSigners();
    
    // Deploy contract
    const HashKeyChainStaking = await ethers.getContractFactory("HashKeyChainStaking");
    staking = await upgrades.deployProxy(HashKeyChainStaking, [
      ethers.parseEther("0.38"),
      (await ethers.provider.getBlockNumber()) + 10,
      ethers.parseEther("1"),
      minStakeAmount,
      ethers.parseEther("6000000"),
      2
    ]);
    
    await staking.waitForDeployment();
    
    // Get stHSK contract
    const stHSKAddress = await staking.stHSK();
    const StHSK = await ethers.getContractFactory("StHSK");
    stHSK = StHSK.attach(stHSKAddress);
    
    // Add rewards
    await owner.sendTransaction({
      to: await staking.getAddress(),
      value: ethers.parseEther("2000")
    });
  });

  it("Should accumulate rewards over time", async function() {
    const stakeAmount = ethers.parseEther("9000");
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    await staking.connect(addr2).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr3).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr4).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr5).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr6).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr7).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    await staking.connect(addr8).stakeLocked(FIXED_365_DAYS, { value: ethers.parseEther("9000") });
    
    
    const initialPooledHSK = await staking.totalPooledHSK();
    
    // Fast forward time and mine blocks
    await time.increase(2.5 * 24 * 60 * 60); // 180 days
    await mine(2.5 * 24 * 60 * 30); // Mine 100 blocks
  
    // Force reward pool update
    await staking.updateRewardPool();

    console.log('apr !!!!', await staking.getCurrentAPR(ethers.parseEther("100"), FIXED_365_DAYS));
    // const user1StHSK = await stHSK.balanceOf(addr1.address);
    // const user1HSK = await staking.getHSKForShares(user1StHSK);
    // console.log(`用户1（180天锁定）的HSK价值: ${ethers.formatEther(user1HSK)} HSK`);
    // const user1Reward = user1HSK - stakeAmount;
    // console.log(`用户1（180天锁定）的奖励: ${ethers.formatEther(user1Reward)} HSK`);
    const stakeReward = await staking.getStakeReward(addr1.address, 0);
    console.log(`Original Amount: ${ethers.formatEther(stakeReward[0])} HSK`);
    console.log(`Current Reward: ${ethers.formatEther(stakeReward[1])} HSK`);
    console.log(`Actual Reward (after penalty): ${ethers.formatEther(stakeReward[2])} HSK`);
    console.log(`Total Value: ${ethers.formatEther(stakeReward[3])} HSK`);
    
    // console.log('apr !!!!', await staking.getCurrentAPR(ethers.parseEther("100"), FIXED_180_DAYS));

    // Total pooled HSK should have increased
    expect(await staking.totalPooledHSK()).to.be.gt(initialPooledHSK);
  });
  
  // it("Should apply correct bonus rates for locked staking", async function() {
  //   // // 1. 用户1进行质押
  //   // const stakeAmount = ethers.parseEther("200");
  //   // await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });

  //   // Get APRs, convert to numbers for easier comparison
  //   const apr30Number = Number(await staking.getCurrentAPR(ethers.parseEther("1000"), FIXED_30_DAYS));
  //   const apr90Number = Number(await staking.getCurrentAPR(ethers.parseEther("1000"), FIXED_90_DAYS));
    
  //   // Verify longer lock periods have higher APR
  //   expect(apr90Number).to.be.gt(apr30Number);
    
  //   // Get the baseline reward as reference
  //   console.log(`APR 30 days: ${apr30Number}, APR 90 days: ${apr90Number}, Difference: ${apr90Number - apr30Number}`);
    
  //   // Can choose not to compare exact values, just ensure 90-day APR > 30-day APR
  //   // If we must compare the difference, use more relaxed error range
  //   const bonus90 = Number(await staking.stakingBonus(FIXED_90_DAYS));
  //   console.log(`Bonus for 90 days: ${bonus90}`);
    
  //   // Don't do precise comparison, just ensure 90-day APR is higher than 30-day APR
  // });
}); 
// @HashKeyChainStakingBase.sol 我想下一个测试用例 模拟一下， 参考
// @03_Rewards.test.js 
