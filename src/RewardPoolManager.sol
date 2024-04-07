// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {RewardPool} from "./RewardPool.sol";

contract RewardPoolManager {
    function createPool(string memory name, string memory symbol, address stakeToken, address rewardToken)
        external
        returns (address pool)
    {
        return Create2.deploy(
            0, 0, abi.encodePacked(type(RewardPool).creationCode, abi.encode(name, symbol, stakeToken, rewardToken))
        );
    }
}
