// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./HashKeyChainStakingBase.sol";

/**
 * @title HashKeyChainStakingOperations
 * @dev Implementation of staking operations, using a share-based model
 */
abstract contract HashKeyChainStakingOperations is HashKeyChainStakingBase {
    /**
     * @dev Regular staking (unlocked), directly receives stHSK
     */
    function stake() external payable nonReentrant whenNotPaused {
        // Strict validation of minimum stake amount
        require(msg.value >= minStakeAmount, "Amount below minimum stake");
        require(block.timestamp < stakeEndTime, "Staking ended");
        
        // Update reward pool
        updateRewardPool();
        
        // Calculate shares to mint
        uint256 sharesAmount = getSharesForHSK(msg.value);
        
        // 验证股份数量不为零
        require(sharesAmount > 0, "Shares amount cannot be zero");
        
        // 处理第一次质押的最小流动性
        if (!initialLiquidityMinted) {
            require(sharesAmount >= MINIMUM_LIQUIDITY, "Initial stake too small");
            initialLiquidityMinted = true;
            // 将最小流动性发送到死地址
            stHSK.mint(0x000000000000000000000000000000000000dEaD, MINIMUM_LIQUIDITY);
            sharesAmount -= MINIMUM_LIQUIDITY;
        }
        
        // Update total staked amount
        totalPooledHSK += msg.value;
        
        // 更新未锁定质押的总量
        totalUnlockedShares += sharesAmount;
        
        // Mint stHSK tokens
        stHSK.mint(msg.sender, sharesAmount);
        
        emit Stake(msg.sender, msg.value, sharesAmount, StakeType.FIXED_30_DAYS, 0, 0);
    }

    /**
     * @dev Locked staking, with fixed lock period and additional rewards
     * @param _stakeType Stake type (determines lock period and rewards)
     */
    function stakeLocked(StakeType _stakeType) external payable nonReentrant whenNotPaused {
        // Strict validation of minimum stake amount
        require(msg.value >= minStakeAmount, "Amount below minimum stake");
        require(block.timestamp < stakeEndTime, "Staking ended");
        
        // Update reward pool
        updateRewardPool();
        
        // Calculate shares to mint
        uint256 sharesAmount = getSharesForHSK(msg.value);
        
        // 验证股份数量不为零
        require(sharesAmount > 0, "Shares amount cannot be zero");
        
        // 处理第一次质押的最小流动性
        if (!initialLiquidityMinted) {
            require(sharesAmount >= MINIMUM_LIQUIDITY, "Initial stake too small");
            initialLiquidityMinted = true;
            // 将最小流动性发送到死地址
            stHSK.mint(0x000000000000000000000000000000000000dEaD, MINIMUM_LIQUIDITY);
            sharesAmount -= MINIMUM_LIQUIDITY;
        }
        
        // Determine lock period
        uint256 lockDuration;
        if (_stakeType == StakeType.FIXED_30_DAYS) lockDuration = 30 days;
        else if (_stakeType == StakeType.FIXED_90_DAYS) lockDuration = 90 days;
        else if (_stakeType == StakeType.FIXED_180_DAYS) lockDuration = 180 days;
        else if (_stakeType == StakeType.FIXED_365_DAYS) lockDuration = 365 days;
        else revert("Invalid stake type");
        
        // Create locked stake record
        lockedStakes[msg.sender].push(LockedStake({
            sharesAmount: sharesAmount,
            hskAmount: msg.value,
            lockEndTime: block.timestamp + lockDuration,
            lockDuration: lockDuration,
            withdrawn: false
        }));
        
        // Update total staked amount
        totalPooledHSK += msg.value;
        
        // 更新该锁定期类型的质押总量
        totalSharesByStakeType[_stakeType] += sharesAmount;
        
        // Mint stHSK tokens
        stHSK.mint(msg.sender, sharesAmount);
        
        uint256 stakeId = lockedStakes[msg.sender].length - 1;
        emit Stake(msg.sender, msg.value, sharesAmount, _stakeType, block.timestamp + lockDuration, stakeId);
    }

    /**
     * @dev Unlock locked stake
     * @param _stakeId Stake ID
     */
    function unstakeLocked(uint256 _stakeId) external nonReentrant {
        require(_stakeId < lockedStakes[msg.sender].length, "Invalid stake ID");
        LockedStake storage lockedStake = lockedStakes[msg.sender][_stakeId];
        
        require(!lockedStake.withdrawn, "Stake already withdrawn");
        require(lockedStake.sharesAmount > 0, "Stake amount is zero");
        
        // Update reward pool
        updateRewardPool();
        
        // Check if early withdrawal
        bool isEarlyWithdrawal = (block.timestamp < lockedStake.lockEndTime);
        
        // Calculate penalty (if early withdrawal)
        uint256 penalty = 0;
        uint256 sharesToBurn = lockedStake.sharesAmount;
        uint256 hskToReturn = getHSKForShares(sharesToBurn);
        
        // 确定质押类型并更新该类型的质押总量
        StakeType stakeType;
        if (lockedStake.lockDuration == 30 days) stakeType = StakeType.FIXED_30_DAYS;
        else if (lockedStake.lockDuration == 90 days) stakeType = StakeType.FIXED_90_DAYS;
        else if (lockedStake.lockDuration == 180 days) stakeType = StakeType.FIXED_180_DAYS;
        else stakeType = StakeType.FIXED_365_DAYS;
        
        // 更新该锁定期类型的质押总量
        totalSharesByStakeType[stakeType] -= sharesToBurn;
        
        if (isEarlyWithdrawal) {
            // Calculate elapsed lock period ratio
            uint256 elapsedTime = block.timestamp - (lockedStake.lockEndTime - lockedStake.lockDuration);
            uint256 completionRatio = (elapsedTime * BASIS_POINTS) / lockedStake.lockDuration;
            
            // Adjust penalty based on completion (higher completion, lower penalty)
            uint256 adjustedPenalty = earlyWithdrawalPenalty[stakeType] * (BASIS_POINTS - completionRatio) / BASIS_POINTS;
            
            // Apply penalty
            penalty = (hskToReturn * adjustedPenalty) / BASIS_POINTS;
            hskToReturn -= penalty;
            
            // Add penalty to reserved rewards
            reservedRewards += penalty;
        }
        
        // Mark stake as withdrawn
        lockedStake.withdrawn = true;
        
        // 计算原始质押金额和奖励部分
        uint256 originalStake = lockedStake.hskAmount;
        uint256 rewardPart = 0;
        
        // 如果返还金额大于原始质押金额，则差额为奖励部分
        if (hskToReturn > originalStake) {
            rewardPart = hskToReturn - originalStake;
        } else {
            // 如果返还金额小于原始质押金额（可能是因为提前提取的罚金），则全部视为原始质押
            originalStake = hskToReturn;
        }
        
        // 更新总质押金额，只减去原始质押部分
        totalPooledHSK -= originalStake;
        
        // 如果有奖励部分，从已支付奖励中减去
        if (rewardPart > 0) {
            // 确保不会减去超过已支付奖励的金额
            if (rewardPart > totalPaidRewards) {
                rewardPart = totalPaidRewards;
            }
            totalPaidRewards -= rewardPart;
            totalPooledHSK -= rewardPart;
        }
        
        // Check if user has enough stHSK
        require(stHSK.balanceOf(msg.sender) >= sharesToBurn, "Insufficient stHSK balance");
        
        // Burn stHSK tokens
        stHSK.burn(msg.sender, sharesToBurn);
        
        // Return HSK tokens
        bool transferSuccess = safeHskTransfer(payable(msg.sender), hskToReturn);
        require(transferSuccess, "HSK transfer failed");
        
        emit Unstake(msg.sender, sharesToBurn, hskToReturn, isEarlyWithdrawal, penalty, _stakeId);
    }

    /**
     * @dev Unstake regular (unlocked) stake
     * @param _sharesAmount Share amount to unstake
     */
    function unstake(uint256 _sharesAmount) external nonReentrant {
        require(_sharesAmount > 0, "Cannot unstake 0");
        require(stHSK.balanceOf(msg.sender) >= _sharesAmount, "Insufficient stHSK balance");
        
        // Update reward pool
        updateRewardPool();
        
        // Calculate HSK amount to return
        uint256 hskToReturn = getHSKForShares(_sharesAmount);
        
        // 计算原始质押金额和奖励部分
        // 对于普通质押，我们没有记录原始质押金额，所以需要估算
        // 使用当前的shares比例来估算原始质押部分
        uint256 totalShares = stHSK.totalSupply();
        uint256 originalStakeRatio = (_sharesAmount * BASIS_POINTS) / totalShares;
        uint256 originalStake = (totalPooledHSK * originalStakeRatio) / BASIS_POINTS;
        
        // 确保原始质押不超过返还金额
        if (originalStake > hskToReturn) {
            originalStake = hskToReturn;
        }
        
        uint256 rewardPart = hskToReturn - originalStake;
        
        // 更新总质押金额，只减去原始质押部分
        totalPooledHSK -= originalStake;
        
        // 如果有奖励部分，从已支付奖励中减去
        if (rewardPart > 0) {
            // 确保不会减去超过已支付奖励的金额
            if (rewardPart > totalPaidRewards) {
                rewardPart = totalPaidRewards;
            }
            totalPaidRewards -= rewardPart;
            totalPooledHSK -= rewardPart;
        }
        
        if (_sharesAmount <= totalUnlockedShares) {
            totalUnlockedShares -= _sharesAmount;
        } else {
            // 如果提取的数量超过了未锁定的总量，说明用户提取了一部分锁定的质押
            // 这种情况在实际中不应该发生，因为锁定的质押应该通过unstakeLocked提取
            // 这里只是为了防止totalUnlockedShares变为负数
            totalUnlockedShares = 0;
        }
        
        // Burn stHSK tokens
        stHSK.burn(msg.sender, _sharesAmount);
        
        // Return HSK tokens
        bool success = safeHskTransfer(payable(msg.sender), hskToReturn);
        require(success, "HSK transfer failed");
        
        emit Unstake(msg.sender, _sharesAmount, hskToReturn, false, 0, type(uint256).max);
    }
}