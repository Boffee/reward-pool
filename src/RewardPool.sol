// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Reward Pool
/// @author boffee
/// @author Modified from MasterChef V2 (https://github.com/1coinswap/core/blob/master/contracts/MasterChefV2.sol)
/// @notice This contract is used to manage reward pool.
contract RewardPool is ERC20, Ownable {
    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    uint256 public emissionRate; // total pool emission per second
    uint256 public emissionPerShare; // total accumulated reward emitted per share
    uint64 public lastUpdatedTimestamp; // last updated timestamp of the pool

    mapping(address => int256) internal _debts;

    constructor(string memory name, string memory symbol, address _stakeToken, address _rewardToken, address owner)
        ERC20(name, symbol)
        Ownable(owner)
    {
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        lastUpdatedTimestamp = uint64(block.timestamp);
    }

    /// @notice get pending reward for a given account.
    /// @param account Address of account.
    /// @return pending reward for a given account.
    function getPendingReward(address account) external view returns (uint256 pending) {
        uint256 emission =
            Math.min((block.timestamp - lastUpdatedTimestamp) * emissionRate, stakeToken.balanceOf(address(this)));
        uint256 _emissionPerShare = emissionPerShare + (emission * 1e18) / totalSupply();
        return uint256(int256((balanceOf(account) * _emissionPerShare) / 1e18) - _debts[account]);
    }

    /// @dev stake token and get pool token.
    /// @param amount The amount of token to be staked.
    function mint(uint256 amount) external {
        stakeToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    /// @dev burn pool token and get stake token.
    /// @param amount The amount of token to be burned.
    function burn(uint256 amount) external {
        stakeToken.transfer(msg.sender, amount);
        _burn(msg.sender, amount);
    }

    /// @dev Extract rewards for account.
    /// @param account Receiver of rewards.
    function extract(address account) external {
        _extract(account);
    }

    /// @notice Update pool info to the current timestamp.
    function updatePool() public {
        if (block.timestamp > lastUpdatedTimestamp) {
            uint256 emission =
                Math.min((block.timestamp - lastUpdatedTimestamp) * emissionRate, stakeToken.balanceOf(address(this)));
            emissionPerShare += (emission * 1e18) / totalSupply();
            lastUpdatedTimestamp = uint64(block.timestamp);
        }
    }

    /// @notice Update the given pool's reward rate.
    /// @param _emissionRate New emission rate of the pool.
    function setEmissionRate(uint256 _emissionRate) external onlyOwner {
        emissionRate = _emissionRate;
    }

    /// @dev update debt balance on mint, burn, and transfer
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0)) {
            _unstake(from, value);
        }
        if (to != address(0)) {
            _stake(to, value);
        }
        super._update(from, to, value);
    }

    /// @notice Stake amount under account to pool for reward allocation.
    /// @param account The receiver of reward allocations.
    /// @param amount The amount of token staked.
    function _stake(address account, uint256 amount) internal {
        updatePool();
        _debts[account] += int256((amount * emissionPerShare) / 1e18);
    }

    /// @notice Unstake account's token from pool.
    /// @param account Receiver of the reward.
    /// @param amount The amount of token unstaked.
    function _unstake(address account, uint256 amount) internal {
        updatePool();
        _debts[account] -= int256((amount * emissionPerShare) / 1e18);
    }

    /// @notice Extract rewards for account.
    /// @param account Receiver of rewards.
    function _extract(address account) internal {
        updatePool();

        int256 accumulatedReward = int256((balanceOf(account) * emissionPerShare) / 1e18);
        uint256 pendingReward = uint256(accumulatedReward - _debts[account]);

        _debts[account] = int128(accumulatedReward);
        rewardToken.transferFrom(address(this), account, pendingReward);
    }
}
