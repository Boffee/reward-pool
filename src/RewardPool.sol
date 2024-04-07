// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Reward Pool
/// @author boffee
/// @author Modified from MasterChef V2 (https://github.com/1coinswap/core/blob/master/contracts/MasterChefV2.sol)
/// @notice This contract is used to manage reward pools.
abstract contract RewardPool {
    struct AccountInfo {
        uint256 shares; // shares staked by the account
        int256 emissionDebt; // accounting trick for variable emissions
    }

    struct PoolInfo {
        uint256 emissionRate; // total pool emission per second
        uint256 emissionPerShare; // total reward emitted per share
        uint256 totalShares; // total shares staked in the pool
        uint256 totalBalance; // remaining reward balance
        uint64 lastUpdatedTimestamp; // last updated timestamp of the pool
    }

    event SetAccount(address indexed account, uint256 indexed poolId, AccountInfo accountInfo);
    event SetPool(uint256 indexed poolId, PoolInfo poolInfo);

    /// @notice Info of each pool.
    mapping(uint256 => PoolInfo) private _poolInfos;

    /// @notice Info of each account in each pool.
    mapping(uint256 => mapping(address => AccountInfo)) private _accountInfos;

    /// @notice The reward token.
    IERC20 public rewardToken;

    /// @notice get pending reward for a given account.
    /// @param account Address of account.
    /// @param poolId id of the pool.
    /// @return pending reward for a given account.
    function getPendingReward(address account, uint256 poolId) external view returns (uint256 pending) {
        PoolInfo memory poolInfo = getUpdatedPoolInfo(poolId);
        AccountInfo memory accountInfo = getAccountInfo(poolId, account);

        return uint256(int256((accountInfo.shares * poolInfo.emissionPerShare) / 1e18) - accountInfo.emissionDebt);
    }

    /// @notice get pool info
    /// @param poolId id of the pool.
    /// @return poolInfo
    function getPoolInfo(uint256 poolId) public view returns (PoolInfo memory) {
        return _poolInfos[poolId];
    }

    /// @notice get pool info updated to the current timestamp
    /// @param poolId id of the pool.
    /// @return poolInfo
    function getUpdatedPoolInfo(uint256 poolId) public view returns (PoolInfo memory) {
        PoolInfo memory poolInfo = _poolInfos[poolId];

        if (block.timestamp <= poolInfo.lastUpdatedTimestamp) return poolInfo;

        uint256 emission =
            Math.min((block.timestamp - poolInfo.lastUpdatedTimestamp) * poolInfo.emissionRate, poolInfo.totalBalance);
        poolInfo.totalBalance -= emission;
        poolInfo.emissionPerShare += (emission * 1e18) / poolInfo.totalShares;
        poolInfo.lastUpdatedTimestamp = uint64(block.timestamp);

        return poolInfo;
    }

    /// @notice get account info
    /// @param poolId id of the pool.
    /// @param account id of the account. See `_accountInfos`.
    /// @return accountInfo
    function getAccountInfo(uint256 poolId, address account) public view returns (AccountInfo memory) {
        return _accountInfos[poolId][account];
    }

    /// @notice Update pool info to the current timestamp.
    /// @param poolId id of the pool.
    /// @return poolInfo Returns the pool that was updated.
    function updatePool(uint256 poolId) public returns (PoolInfo memory) {
        if (block.timestamp > _poolInfos[poolId].lastUpdatedTimestamp) {
            _poolInfos[poolId] = getUpdatedPoolInfo(poolId);
            emit SetPool(poolId, _poolInfos[poolId]);
        }

        return _poolInfos[poolId];
    }

    /// @notice Stake shares under account to pool for reward allocation.
    /// @param account The receiver of reward allocations.
    /// @param poolId id of the pool.
    /// @param shares The amount of shares to be docked.
    function _stake(address account, uint256 poolId, uint256 shares) internal {
        PoolInfo memory poolInfo = updatePool(poolId);
        AccountInfo storage accountInfo = _accountInfos[poolId][account];

        accountInfo.shares += shares;
        accountInfo.emissionDebt += int256((shares * poolInfo.emissionPerShare) / 1e18);
        _poolInfos[poolId].totalShares += shares;

        emit SetAccount(account, poolId, _accountInfos[poolId][account]);
    }

    /// @notice Unstake account's shares from pool.
    /// @param account Receiver of the reward.
    /// @param poolId id of the pool.
    /// @param shares Extractor shares to undock.
    function _unstake(address account, uint256 poolId, uint256 shares) internal {
        PoolInfo memory poolInfo = updatePool(poolId);
        AccountInfo storage accountInfo = _accountInfos[poolId][account];

        accountInfo.emissionDebt -= int256((shares * poolInfo.emissionPerShare) / 1e18);
        accountInfo.shares -= shares;
        _poolInfos[poolId].totalShares -= shares;

        emit SetAccount(account, poolId, _accountInfos[poolId][account]);
    }

    /// @notice Extract proceeds for account.
    /// @param account Receiver of rewards.
    /// @param poolId id of the pool.
    function _extract(address account, uint256 poolId) internal {
        PoolInfo memory poolInfo = updatePool(poolId);
        AccountInfo storage accountInfo = _accountInfos[poolId][account];
        int256 accumulatedReward = int256((accountInfo.shares * uint256(poolInfo.emissionPerShare)) / 1e18);
        uint256 _pendingReward = uint256(accumulatedReward - accountInfo.emissionDebt);

        accountInfo.emissionDebt = int128(accumulatedReward);
        rewardToken.transferFrom(address(this), account, _pendingReward);

        emit SetAccount(account, poolId, _accountInfos[poolId][account]);
    }

    /// @notice Unstake without caring about rewards. EMERGENCY ONLY.
    /// @param account Receiver of the reward.
    /// @param poolId id of the pool.
    function _emergencyUnstake(address account, uint256 poolId) internal {
        uint256 shares = _accountInfos[poolId][account].shares;
        if (_poolInfos[poolId].totalShares >= shares) {
            _poolInfos[poolId].totalShares -= shares;
        }

        delete _accountInfos[poolId][account];

        emit SetAccount(account, poolId, _accountInfos[poolId][account]);
    }

    /// @notice Create a new pool.
    /// @param poolId The id of the pool.
    /// @param emissionRate reward rate of the new pool.
    function _createPool(uint256 poolId, uint256 emissionRate) internal {
        require(_poolInfos[poolId].lastUpdatedTimestamp == 0, "Pool already exists");

        _poolInfos[poolId] = PoolInfo({
            emissionRate: emissionRate,
            emissionPerShare: 0,
            totalShares: 0,
            totalBalance: 0,
            lastUpdatedTimestamp: uint64(block.timestamp)
        });

        emit SetPool(poolId, _poolInfos[poolId]);
    }

    /// @notice Update the given pool's reward rate.
    /// @param poolId The id of the pool.
    /// @param emissionRate New emission rate of the pool.
    function _setEmissionRate(uint256 poolId, uint256 emissionRate) internal {
        _poolInfos[poolId].emissionRate = uint64(emissionRate);

        emit SetPool(poolId, _poolInfos[poolId]);
    }

    /// @notice Add reward token to the pool
    /// @param account The account that sends the reward.
    /// @param poolId The id of the pool.
    /// @param amount The amount of reward to be added.
    function _addReward(address account, uint256 poolId, uint256 amount) internal {
        require(_poolInfos[poolId].lastUpdatedTimestamp != 0, "Pool does not exist");

        rewardToken.transferFrom(account, address(this), amount);
        _poolInfos[poolId].totalBalance += amount;

        emit SetPool(poolId, _poolInfos[poolId]);
    }
}
