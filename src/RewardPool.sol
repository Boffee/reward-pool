// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Reward Pool
/// @author boffee
/// @author Modified from MasterChef V2 (https://github.com/1coinswap/core/blob/master/contracts/MasterChefV2.sol)
/// @notice This contract is used to manage reward pool.
contract RewardPool is ERC20 {
    struct PoolInfo {
        uint256 emissionRate; // total pool emission per second
        uint256 emissionPerShare; // total accumulated reward emitted per share
        uint64 lastUpdatedTimestamp; // last updated timestamp of the pool
    }

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    PoolInfo internal _poolInfo;

    mapping(address => int256) internal _debts;

    constructor(string memory name, string memory symbol, address _stakeToken, address _rewardToken)
        ERC20(name, symbol)
    {
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        _poolInfo.lastUpdatedTimestamp = uint64(block.timestamp);
    }

    /// @notice get pending reward for a given account.
    /// @param account Address of account.
    /// @return pending reward for a given account.
    function getPendingReward(address account) external view returns (uint256 pending) {
        PoolInfo memory poolInfo = getUpdatedPoolInfo();

        return uint256(int256((balanceOf(account) * poolInfo.emissionPerShare) / 1e18) - _debts[account]);
    }

    /// @notice get pool info
    /// @return poolInfo
    function getPoolInfo() public view returns (PoolInfo memory) {
        return _poolInfo;
    }

    /// @notice get pool info updated to the current timestamp
    function getUpdatedPoolInfo() public view returns (PoolInfo memory) {
        PoolInfo memory poolInfo = _poolInfo;

        if (block.timestamp <= poolInfo.lastUpdatedTimestamp) return poolInfo;

        uint256 emission = Math.min(
            (block.timestamp - poolInfo.lastUpdatedTimestamp) * poolInfo.emissionRate,
            stakeToken.balanceOf(address(this))
        );
        poolInfo.emissionPerShare += (emission * 1e18) / totalSupply();
        poolInfo.lastUpdatedTimestamp = uint64(block.timestamp);

        return poolInfo;
    }

    function mint(uint256 amount) external {
        stakeToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        stakeToken.transfer(msg.sender, amount);
        _burn(msg.sender, amount);
    }

    /// @notice Update pool info to the current timestamp.
    function updatePool() public {
        if (block.timestamp > _poolInfo.lastUpdatedTimestamp) {
            _poolInfo = getUpdatedPoolInfo();
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0)) {
            _unstake(from, value);
        }
        if (to != address(0)) {
            _stake(to, value);
        }
    }

    /// @notice Stake amount under account to pool for reward allocation.
    /// @param account The receiver of reward allocations.
    /// @param amount The amount of token staked.
    function _stake(address account, uint256 amount) internal {
        updatePool();
        _debts[account] += int256((amount * _poolInfo.emissionPerShare) / 1e18);
    }

    /// @notice Unstake account's token from pool.
    /// @param account Receiver of the reward.
    /// @param amount The amount of token unstaked.
    function _unstake(address account, uint256 amount) internal {
        updatePool();
        _debts[account] -= int256((amount * _poolInfo.emissionPerShare) / 1e18);
    }

    /// @notice Extract rewards for account.
    /// @param account Receiver of rewards.
    function _extract(address account) internal {
        updatePool();

        int256 accumulatedReward = int256((balanceOf(account) * _poolInfo.emissionPerShare) / 1e18);
        uint256 pendingReward = uint256(accumulatedReward - _debts[account]);

        _debts[account] = int128(accumulatedReward);
        rewardToken.transferFrom(address(this), account, pendingReward);
    }

    /// @notice Update the given pool's reward rate.
    /// @param emissionRate New emission rate of the pool.
    function _setEmissionRate(uint256 emissionRate) internal {
        _poolInfo.emissionRate = uint64(emissionRate);
    }

    /// @notice Add reward token to the pool
    /// @param account The account that sends the reward.
    /// @param amount The amount of reward to be added.
    function _addReward(address account, uint256 amount) internal {
        require(_poolInfo.lastUpdatedTimestamp != 0, "Pool does not exist");

        rewardToken.transferFrom(account, address(this), amount);
    }
}
