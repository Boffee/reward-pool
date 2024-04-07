// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../src/RewardPoolManager.sol";
import "./mocks/MockERC20.sol";

contract RewardPoolTest is Test {
    RewardPoolManager manager;
    MockERC20 stakeToken;
    MockERC20 rewardToken;

    address alice = address(bytes20(keccak256("alice")));
    address bob = address(bytes20(keccak256("bob")));
    address carol = address(bytes20(keccak256("carol")));

    function setUp() public {
        manager = new RewardPoolManager();
        stakeToken = new MockERC20("Stake Token", "STK");
        rewardToken = new MockERC20("Reward Token", "RWD");
    }

    function test() public {
        address pool = manager.createPool("name", "symbol", address(stakeToken), address(rewardToken), address(this));
        RewardPool rewardPool = RewardPool(pool);

        // setup pool
        rewardPool.setEmissionRate(100);
        rewardToken.mint(address(rewardPool), 100 ether);

        // setup users
        stakeToken.mint(alice, 10 ether);
        stakeToken.mint(bob, 10 ether);
        stakeToken.mint(carol, 10 ether);
        vm.prank(alice);
        stakeToken.approve(address(rewardPool), type(uint256).max);
        vm.prank(bob);
        stakeToken.approve(address(rewardPool), type(uint256).max);
        vm.prank(carol);
        stakeToken.approve(address(rewardPool), type(uint256).max);

        // test stake
        vm.prank(alice);
        rewardPool.mint(4 ether);
        vm.prank(bob);
        rewardPool.mint(1 ether);
        vm.prank(carol);
        rewardPool.mint(5 ether);

        // check pending rewards
        vm.warp(block.timestamp + 10);
        assertEq(rewardPool.getPendingReward(alice), 400);
        assertEq(rewardPool.getPendingReward(bob), 100);
        assertEq(rewardPool.getPendingReward(carol), 500);

        // test unstake
        vm.prank(carol);
        rewardPool.burn(2 ether);
        assertEq(rewardPool.getPendingReward(alice), 400);
        assertEq(rewardPool.getPendingReward(bob), 100);
        assertEq(rewardPool.getPendingReward(carol), 500);

        // check pending rewards
        vm.warp(block.timestamp + 10);
        assertEq(rewardPool.getPendingReward(alice), 900);
        assertEq(rewardPool.getPendingReward(bob), 225);
        assertEq(rewardPool.getPendingReward(carol), 875);

        // test extract
        vm.prank(alice);
        rewardPool.extract(alice);
        assertEq(rewardToken.balanceOf(alice), 900);
        assertEq(rewardPool.getPendingReward(alice), 0);
        vm.prank(bob);
        rewardPool.extract(bob);
        assertEq(rewardToken.balanceOf(bob), 225);
        assertEq(rewardPool.getPendingReward(bob), 0);
        vm.prank(carol);
        rewardPool.extract(carol);
        assertEq(rewardToken.balanceOf(carol), 875);
        assertEq(rewardPool.getPendingReward(carol), 0);
    }
}
