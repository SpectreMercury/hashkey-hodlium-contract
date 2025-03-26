// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./StHSK.sol";

/**
 * @title HashKeyChainStakingStorage
 * @dev Modified storage contract for share-based model
 */
abstract contract HashKeyChainStakingStorage {
    // Flexible staking status enum
    enum FlexibleStakeStatus { STAKING, PENDING_WITHDRAWAL, WITHDRAWN }

    // Flexible stake structure
    struct FlexibleStake {
        uint256 sharesAmount;    // Amount of stHSK shares
        uint256 hskAmount;       // Amount of HSK staked
        uint256 stakeBlock;      // Block number when staked
        FlexibleStakeStatus status; // Current status of the stake
    }

    // Pending withdrawal structure
    struct PendingWithdrawal {
        uint256 hskAmount;       // Amount of HSK to withdraw
        uint256 claimableBlock;  // Block when withdrawal can be claimed
        bool claimed;            // Whether the withdrawal has been claimed
    }
    
    // Locked stake information
    struct LockedStake {
        uint256 sharesAmount;       // Amount of locked shares
        uint256 hskAmount;          // Original HSK amount staked (for record only)
        uint256 lockEndTime;        // Lock period end time
        uint256 lockDuration;       // Lock duration (seconds)
        bool withdrawn;             // Whether withdrawn
    }

     // Mapping of user addresses to their flexible stakes
    mapping(address => FlexibleStake[]) public flexibleStakes;
    // Mapping of user addresses to their pending withdrawals
    mapping(address => PendingWithdrawal[]) public pendingWithdrawals;

    // Minimum blocks before a withdrawal can be requested
    uint256 public minWithdrawalRequestBlocks;
    // Blocks to wait after requesting withdrawal (2 weeks)
    uint256 public withdrawalWaitingBlocks;

    // Stake types
    enum StakeType { FIXED_30_DAYS, FIXED_90_DAYS, FIXED_180_DAYS, FIXED_365_DAYS, FLEXIBLE }

    // Constants
    uint256 internal constant PRECISION_FACTOR = 1e18;
    uint256 internal constant MAX_PENALTY = 5000;      // Maximum penalty: 50%
    uint256 internal constant BASIS_POINTS = 10000;    // 100% in basis points
    uint256 internal constant MAX_APR = 3000;         // Maximum APR: 30%
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;  // 最小流动性，防止第一个质押者操纵
    uint256 internal constant MINIMUM_SHARES_THRESHOLD = 1e16;  // 最小份额阈值，防止汇率计算异常

    // 是否已经初始化最小流动性
    bool public initialLiquidityMinted;

    // Configurable block time
    uint256 public blockTime;  // Block time in seconds

    // stHSK token
    StHSK public stHSK;
    
    // Total HSK in pool (including rewards)
    uint256 public totalPooledHSK;
    
    // Block reward configuration
    uint256 public hskPerBlock;
    uint256 public lastRewardBlock;
    uint256 public startBlock;
    uint256 public maxHskPerBlock;
    
    // Locked stake records (only for fixed lock period stakes)
    mapping(address => LockedStake[]) public lockedStakes;
    
    // Reserved rewards (contract balance - total staked)
    uint256 public reservedRewards;
    
    // Minimum stake amount
    uint256 public minStakeAmount;
    
    // Early withdrawal penalty rates (basis points, 1000 = 10%)
    mapping(StakeType => uint256) public earlyWithdrawalPenalty;
    
    // Base reward bonus for different staking periods (basis points)
    mapping(StakeType => uint256) public stakingBonus;
    
    // Staking end time
    uint256 public stakeEndTime;
    
    // Contract version
    uint256 public version;

    uint256 public annualRewardsBudget;
    
    // 跟踪每种锁定期类型的质押总量（以shares计算）
    mapping(StakeType => uint256) public totalSharesByStakeType;
    mapping(StakeType => uint256) public totalSharesByStakeType1111;
    
    // 跟踪未锁定质押的总量（以shares计算）
    uint256 public totalUnlockedShares;
    
    // 跟踪已支付的奖励总量
    uint256 public totalPaidRewards;

    mapping(StakeType => uint256) public poolWeight;
}