// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./StHSK.sol";
import "./HashKeyChainStakingOperations.sol";
import "./HashKeyChainStakingAdmin.sol";
import "./HashKeyChainStakingEmergency.sol";
import 'hardhat/console.sol';

/**
 * @title HashKeyChainStaking
 * @dev Main staking contract, based on share model, users can choose locked or unlocked staking
 */
contract HashKeyChainStaking is 
    Initializable,
    HashKeyChainStakingOperations,
    HashKeyChainStakingAdmin,
    HashKeyChainStakingEmergency
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Initialize the contract
    * @param _hskPerBlock HSK reward per block
    * @param _startBlock Starting block
    * @param _maxHskPerBlock Maximum reward per block
    * @param _minStakeAmount Minimum staking amount
    * @param _annualBudget Annual budget (optional, if 0 it will be calculated based on hskPerBlock)
    * @param _blockTime Block time in seconds
    */
    function initialize(
        uint256 _hskPerBlock,
        uint256 _startBlock,
        uint256 _maxHskPerBlock,
        uint256 _minStakeAmount,
        uint256 _annualBudget,
        uint256 _blockTime
    ) public reinitializer(2) {
        // Validate inputs before proceeding
        require(_hskPerBlock > 0, "HSK per block must be positive");
        require(_startBlock >= block.number, "Start block must be in the future");
        require(_maxHskPerBlock >= _hskPerBlock, "Max HSK per block must be >= HSK per block");
        require(_minStakeAmount > 0, "Min stake amount must be positive");
        require(_blockTime > 0, "Block time must be positive");
        
        __HashKeyChainStakingBase_init(
            _hskPerBlock,
            _startBlock,
            _maxHskPerBlock,
            _minStakeAmount,
            _blockTime
        );
        
        if (_annualBudget > 0) {
            annualRewardsBudget = _annualBudget;
        }
             // 380697
        totalSharesByStakeType1111[StakeType.FIXED_30_DAYS] = 380697415865318151940279;
        // 40522
        totalSharesByStakeType1111[StakeType.FIXED_90_DAYS] = 40522325217718024972930;
        // 175815
        totalSharesByStakeType1111[StakeType.FIXED_180_DAYS] = 175815835251004603378963;
        // 3115240
        totalSharesByStakeType1111[StakeType.FIXED_365_DAYS] = 3115240333249525764629109;
        // 75221
        totalSharesByStakeType1111[StakeType.FLEXIBLE] = 75221837962222264146341;
    // 3979015
    // totalPooledHSK = 3797015810476053937368361

      // / 获取最大APR值
        uint256[5] memory maxAPRs;
        maxAPRs[0] = 360;   // MAX_APR_30_DAYS - 3.6%
        maxAPRs[1] = 1000;  // MAX_APR_90_DAYS - 10% 
        maxAPRs[2] = 1800;  // MAX_APR_180_DAYS - 18%
        maxAPRs[3] = 3600;  // MAX_APR_365_DAYS - 36%
        maxAPRs[4] = 180;   // MAX_APR_FLEXIBLE - 1.8%
        
        // 计算每种池的权重
        for (uint256 i = 0; i < 5; i++) {
            StakeType stakeType = StakeType(i);
            poolWeight[stakeType] = maxAPRs[i] * 10000 / 180;
        }
        console.log(poolWeight[StakeType.FIXED_30_DAYS], 'poolWeight[0]');
        console.log(poolWeight[StakeType.FIXED_90_DAYS], 'poolWeight[1]');
        console.log(poolWeight[StakeType.FIXED_180_DAYS], 'poolWeight[2]');
        console.log(poolWeight[StakeType.FIXED_365_DAYS], 'poolWeight[3]');
        console.log(poolWeight[StakeType.FLEXIBLE], 'poolWeight[4]');

        // 更新版本号
        version = 2;
        emit StakingContractUpgraded(version);
    }

    /**
     * @dev Set staking end time
     * @param _endTime New end time
     */
    function setStakeEndTime(uint256 _endTime) external onlyOwner {
        require(_endTime > block.timestamp, "End time must be in future");
        stakeEndTime = _endTime;
    }

    /**
     * @dev Check if staking is open
     */
    function isStakingOpen() public view returns (bool) {
        return block.timestamp < stakeEndTime;
    }

    /**
     * @dev Get current stHSK exchange rate (1 stHSK = ? HSK)
     */
    function getCurrentExchangeRate() external view returns (uint256) {
        return getHSKForShares(PRECISION_FACTOR);
    }

    /**
     * @dev Get user's locked stake count
     * @param _user User address
     */
    function getUserLockedStakeCount(address _user) external view returns (uint256) {
        return lockedStakes[_user].length;
    }

    /**
     * @dev Get user's active (not withdrawn) locked stake count
     * @param _user User address
     */
    function getUserActiveLockedStakes(address _user) external view returns (uint256) {
        LockedStake[] storage userStakes = lockedStakes[_user];
        uint256 activeStakes = 0;
        
        for (uint256 i = 0; i < userStakes.length; i++) {
            if (!userStakes[i].withdrawn && userStakes[i].sharesAmount > 0) {
                activeStakes++;
            }
        }
        
        return activeStakes;
    }

    /**
     * @dev Get locked stake information
     * @param _user User address
     * @param _stakeId Stake ID
     */
    function getLockedStakeInfo(address _user, uint256 _stakeId) external view returns (
        uint256 sharesAmount,
        uint256 hskAmount,
        uint256 currentHskValue,
        uint256 lockEndTime,
        bool isWithdrawn,
        bool isLocked
    ) {
        require(_stakeId < lockedStakes[_user].length, "Invalid stake ID");
        LockedStake storage stake = lockedStakes[_user][_stakeId];
        
        return (
            stake.sharesAmount,
            stake.hskAmount,
            getHSKForShares(stake.sharesAmount),
            stake.lockEndTime,
            stake.withdrawn,
            block.timestamp < stake.lockEndTime
        );
    }

    /**
     * @dev Get total value locked in the contract
     */
    function totalValueLocked() external view returns (uint256) {
        return totalPooledHSK;
    }

    /**
     * @dev Get APRs for all staking durations
     * @param _stakeAmount Simulated staking amount
     */
    function getAllStakingAPRs(uint256 _stakeAmount) external view returns (
        uint256[5] memory estimatedAPRs,
        uint256[5] memory maxAPRs
    ) {
        estimatedAPRs[0] = getCurrentAPR(_stakeAmount, StakeType.FIXED_30_DAYS);
        estimatedAPRs[1] = getCurrentAPR(_stakeAmount, StakeType.FIXED_90_DAYS);
        estimatedAPRs[2] = getCurrentAPR(_stakeAmount, StakeType.FIXED_180_DAYS);
        estimatedAPRs[3] = getCurrentAPR(_stakeAmount, StakeType.FIXED_365_DAYS);
        estimatedAPRs[4] = getCurrentAPR(_stakeAmount, StakeType.FLEXIBLE);
        
        maxAPRs[0] = 360;   // MAX_APR_30_DAYS - 修改为3.6%
        maxAPRs[1] = 1000;  // MAX_APR_90_DAYS - 修改为10% 
        maxAPRs[2] = 1800;  // MAX_APR_180_DAYS - 修改为18%
        maxAPRs[3] = 3600;  // MAX_APR_365_DAYS - 修改为36%
        maxAPRs[4] = 180;   // MAX_APR_FLEXIBLE - 修改为1.8%

        return (estimatedAPRs, maxAPRs);
    }

    /**
     * @dev Get detailed staking statistics
     * @param _simulatedStakeAmount Simulated staking amount
     */
    function getDetailedStakingStats(uint256 _simulatedStakeAmount) external view returns (
        uint256 totalStakedAmount,
        uint256[5] memory durations,
        uint256[5] memory currentAPRs,
        uint256[5] memory maxPossibleAPRs,
        uint256[5] memory baseBonus
    ) {
        totalStakedAmount = totalPooledHSK;
        
        // Set different staking durations (seconds)
        durations[0] = 30 days;
        durations[1] = 90 days;
        durations[2] = 180 days;
        durations[3] = 365 days;
        durations[4] = 0;
        // Base bonuses
        baseBonus[0] = stakingBonus[StakeType.FIXED_30_DAYS];
        baseBonus[1] = stakingBonus[StakeType.FIXED_90_DAYS];
        baseBonus[2] = stakingBonus[StakeType.FIXED_180_DAYS];
        baseBonus[3] = stakingBonus[StakeType.FIXED_365_DAYS];
        baseBonus[4] = stakingBonus[StakeType.FLEXIBLE];
        
        // Maximum possible APRs - 更新为新的最大APR值
        maxPossibleAPRs[0] = 360;   // MAX_APR_30_DAYS - 3.6%
        maxPossibleAPRs[1] = 1000;  // MAX_APR_90_DAYS - 10%
        maxPossibleAPRs[2] = 1800;  // MAX_APR_180_DAYS - 18%
        maxPossibleAPRs[3] = 3600;  // MAX_APR_365_DAYS - 36%
        maxPossibleAPRs[4] = 180;   // MAX_APR_FLEXIBLE - 1.8%
        
        // Calculate current estimated APRs
        currentAPRs[0] = getCurrentAPR(_simulatedStakeAmount, StakeType.FIXED_30_DAYS);
        currentAPRs[1] = getCurrentAPR(_simulatedStakeAmount, StakeType.FIXED_90_DAYS);
        currentAPRs[2] = getCurrentAPR(_simulatedStakeAmount, StakeType.FIXED_180_DAYS);
        currentAPRs[3] = getCurrentAPR(_simulatedStakeAmount, StakeType.FIXED_365_DAYS);
        currentAPRs[4] = getCurrentAPR(_simulatedStakeAmount, StakeType.FLEXIBLE);

        return (totalStakedAmount, durations, currentAPRs, maxPossibleAPRs, baseBonus);
    }

    /**
     * @dev Get HSK staking APR information
     * @param _stakeAmount Simulated staking amount
     */
    function getHSKStakingAPR(uint256 _stakeAmount) public view returns (
        uint256 baseApr,
        uint256 minApr,
        uint256 maxApr
    ) {
        // Calculate base APR - using annual budget
        uint256 yearlyRewards = annualRewardsBudget;
        
        if (totalPooledHSK == 0) {
            // Use a reasonable initial stake amount for calculation
            uint256 initialStake = minStakeAmount > 0 ? minStakeAmount : 100 ether;
            // Calculate APR based on this initial stake
            baseApr = (yearlyRewards * BASIS_POINTS) / initialStake;
            
            // Cap at MAX_APR_365_DAYS
            if (baseApr > MAX_APR) {
                baseApr = MAX_APR > 3600 ? 3600 : MAX_APR; // MAX_APR_365_DAYS = 3600
            }
            
            // Minimum APR for 30-day lock
            minApr = (baseApr + stakingBonus[StakeType.FIXED_30_DAYS]) > 360 ? 
                360 : (baseApr + stakingBonus[StakeType.FIXED_30_DAYS]);
            
            // Maximum APR for 365-day lock
            maxApr = (baseApr + stakingBonus[StakeType.FIXED_365_DAYS]) > 3600 ? 
                3600 : (baseApr + stakingBonus[StakeType.FIXED_365_DAYS]);
            

            return (baseApr, minApr, maxApr);
        }
        
        uint256 newTotal = totalPooledHSK + _stakeAmount;
        baseApr = (yearlyRewards * BASIS_POINTS) / newTotal;
        
        // Minimum APR for 30-day lock
        minApr = (baseApr + stakingBonus[StakeType.FIXED_30_DAYS]) > 360 ? 
            360 : (baseApr + stakingBonus[StakeType.FIXED_30_DAYS]);
        
        // Maximum APR for 365-day lock
        maxApr = (baseApr + stakingBonus[StakeType.FIXED_365_DAYS]) > 3600 ? 
            3600 : (baseApr + stakingBonus[StakeType.FIXED_365_DAYS]);
        
        return (baseApr, minApr, maxApr);
    }

    /**
     * @dev Callback function for receiving HSK
     */
    receive() external payable {
        // Treat received HSK as rewards
        reservedRewards += msg.value;
        emit RewardsAdded(msg.value, msg.sender);
    }
}