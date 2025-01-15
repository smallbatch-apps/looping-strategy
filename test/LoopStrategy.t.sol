// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {LoopingStrategy} from "../src/LoopStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract LoopStrategyTest is Test {
    LoopingStrategy public strategy;
    IPool public lendingPool;
    IERC20 public weth;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    // Constants for strategy parameters
    uint256 constant MAX_LTV_THRESHOLD = 7500;    // 75%
    uint256 constant WARNING_THRESHOLD = 8000;    // 80%
    uint256 constant EMERGENCY_THRESHOLD = 9500;  // 95%

    function setUp() public {
        // Deploy or get AAVE pool address for the network we're forking
        lendingPool = IPool(0xPool_Address_Here);
        weth = IERC20(0xWETH_Address_Here);
        
        // Deploy strategy
        strategy = new LoopingStrategy(
            address(lendingPool),
            address(weth),
            MAX_LTV_THRESHOLD,
            WARNING_THRESHOLD,
            EMERGENCY_THRESHOLD
        );
        
        // Give test users some WETH
        deal(address(weth), alice, 100 ether);
        deal(address(weth), bob, 100 ether);
    }

    // Constructor Tests
    function test_Constructor_SetsCorrectValues() public {
        assertEq(address(strategy.lendingPool()), address(lendingPool));
        assertEq(address(strategy.ethDerivative()), address(weth));
        // Test other constructor params...
    }

    function test_Constructor_RevertsOnInvalidThresholds() public {
        // Test invalid threshold combinations
        vm.expectRevert(LoopingStrategy.InvalidLtvThresholds.selector);
        new LoopingStrategy(
            address(lendingPool),
            address(weth),
            8000,  // MAX higher than WARNING
            7500,
            9500
        );
    }

    // Deposit Tests
    function test_Deposit_BasicFlow() public {
        uint256 depositAmount = 1 ether;
        
        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        
        // Calculate expected shares
        uint256 expectedShares = strategy.previewDeposit(depositAmount);
        
        strategy.deposit(
            address(weth),
            alice,
            alice,
            depositAmount,
            expectedShares,
            depositAmount  // baseAssets same as deposit for WETH
        );
        vm.stopPrank();
        
        assertEq(strategy.balanceOf(alice), expectedShares);
    }

    // Withdrawal Tests
    function test_Withdraw_BasicFlow() public {
        // First deposit
        test_Deposit_BasicFlow();
        
        uint256 shares = strategy.balanceOf(alice);
        uint256 expectedAssets = strategy.previewRedeem(shares);
        
        vm.startPrank(alice);
        strategy.withdraw(
            expectedAssets,
            alice,
            alice
        );
        vm.stopPrank();
        
        assertEq(strategy.balanceOf(alice), 0);
        assertEq(weth.balanceOf(alice), 100 ether); // Back to original balance
    }

    // Safety Check Tests
    function test_PositionCheck_UnderWarningThreshold() public {
        // Test normal operation
    }

    function test_PositionCheck_WarningThreshold() public {
        // Test warning level behavior
    }

    function test_PositionCheck_EmergencyThreshold() public {
        // Test emergency unwinding
    }

    // Looping Tests
    function test_LoopDeposit_SingleIteration() public {
        // Test basic looping behavior
    }

    function test_LoopDeposit_MultipleIterations() public {
        // Test multiple loop iterations
    }

    // Edge Cases and Failure Modes
    function test_RevertWhen_InvalidAsset() public {
        // Test depositing wrong asset
    }

    function test_RevertWhen_InsufficientApproval() public {
        // Test insufficient token approval
    }

    // Fuzz Tests
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0.1 ether && amount < 1000 ether);
        // Fuzz deposit amounts
    }

    function testFuzz_WithdrawPartial(uint256 sharePercentage) public {
        vm.assume(sharePercentage > 0 && sharePercentage <= 10000);
        // Fuzz partial withdrawals
    }

    // Integration Tests with AAVE
    function test_Integration_FullCycle() public {
        // Test full deposit -> loop -> withdraw cycle
    }

    // Helper functions
    function _depositAndLoop(address user, uint256 amount) internal {
        // Helper for common deposit+loop pattern
    }
}