// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./HashKeyChainStakingBase.sol";

/**
 * @title HashKeyChainStakingOperations
 * @dev Implementation of staking operations, using a share-based model
 */
import "hardhat/console.sol";

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
            require(
                sharesAmount >= MINIMUM_LIQUIDITY,
                "Initial stake too small"
            );
            initialLiquidityMinted = true;
            // 将最小流动性发送到死地址
            stHSK.mint(
                0x000000000000000000000000000000000000dEaD,
                MINIMUM_LIQUIDITY
            );
            sharesAmount -= MINIMUM_LIQUIDITY;
        }

        // Update total staked amount
        totalPooledHSK += msg.value;

        // 更新未锁定质押的总量
        totalUnlockedShares += sharesAmount;

        // Mint stHSK tokens
        stHSK.mint(msg.sender, sharesAmount);

        emit Stake(
            msg.sender,
            msg.value,
            sharesAmount,
            StakeType.FIXED_30_DAYS,
            0,
            0
        );
    }

    /**
     * @dev Locked staking, with fixed lock period and additional rewards
     * @param _stakeType Stake type (determines lock period and rewards)
     */
    function stakeLocked(
        StakeType _stakeType
    ) external payable nonReentrant whenNotPaused {
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
            require(
                sharesAmount >= MINIMUM_LIQUIDITY,
                "Initial stake too small"
            );
            initialLiquidityMinted = true;
            // 将最小流动性发送到死地址
            stHSK.mint(
                0x000000000000000000000000000000000000dEaD,
                MINIMUM_LIQUIDITY
            );
            sharesAmount -= MINIMUM_LIQUIDITY;
        }

        // Determine lock period
        uint256 lockDuration;
        if (_stakeType == StakeType.FIXED_30_DAYS) lockDuration = 30 days;
        else if (_stakeType == StakeType.FIXED_90_DAYS) lockDuration = 90 days;
        else if (_stakeType == StakeType.FIXED_180_DAYS)
            lockDuration = 180 days;
        else if (_stakeType == StakeType.FIXED_365_DAYS)
            lockDuration = 365 days;
        else if (_stakeType == StakeType.FLEXIBLE) lockDuration = 0 days;
        else revert("Invalid stake type");

        // Create locked stake record
        lockedStakes[msg.sender].push(
            LockedStake({
                sharesAmount: sharesAmount,
                hskAmount: msg.value,
                lockEndTime: block.timestamp + lockDuration,
                lockDuration: lockDuration,
                withdrawn: false
            })
        );

        // Update total staked amount
        totalPooledHSK += msg.value;

        // 更新该锁定期类型的质押总量
        totalSharesByStakeType[_stakeType] += sharesAmount;

        // Mint stHSK tokens
        stHSK.mint(msg.sender, sharesAmount);

        uint256 stakeId = lockedStakes[msg.sender].length - 1;
        emit Stake(
            msg.sender,
            msg.value,
            sharesAmount,
            _stakeType,
            block.timestamp + lockDuration,
            stakeId
        );
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
        if (lockedStake.lockDuration == 30 days)
            stakeType = StakeType.FIXED_30_DAYS;
        else if (lockedStake.lockDuration == 90 days)
            stakeType = StakeType.FIXED_90_DAYS;
        else if (lockedStake.lockDuration == 180 days)
            stakeType = StakeType.FIXED_180_DAYS;
        else if (lockedStake.lockDuration == 365 days)
            stakeType = StakeType.FIXED_365_DAYS;
        else stakeType = StakeType.FLEXIBLE;

        // 更新该锁定期类型的质押总量
        totalSharesByStakeType[stakeType] -= sharesToBurn;

        if (isEarlyWithdrawal) {
            // 直接按照比例全扣， 不需要计算 !!!
            penalty =
                (hskToReturn * earlyWithdrawalPenalty[stakeType]) /
                BASIS_POINTS;

            hskToReturn -= penalty;

            // Add penalty to reserved rewards
            reservedRewards += penalty;
        }

        // Mark stake as withdrawn
        lockedStake.withdrawn = true;

        // 计算原始质押金额和奖励部分烦烦烦方法
        uint256 originalStake = lockedStake.hskAmount;
        uint256 rewardPart = 0;

        // 如果返还金额大于原始质押金额，则差额为奖励部分
        if (hskToReturn > originalStake) {
            rewardPart = hskToReturn - originalStake;
        } else {
            // 如果返还金额小于原始质押金额（可能是因为提前提取的罚金），则全部视为原始质押
            originalStake = hskToReturn;
        }

        totalPooledHSK = totalPooledHSK - hskToReturn - penalty;

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
        require(
            stHSK.balanceOf(msg.sender) >= sharesToBurn,
            "Insufficient stHSK balance"
        );

        // Burn stHSK tokens
        stHSK.burn(msg.sender, sharesToBurn);

        // Return HSK tokens
        bool transferSuccess = safeHskTransfer(
            payable(msg.sender),
            hskToReturn
        );
        require(transferSuccess, "HSK transfer failed");

        emit Unstake(
            msg.sender,
            sharesToBurn,
            hskToReturn,
            isEarlyWithdrawal,
            penalty,
            _stakeId
        );
    }

    /**
     * @dev Unstake regular (unlocked) stake
     * @param _sharesAmount Share amount to unstake
     */
    function unstake(uint256 _sharesAmount) external nonReentrant {
        require(_sharesAmount > 0, "Cannot unstake 0");
        require(
            stHSK.balanceOf(msg.sender) >= _sharesAmount,
            "Insufficient stHSK balance"
        );

        // Update reward pool
        updateRewardPool();

        // Calculate HSK amount to return
        uint256 hskToReturn = getHSKForShares(_sharesAmount);

        // 计算原始质押金额和奖励部分
        // 对于普通质押，我们没有记录原始质押金额，所以需要估算
        // 使用当前的shares比例来估算原始质押部分
        uint256 totalShares = stHSK.totalSupply();
        uint256 originalStakeRatio = (_sharesAmount * BASIS_POINTS) /
            totalShares;
        uint256 originalStake = (totalPooledHSK * originalStakeRatio) /
            BASIS_POINTS;

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

        emit Unstake(
            msg.sender,
            _sharesAmount,
            hskToReturn,
            false,
            0,
            type(uint256).max
        );
    }

    /**
     * @notice 获取单笔质押的当前收益
     * @param _user 用户地址
     * @param _stakeId 质押ID
     * @return originalAmount 原始质押金额
     * @return reward 当前累积的收益金额
     * @return actualReward 考虑提前解锁惩罚后的实际收益
     * @return totalValue 质押的当前总价值（本金+收益）
     */
    function getStakeReward(
        address _user,
        uint256 _stakeId
    )
        external
        view
        returns (
            uint256 originalAmount,
            uint256 reward,
            uint256 actualReward,
            uint256 totalValue
        )
    {
        // 获取质押信息
        require(_stakeId < lockedStakes[_user].length, "Invalid stake ID");
        LockedStake storage userStake = lockedStakes[_user][_stakeId];

        // 检查质押是否存在
        require(userStake.sharesAmount > 0, "Stake amount is zero");

        // 如果质押已提取，返回零收益
        if (userStake.withdrawn) {
            return (userStake.hskAmount, 0, 0, 0);
        }

        // 计算当前HSK价值 - 复用getHSKForShares逻辑
        uint256 currentHskValue = getHSKForSharesByDuration(userStake.sharesAmount, userStake.lockDuration);

        // 原始质押金额
        originalAmount = userStake.hskAmount;

        // 计算收益 = 当前价值 - 原始质押金额
        if (currentHskValue > originalAmount) {
            reward = currentHskValue - originalAmount;
        } else {
            reward = 0;
        }

        // 计算实际收益（考虑提前解锁惩罚）
        actualReward = reward;

        // 如果是锁定质押且当前仍在锁定期内，计算提前解锁的惩罚
        if (block.timestamp < userStake.lockEndTime) {
            // 获取质押类型
            StakeType stakeType;
            if (userStake.lockDuration == 30 days)
                stakeType = StakeType.FIXED_30_DAYS;
            else if (userStake.lockDuration == 90 days)
                stakeType = StakeType.FIXED_90_DAYS;
            else if (userStake.lockDuration == 180 days)
                stakeType = StakeType.FIXED_180_DAYS;
            else if (userStake.lockDuration == 365 days)
                stakeType = StakeType.FIXED_365_DAYS;
            else stakeType = StakeType.FLEXIBLE;

            // 计算已经过的锁定期比例
            uint256 elapsedTime = block.timestamp -
                (userStake.lockEndTime - userStake.lockDuration);
            uint256 completionRatio = (elapsedTime * BASIS_POINTS) /
                userStake.lockDuration;

            // 调整惩罚比例（完成度越高，惩罚越低）
            uint256 adjustedPenalty = (earlyWithdrawalPenalty[stakeType] *
                (BASIS_POINTS - completionRatio)) / BASIS_POINTS;

            // 应用惩罚
            uint256 penalty = (reward * adjustedPenalty) / BASIS_POINTS;
            actualReward = reward - penalty;
        }

        // 计算总价值
        totalValue = currentHskValue;

        return (originalAmount, reward, actualReward, totalValue);
    }

    /**
     * @notice 获取单笔灵活质押的当前收益
     * @param _user 用户地址
     * @param _stakeId 质押ID
     * @return originalAmount 原始质押金额
     * @return reward 当前累积的收益金额
     * @return actualReward 考虑提前解锁惩罚后的实际收益（灵活质押无惩罚）
     * @return totalValue 质押的当前总价值（本金+收益）
     */
    function getFlexibleStakeReward(
        address _user,
        uint256 _stakeId
    )
        external
        view
        returns (
            uint256 originalAmount,
            uint256 reward,
            uint256 actualReward,
            uint256 totalValue
        )
    {
        // 获取质押信息
        require(_stakeId < flexibleStakes[_user].length, "Invalid stake ID");
        FlexibleStake storage userStake = flexibleStakes[_user][_stakeId];

        // 检查质押是否存在
        require(userStake.sharesAmount > 0, "Stake amount is zero");

        // 如果质押已提取，返回零收益
        if (userStake.status != FlexibleStakeStatus.STAKING) {
            return (userStake.hskAmount, 0, 0, 0);
        }

        // 计算当前HSK价值 - 复用getHSKForShares逻辑
        uint256 currentHskValue = getHSKForShares(userStake.sharesAmount);

        // 原始质押金额
        originalAmount = userStake.hskAmount;

        // 计算收益 = 当前价值 - 原始质押金额
        if (currentHskValue > originalAmount) {
            reward = currentHskValue - originalAmount;
        } else {
            reward = 0;
        }

        // 灵活质押没有提前解锁惩罚，因此 actualReward = reward
        actualReward = reward;

        // 计算总价值
        totalValue = currentHskValue;

        return (originalAmount, reward, actualReward, totalValue);
    }

    /**
     * @dev Stake HSK with flexible terms
     */
    function stakeFlexible() external payable nonReentrant whenNotPaused {
        require(msg.value >= minStakeAmount, "Amount below minimum stake");
        require(block.timestamp < stakeEndTime, "Staking ended");

        updateRewardPool1();

        uint256 sharesAmount = getSharesForHSK(msg.value);
        require(sharesAmount > 0, "Shares amount cannot be zero");

        if (!initialLiquidityMinted) {
            require(
                sharesAmount >= MINIMUM_LIQUIDITY,
                "Initial stake too small"
            );
            initialLiquidityMinted = true;
            stHSK.mint(
                0x000000000000000000000000000000000000dEaD,
                MINIMUM_LIQUIDITY
            );
            sharesAmount -= MINIMUM_LIQUIDITY;
        }

        totalPooledHSK += msg.value;
        totalSharesByStakeType[StakeType.FLEXIBLE] += sharesAmount;

        stHSK.mint(msg.sender, sharesAmount);

        flexibleStakes[msg.sender].push(
            FlexibleStake({
                sharesAmount: sharesAmount,
                hskAmount: msg.value,
                stakeBlock: block.number,
                status: FlexibleStakeStatus.STAKING
            })
        );

        uint256 stakeId = flexibleStakes[msg.sender].length - 1;
        emit Stake(
            msg.sender,
            msg.value,
            sharesAmount,
            StakeType.FLEXIBLE,
            0,
            stakeId
        );
    }

    /**
     * @dev Request to unstake a flexible stake
     * @param _stakeId The ID of the stake to unstake
     */
    function requestUnstakeFlexible(uint256 _stakeId) external nonReentrant {
        require(
            _stakeId < flexibleStakes[msg.sender].length,
            "Invalid stake ID"
        );
        FlexibleStake storage stake = flexibleStakes[msg.sender][_stakeId];

        require(
            stake.status == FlexibleStakeStatus.STAKING,
            "Stake not active"
        );
        require(
            block.number >= stake.stakeBlock + minWithdrawalRequestBlocks,
            "Too early to request withdrawal"
        );

        updateRewardPool1();

        uint256 sharesToBurn = stake.sharesAmount;
        uint256 hskToReturn = getHSKForShares(sharesToBurn);

        uint256 totalShares = stHSK.totalSupply();
        uint256 originalStakeRatio = (sharesToBurn * BASIS_POINTS) /
            totalShares;
        uint256 originalStake = (totalPooledHSK * originalStakeRatio) /
            BASIS_POINTS;
        if (originalStake > hskToReturn) {
            originalStake = hskToReturn;
        }
        uint256 rewardPart = hskToReturn - originalStake;
        // console.log('requestUnstakeFlexible: rewardPart', rewardPart);

        totalPooledHSK -= originalStake;
        if (rewardPart > 0) {
            if (rewardPart > totalPaidRewards) {
                rewardPart = totalPaidRewards;
            }
            totalPaidRewards -= rewardPart;
            totalPooledHSK -= rewardPart;
        }

        totalSharesByStakeType[StakeType.FLEXIBLE] -= sharesToBurn;

        stHSK.burn(msg.sender, sharesToBurn);

        uint256 claimableBlock = block.number + withdrawalWaitingBlocks;
        pendingWithdrawals[msg.sender].push(
            PendingWithdrawal({
                hskAmount: hskToReturn,
                claimableBlock: claimableBlock,
                claimed: false
            })
        );

        stake.status = FlexibleStakeStatus.WITHDRAWN;

        emit RequestUnstakeFlexible(
            msg.sender,
            _stakeId,
            hskToReturn,
            claimableBlock
        );
    }

    /**
     * @dev Claim a pending withdrawal
     * @param _withdrawalId The ID of the withdrawal to claim
     */
    function claimWithdrawal(uint256 _withdrawalId) external nonReentrant {
        require(
            _withdrawalId < pendingWithdrawals[msg.sender].length,
            "Invalid withdrawal ID"
        );
        PendingWithdrawal storage withdrawal = pendingWithdrawals[msg.sender][
            _withdrawalId
        ];

        require(!withdrawal.claimed, "Withdrawal already claimed");
        require(
            block.number >= withdrawal.claimableBlock,
            "Too early to claim"
        );

        withdrawal.claimed = true;

        bool success = safeHskTransfer(
            payable(msg.sender),
            withdrawal.hskAmount
        );
        require(success, "HSK transfer failed");

        emit WithdrawalClaimed(msg.sender, _withdrawalId, withdrawal.hskAmount);
    }

    /**
     * @dev Get user's flexible stake count
     * @param _user User address
     */
    function getUserFlexibleStakeCount(
        address _user
    ) external view returns (uint256) {
        return flexibleStakes[_user].length;
    }

    /**
     * @dev Get user's active (not withdrawn) flexible stake count
     * @param _user User address
     */
    function getUserActiveFlexibleStakes(
        address _user
    ) external view returns (uint256) {
        FlexibleStake[] storage userStakes = flexibleStakes[_user];
        uint256 activeStakes = 0;

        for (uint256 i = 0; i < userStakes.length; i++) {
            if (
                userStakes[i].status == FlexibleStakeStatus.STAKING &&
                userStakes[i].sharesAmount > 0
            ) {
                activeStakes++;
            }
        }

        return activeStakes;
    }

    /**
     * @dev Get flexible stake information
     * @param _user User address
     * @param _stakeId Stake ID
     */
    function getFlexibleStakeInfo(
        address _user,
        uint256 _stakeId
    )
        external
        view
        returns (
            uint256 sharesAmount,
            uint256 hskAmount,
            uint256 currentHskValue,
            uint256 stakeBlock,
            FlexibleStakeStatus stakingStatus
        )
    {
        require(_stakeId < flexibleStakes[_user].length, "Invalid stake ID");
        FlexibleStake storage stake = flexibleStakes[_user][_stakeId];

        return (
            stake.sharesAmount,
            stake.hskAmount,
            getHSKForShares(stake.sharesAmount),
            stake.stakeBlock,
            stake.status
        );
    }
}
