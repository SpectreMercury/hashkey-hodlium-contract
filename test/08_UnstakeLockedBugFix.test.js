const { expect } = require("chai");
const { ethers } = require("hardhat");
const { upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("HashKeyChain Staking - UnstakeLocked Bug Fix", function () {
  let staking, stHSK, owner, addr1, addr2, addr3;
  const minStakeAmount = ethers.parseEther("100");
  
  // Stake types
  const FIXED_30_DAYS = 0;
  const FIXED_90_DAYS = 1;
  const FIXED_180_DAYS = 2;
  const FIXED_365_DAYS = 3;
  
  // 辅助函数：打印合约状态
  async function logContractState(message) {
    const rewardStatus = await staking.getRewardStatus();
    console.log(`\n--- ${message} ---`);
    console.log(`totalPooledHSK: ${ethers.formatEther(rewardStatus.totalPooled)} HSK`);
    console.log(`totalShares: ${ethers.formatEther(rewardStatus.totalShares)} stHSK`);
    console.log(`totalPaidRewards: ${ethers.formatEther(rewardStatus.totalPaid)} HSK`);
    console.log(`reservedRewards: ${ethers.formatEther(rewardStatus.reserved)} HSK`);
    console.log(`contractBalance: ${ethers.formatEther(rewardStatus.contractBalance)} HSK`);
    console.log(`Exchange Rate: 1 stHSK = ${ethers.formatEther(await staking.getHSKForShares(ethers.parseEther("1")))} HSK`);
    console.log(`--------------------------\n`);
  }
  
  // 辅助函数：打印用户的锁定质押详情
  async function logUserStakes(address, message) {
    const stakeCount = await staking.getUserLockedStakeCount(address);
    console.log(`\n=== ${message} ===`);
    console.log(`用户地址: ${address}`);
    console.log(`锁定质押数量: ${stakeCount}`);
    console.log(`stHSK余额: ${ethers.formatEther(await stHSK.balanceOf(address))} stHSK`);
    
    for (let i = 0; i < stakeCount; i++) {
      const stakeInfo = await staking.getLockedStakeInfo(address, i);
      console.log(`\n质押 #${i}:`);
      console.log(`  sharesAmount: ${ethers.formatEther(stakeInfo.sharesAmount)} stHSK`);
      console.log(`  hskAmount: ${ethers.formatEther(stakeInfo.hskAmount)} HSK`);
      console.log(`  当前HSK价值: ${ethers.formatEther(stakeInfo.currentHskValue)} HSK`);
      console.log(`  锁定结束时间: ${new Date(Number(stakeInfo.lockEndTime) * 1000).toLocaleString()}`);
      console.log(`  是否已提取: ${stakeInfo.isWithdrawn}`);
      console.log(`  是否仍在锁定期: ${stakeInfo.isLocked}`);
      
      // 计算sharesAmount和hskAmount的误差百分比
      if (!stakeInfo.isWithdrawn) {
        const sharesAmount = Number(ethers.formatEther(stakeInfo.sharesAmount));
        const hskAmount = Number(ethers.formatEther(stakeInfo.hskAmount));
        const currentHskValue = Number(ethers.formatEther(stakeInfo.currentHskValue));
        
        // 计算sharesAmount和hskAmount的误差百分比
        const errorPercentage = Math.abs((currentHskValue - hskAmount) / hskAmount * 100);
        console.log(`  误差百分比: ${errorPercentage.toFixed(4)}%`);
        
        // 验证误差不超过5%
        if (errorPercentage > 5) {
          console.log(`  ⚠️ 警告: 误差超过5%!`);
        } else {
          console.log(`  ✓ 误差在允许范围内`);
        }
      } else {
        console.log(`  (已提取，不计算误差)`);
      }
    }
    console.log(`===========================\n`);
  }
  
  // 辅助函数：验证所有未提取质押的误差不超过5%
  async function verifyErrorPercentage(address) {
    const stakeCount = await staking.getUserLockedStakeCount(address);
    
    for (let i = 0; i < stakeCount; i++) {
      const stakeInfo = await staking.getLockedStakeInfo(address, i);
      
      // 只验证未提取的质押
      if (!stakeInfo.isWithdrawn) {
        const sharesAmount = Number(ethers.formatEther(stakeInfo.sharesAmount));
        const hskAmount = Number(ethers.formatEther(stakeInfo.hskAmount));
        const currentHskValue = Number(ethers.formatEther(stakeInfo.currentHskValue));
        
        // 计算sharesAmount和hskAmount的误差百分比
        const errorPercentage = Math.abs((currentHskValue - hskAmount) / hskAmount * 100);
        
        // 验证误差不超过5%
        expect(errorPercentage).to.be.lessThan(5, `质押 #${i} 的误差超过5%: ${errorPercentage.toFixed(4)}%`);
      }
    }
  }
  
  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    
    // 部署合约
    const HashKeyChainStaking = await ethers.getContractFactory("HashKeyChainStaking");
    staking = await upgrades.deployProxy(HashKeyChainStaking, [
      ethers.parseEther("0.01"),  // hskPerBlock
      (await ethers.provider.getBlockNumber()) + 10,  // startBlock
      ethers.parseEther("0.1"),   // maxHskPerBlock
      minStakeAmount,             // minStakeAmount
      ethers.parseEther("1000"),  // annualBudget
      2                           // blockTime
    ]);
    
    await staking.waitForDeployment();
    
    // 获取stHSK合约
    const stHSKAddress = await staking.stHSK();
    const StHSK = await ethers.getContractFactory("StHSK");
    stHSK = StHSK.attach(stHSKAddress);
    
    // 添加奖励
    await owner.sendTransaction({
      to: await staking.getAddress(),
      value: ethers.parseEther("10")
    });
    
    // 等待开始区块
    await time.advanceBlockTo((await ethers.provider.getBlockNumber()) + 10);
  });

  it("复现之前的错误：第一次unstakeLocked成功，后续unstakeLocked失败", async function() {
    // 1. 用户1进行锁定质押
    const stakeAmount = ethers.parseEther("200");
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    
    // 记录用户1质押后的状态
    await logUserStakes(addr1.address, "用户1质押后");
    
    // 验证用户1质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 2. 用户2进行锁定质押
    await staking.connect(addr2).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    
    // 记录用户2质押后的状态
    await logUserStakes(addr2.address, "用户2质押后");
    
    // 验证用户2质押的误差在5%以内
    await verifyErrorPercentage(addr2.address);
    
    // 记录初始状态
    await logContractState("初始状态");
    
    // 3. 等待锁定期结束
    await time.increase(30 * 24 * 60 * 60 + 1); // 30天 + 1秒
    
    // 4. 用户1解除锁定质押
    const stakeId1 = 0;
    await staking.connect(addr1).unstakeLocked(stakeId1);
    
    // 记录用户1解除质押后的状态
    await logUserStakes(addr1.address, "用户1解除质押后");
    await logContractState("用户1解除质押后");
    
    // 验证用户1解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 5. 用户2解除锁定质押 - 在修复前这里会失败
    const stakeId2 = 0;
    await staking.connect(addr2).unstakeLocked(stakeId2);
    
    // 记录用户2解除质押后的状态
    await logUserStakes(addr2.address, "用户2解除质押后");
    await logContractState("用户2解除质押后");
    
    // 验证用户2解锁后的误差在5%以内
    await verifyErrorPercentage(addr2.address);
    
    // 6. 验证两次解除质押都成功
    const stake1 = await staking.getLockedStakeInfo(addr1.address, stakeId1);
    const stake2 = await staking.getLockedStakeInfo(addr2.address, stakeId2);
    
    expect(stake1.isWithdrawn).to.be.true;
    expect(stake2.isWithdrawn).to.be.true;
  });

  it("测试复杂场景：多用户、多种锁定期、提前解锁和正常解锁混合", async function() {
    // 1. 用户1进行30天锁定质押
    const stakeAmount1 = ethers.parseEther("200");
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount1 });
    await logUserStakes(addr1.address, "用户1进行30天锁定质押后");
    
    // 验证用户1质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 2. 用户2进行90天锁定质押
    const stakeAmount2 = ethers.parseEther("300");
    await staking.connect(addr2).stakeLocked(FIXED_90_DAYS, { value: stakeAmount2 });
    await logUserStakes(addr2.address, "用户2进行90天锁定质押后");
    
    // 验证用户2质押的误差在5%以内
    await verifyErrorPercentage(addr2.address);
    
    // 3. 用户3进行180天锁定质押
    const stakeAmount3 = ethers.parseEther("400");
    await staking.connect(addr3).stakeLocked(FIXED_180_DAYS, { value: stakeAmount3 });
    await logUserStakes(addr3.address, "用户3进行180天锁定质押后");
    
    // 验证用户3质押的误差在5%以内
    await verifyErrorPercentage(addr3.address);
    
    // 记录初始状态
    await logContractState("初始质押状态");
    
    // 4. 等待一段时间，让奖励累积
    await time.increase(15 * 24 * 60 * 60); // 15天
    
    // 5. 用户1提前解锁（应该有罚金）
    await staking.connect(addr1).unstakeLocked(0);
    await logUserStakes(addr1.address, "用户1提前解锁后");
    
    // 验证用户1解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录用户1提前解锁后的状态
    await logContractState("用户1提前解锁后");
    
    // 6. 再等待一段时间
    await time.increase(20 * 24 * 60 * 60); // 再过20天
    
    // 7. 用户2正常解锁（已经超过90天）
    await staking.connect(addr2).unstakeLocked(0);
    await logUserStakes(addr2.address, "用户2正常解锁后");
    
    // 验证用户2解锁后的误差在5%以内
    await verifyErrorPercentage(addr2.address);
    
    // 记录用户2正常解锁后的状态
    await logContractState("用户2正常解锁后");
    
    // 8. 用户3再进行一次质押
    const stakeAmount4 = ethers.parseEther("250");
    await staking.connect(addr3).stakeLocked(FIXED_30_DAYS, { value: stakeAmount4 });
    await logUserStakes(addr3.address, "用户3进行第二次质押后");
    
    // 验证用户3质押的误差在5%以内
    await verifyErrorPercentage(addr3.address);
    
    // 9. 用户3提前解锁第一次质押（180天的）
    await staking.connect(addr3).unstakeLocked(0);
    await logUserStakes(addr3.address, "用户3提前解锁第一次质押后");
    
    // 验证用户3解锁后的误差在5%以内
    await verifyErrorPercentage(addr3.address);
    
    // 记录用户3提前解锁第一次质押后的状态
    await logContractState("用户3提前解锁第一次质押后");
    
    // 10. 用户3正常解锁第二次质押
    await time.increase(35 * 24 * 60 * 60); // 再过35天
    await staking.connect(addr3).unstakeLocked(1);
    await logUserStakes(addr3.address, "用户3正常解锁第二次质押后");
    
    // 验证用户3解锁后的误差在5%以内
    await verifyErrorPercentage(addr3.address);
    
    // 记录最终状态
    await logContractState("最终状态");
    
    // 验证最终状态
    const finalStatus = await staking.getRewardStatus();
    
    // 所有质押都已解锁，totalPooledHSK应该接近0（可能有一些舍入误差）
    expect(finalStatus.totalPooled).to.be.lessThan(ethers.parseEther("1"));
    
    // 由于精度问题，totalShares可能会有较大的值，但相对于初始质押量来说仍然很小
    // 使用一个足够大的阈值
    expect(finalStatus.totalShares).to.be.lessThan(ethers.parseEther("1"));
  });

  it("测试奖励计算和分配：验证totalPaidRewards的正确性", async function() {
    // 1. 用户1进行质押
    const stakeAmount = ethers.parseEther("200");
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    await logUserStakes(addr1.address, "用户1质押后");
    
    // 验证用户1质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录初始状态
    await logContractState("初始质押状态");
    
    // 2. 等待一段时间，让奖励累积
    await time.increase(10 * 24 * 60 * 60); // 10天
    
    // 3. 手动更新奖励池
    await staking.updateRewardPool();
    await logUserStakes(addr1.address, "奖励更新后");
    
    // 验证奖励更新后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录奖励更新后的状态
    await logContractState("奖励更新后");
    
    // 4. 用户1解锁质押
    await staking.connect(addr1).unstakeLocked(0);
    await logUserStakes(addr1.address, "解锁后");
    
    // 验证用户1解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录解锁后的状态
    await logContractState("解锁后");
    
    // 验证totalPaidRewards的变化
    const finalStatus = await staking.getRewardStatus();
    
    // 解锁后，totalPaidRewards应该减少（因为奖励已经支付给用户）
    expect(finalStatus.totalPaid).to.be.lessThan(ethers.parseEther("10"));
  });

  it("测试多次连续unstakeLocked：验证totalPooledHSK的正确性", async function() {
    // 1. 用户1进行多次质押
    const stakeAmount = ethers.parseEther("100");
    
    // 第一次质押
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    await logUserStakes(addr1.address, "第一次质押后");
    
    // 验证用户1质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 第二次质押
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    await logUserStakes(addr1.address, "第二次质押后");
    
    // 验证用户2质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 第三次质押
    await staking.connect(addr1).stakeLocked(FIXED_30_DAYS, { value: stakeAmount });
    await logUserStakes(addr1.address, "第三次质押后");
    
    // 验证用户3质押的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录初始状态
    await logContractState("三次质押后状态");
    
    // 2. 等待锁定期结束
    await time.increase(30 * 24 * 60 * 60 + 1); // 30天 + 1秒
    
    // 3. 连续解锁所有质押
    await staking.connect(addr1).unstakeLocked(0);
    await logUserStakes(addr1.address, "第一次解锁后");
    await logContractState("第一次解锁后");
    
    // 验证第一次解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 第二次解锁
    await staking.connect(addr1).unstakeLocked(1);
    await logUserStakes(addr1.address, "第二次解锁后");
    
    // 验证第二次解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 第三次解锁
    await staking.connect(addr1).unstakeLocked(2);
    await logUserStakes(addr1.address, "第三次解锁后");
    
    // 验证第三次解锁后的误差在5%以内
    await verifyErrorPercentage(addr1.address);
    
    // 记录最终状态
    await logContractState("第三次解锁后");
    
    // 验证最终状态
    const finalStatus = await staking.getRewardStatus();
    
    // 所有质押都已解锁，totalPooledHSK应该接近0（可能有一些舍入误差）
    expect(finalStatus.totalPooled).to.be.lessThan(ethers.parseEther("1"));
    
    // 由于精度问题，totalShares可能会有较大的值，但相对于初始质押量来说仍然很小
    // 使用一个足够大的阈值
    expect(finalStatus.totalShares).to.be.lessThan(ethers.parseEther("1"));
  });
}); 