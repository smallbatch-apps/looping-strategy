// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {LoopingStrategy} from "../src/LoopingStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockPool} from "./mocks/MockPool.sol";

import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";

contract LoopStrategyTest is Test {
    LoopingStrategy public strategy;
    IPool public lendingPool;
    IERC20 public weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant MAX_LTV_THRESHOLD = 7500; // 75%
    uint256 constant WARNING_THRESHOLD = 8000; // 80%
    uint256 constant EMERGENCY_THRESHOLD = 9500; // 95%

    function setUp() public {
        // Create core contracts
        MockPool mockPool = new MockPool(IPoolAddressesProvider(address(0)));

        lendingPool = IPool(address(mockPool));

        weth = IERC20(address(new MockERC20("Wrapped Ether", "WETH")));
        // Pre-fund the mock pool with enough tokens
        deal(address(weth), address(lendingPool), 100 ether);

        // Deploy strategy
        LoopingStrategy implementation = new LoopingStrategy(
            address(lendingPool),
            address(weth),
            MAX_LTV_THRESHOLD,
            WARNING_THRESHOLD,
            EMERGENCY_THRESHOLD
        );

        bytes memory initData = abi.encodeWithSelector(
            LoopingStrategy.initialize.selector
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            initData
        );
        strategy = LoopingStrategy(payable(address(proxy)));

        // Setup provider and assets
        vm.startPrank(address(this));
        MockProvider mockProvider = new MockProvider();
        mockProvider.setRate(address(weth), 1e18);
        strategy.setProvider(address(mockProvider));
        strategy.addAsset(address(weth), true);
        strategy.unpause();
        vm.stopPrank();

        vm.prank(alice);
        MockERC20(address(weth)).mint(100 ether);
        vm.prank(bob);
        MockERC20(address(weth)).mint(100 ether);
    }

    function test_Deposit_BasicFlow() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertApproxEqRel(
            totalDebt,
            3 ether, // ~3x leverage through looping
            4e16, // Allow for some rounding
            "Should achieve ~3x leverage through looping"
        );
    }

    function test_Deposit_1Ether() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
            .getUserAccountData(address(strategy));
        assertGt(
            totalCollateral,
            depositAmount,
            "Should have more collateral after looping"
        );
        assertApproxEqRel(
            totalDebt,
            2.85 ether, // ~3x leverage through looping
            4e16, // Allow for some rounding
            "Should achieve ~3x leverage through looping"
        );
    }

    function test_Deposit_2Ether() public {
        uint256 depositAmount = 2 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        assertApproxEqRel(
            totalDebt,
            5.66 ether, // ~3x leverage on 2 ETH
            4e16, // Allow for some rounding
            "Should achieve ~3x leverage through looping"
        );
    }

    function test_Deposit_5Ether() public {
        uint256 depositAmount = 5 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        assertApproxEqRel(
            totalDebt,
            14.15 ether, // ~3x leverage on 5 ETH
            4e16, // Allow for some rounding
            "Should achieve ~3x leverage through looping"
        );
    }

    function test_Deposit_MultipleTimes() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount * 2);

        // First deposit
        strategy.deposit(depositAmount, alice);
        (, uint256 totalDebt1, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertApproxEqRel(
            totalDebt1,
            3 ether,
            4e16,
            "First deposit should achieve ~3x leverage"
        );

        // Second deposit
        strategy.deposit(depositAmount, alice);
        (, uint256 totalDebt2, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertApproxEqRel(
            totalDebt2,
            6 ether,
            4e16,
            "Second deposit should achieve ~6x total debt"
        );

        vm.stopPrank();
    }

    function test_Deposit_VerifyBorrowing() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertApproxEqRel(
            totalDebt,
            3 ether, // ~3x leverage through looping with 75% LTV
            4e16, // Allow for some rounding
            "Should borrow ~3x through repeated 75% LTV borrows"
        );
    }

    function test_Deposit_MultipleUsers() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(strategy), 2 ether);
        strategy.deposit(2 ether, bob);
        vm.stopPrank();

        assertEq(strategy.balanceOf(alice), 1 ether);
        assertEq(strategy.balanceOf(bob), 2 ether);
    }

    function test_Deposit_ZeroAmount() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 0);
        vm.expectRevert(); // Should revert with zero amount
        strategy.deposit(0, alice);
        vm.stopPrank();
    }

    function test_Deposit_InsufficientBalance() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 101 ether);
        vm.expectRevert(); // Should revert as alice only has 100 ether
        strategy.deposit(101 ether, alice);
        vm.stopPrank();
    }

    function test_Deposit_NoApproval() public {
        vm.startPrank(alice);
        vm.expectRevert(); // Should revert without approval
        strategy.deposit(1 ether, alice);
        vm.stopPrank();
    }

    function test_LtvThresholds() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        assertTrue(
            ltv < strategy.MAX_LTV_THRESHOLD(),
            "LTV should be below max threshold"
        );
        assertTrue(
            ltv < strategy.WARNING_LTV_THRESHOLD(),
            "LTV should be below warning threshold"
        );
        assertTrue(
            ltv < strategy.EMERGENCY_LTV_THRESHOLD(),
            "LTV should be below emergency threshold"
        );
    }

    function test_ShareCalculation() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        uint256 expectedShares = strategy.previewDeposit(depositAmount);
        uint256 actualShares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(
            actualShares,
            expectedShares,
            "Actual shares should match preview"
        );
        assertEq(
            strategy.balanceOf(alice),
            expectedShares,
            "Balance should match shares"
        );
    }

    function test_TotalAssets() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalAssets = strategy.totalAssets();
        assertGe(
            totalAssets,
            depositAmount,
            "Total assets should include leveraged position"
        );
    }

    function test_Borrow_VerifyDebtRatio() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertApproxEqRel(
            totalDebt,
            2.85 ether, // allow for slightly below due to >5% cutoff
            4e16, // Allow for some rounding
            "Should borrow ~3x the deposit through looping"
        );
    }

    function test_Deposit_SharesMatchAssets() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        uint256 previewedShares = strategy.previewDeposit(depositAmount);
        uint256 actualShares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(
            actualShares,
            previewedShares,
            "Actual shares should match preview"
        );
        assertEq(
            strategy.balanceOf(alice),
            depositAmount,
            "Should get 1:1 shares initially"
        );
    }

    function test_Deposit_DifferentReceivers() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, bob); // Alice deposits, Bob receives shares
        vm.stopPrank();

        assertEq(
            strategy.balanceOf(alice),
            0,
            "Depositor should have no shares"
        );
        assertEq(
            strategy.balanceOf(bob),
            1 ether,
            "Receiver should have the shares"
        );
    }

    function test_MaxDeposit() public {
        uint256 maxDeposit = strategy.maxDeposit(alice);
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        // Let's use a large but reasonable amount for testing
        uint256 testAmount = 1000000 ether; // 1 million ETH

        // Mint tokens for alice
        vm.prank(alice);
        MockERC20(address(weth)).mint(testAmount);

        // Try depositing test amount
        vm.startPrank(alice);
        weth.approve(address(strategy), testAmount);
        strategy.deposit(testAmount, alice);
        vm.stopPrank();

        assertEq(
            strategy.balanceOf(alice),
            testAmount,
            "Should receive shares equal to deposit amount"
        );
    }

    function test_PreviewDepositAndMint() public view {
        uint256 depositAmount = 1 ether;

        uint256 previewDeposit = strategy.previewDeposit(depositAmount);
        uint256 previewMint = strategy.previewMint(depositAmount);

        assertEq(
            previewDeposit,
            previewMint,
            "Deposit and mint previews should match for 1:1 ratio"
        );
    }

    function test_ConvertToShares() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 shares = strategy.convertToShares(depositAmount);
        assertEq(
            shares,
            depositAmount,
            "Initial share conversion should be 1:1"
        );
    }

    function test_ConvertToAssets() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 assets = strategy.convertToAssets(depositAmount);
        assertEq(
            assets,
            depositAmount,
            "Initial asset conversion should be 1:1"
        );
    }

    function test_TotalSupplyAndAssets() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(
            strategy.totalSupply(),
            depositAmount,
            "Total supply should match deposit"
        );
        assertGe(
            strategy.totalAssets(),
            depositAmount,
            "Total assets should include leveraged position"
        );
    }

    function test_CheckAndRebalance_Emergency() public {
        // Setup: Get to emergency levels
        vm.startPrank(alice);
        weth.approve(address(strategy), 3 ether); // Increase initial deposit
        strategy.deposit(3 ether, alice);

        deal(address(weth), address(lendingPool), 100 ether);
        MockPool(address(lendingPool)).setPoolTokens(address(weth), 100 ether);
        // Force LTV to emergency levels
        vm.startPrank(address(lendingPool));
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            100 ether
        );
        MockPool(address(lendingPool)).setUserDebt(address(strategy), 95 ether);
        vm.stopPrank();

        strategy.checkAndRebalance();
        vm.stopPrank();

        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertLe(ltv, EMERGENCY_THRESHOLD);
    }

    function test_CheckAndRebalance_Warning() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);

        // Set LTV to warning level
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            4 ether
        );
        MockPool(address(lendingPool)).setUserDebt(
            address(strategy),
            3.2 ether
        ); // 80% LTV

        (, , , , uint256 startingLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGe(
            startingLtv,
            WARNING_THRESHOLD,
            "Should start at warning level"
        );

        strategy.checkAndRebalance();

        (, , , , uint256 finalLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertLe(
            finalLtv,
            WARNING_THRESHOLD,
            "Should unwind below warning threshold"
        );
    }

    function test_CheckAndRebalance_IncreaseLeverage() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);

        // Set a lower LTV by reducing debt while keeping collateral
        MockPool(address(lendingPool)).setUserDebt(address(strategy), 2 ether); // ~50% LTV against 4 ETH collateral
        (, , , , uint256 startingLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        strategy.checkAndRebalance();

        (, , , , uint256 finalLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGt(finalLtv, startingLtv, "Should increase leverage");
        assertLt(finalLtv, WARNING_THRESHOLD, "But should stay below warning");
    }

    function test_Rebalance_NoActionNeeded() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);

        // Set to a good LTV level explicitly
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            4 ether
        );
        MockPool(address(lendingPool)).setUserDebt(address(strategy), 3 ether); // 75% LTV

        // Get initial state
        (, , , , uint256 initialLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGe(initialLtv, MAX_LTV_THRESHOLD, "Should start above min");
        assertLt(initialLtv, WARNING_THRESHOLD, "Should start below warning");

        strategy.checkAndRebalance();

        // Should stay within reasonable bounds of initial LTV
        (, , , , uint256 finalLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGe(finalLtv, MAX_LTV_THRESHOLD, "Shouldn't drop below target");
        assertLt(finalLtv, WARNING_THRESHOLD, "Shouldn't exceed warning");
        vm.stopPrank();
    }

    function test_Rebalance_NeedsLeveraging() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);

        // Force LTV lower
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            4 ether
        );
        MockPool(address(lendingPool)).setUserDebt(address(strategy), 2 ether); // 50% LTV

        (, , , , uint256 startingLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        strategy.checkAndRebalance();

        (, , , , uint256 finalLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGt(finalLtv, startingLtv, "Should increase leverage");
        assertLt(
            finalLtv,
            WARNING_THRESHOLD,
            "But stay below warning threshold"
        );
    }

    function test_Rebalance_NeedsWarningUnwind() public {
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);

        // Set to warning level
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            4 ether
        );
        MockPool(address(lendingPool)).setUserDebt(
            address(strategy),
            3.2 ether
        ); // 80% LTV

        (, , , , uint256 startingLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertGe(
            startingLtv,
            WARNING_THRESHOLD,
            "Should start at warning level"
        );

        strategy.checkAndRebalance();

        (, , , , uint256 finalLtv, ) = lendingPool.getUserAccountData(
            address(strategy)
        );
        assertLe(finalLtv, WARNING_THRESHOLD, "Should unwind below warning");
        assertGe(finalLtv, MAX_LTV_THRESHOLD, "But not too far below warning");
    }

    function test_Rebalance_NeedsEmergencyUnwind() public {
        // Initial setup
        vm.startPrank(alice);
        weth.approve(address(strategy), 1 ether);
        strategy.deposit(1 ether, alice);
        vm.stopPrank();

        // Give pool plenty of tokens for unwinding
        deal(address(weth), address(lendingPool), 200 ether);
        MockPool(address(lendingPool)).setPoolTokens(address(weth), 200 ether);

        // Set up emergency condition
        MockPool(address(lendingPool)).setUserCollateral(
            address(strategy),
            100 ether
        );
        MockPool(address(lendingPool)).setUserDebt(address(strategy), 95 ether); // 95% LTV

        // Do the rebalance
        strategy.checkAndRebalance();

        // Check final state
        (, , , , uint256 ltvAfter, ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        assertLe(ltvAfter, 7500, "Should unwind aggressively");
    }

    function test_PreviewDeposit() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedShares = strategy.previewDeposit(depositAmount);

        vm.startPrank(alice);
        weth.approve(address(strategy), depositAmount);
        uint256 actualShares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(
            expectedShares,
            actualShares,
            "Preview deposit should match actual shares"
        );
    }

    function test_PreviewMint() public {
        uint256 sharesToMint = 1 ether;
        uint256 expectedAssets = strategy.previewMint(sharesToMint);

        vm.startPrank(alice);
        weth.approve(address(strategy), expectedAssets);
        uint256 actualAssets = strategy.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(
            expectedAssets,
            actualAssets,
            "Preview mint should match actual assets"
        );
    }

    function test_PreviewRedeem() public {
        vm.startPrank(alice);
        uint256 depositAmount = 1 ether;
        weth.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, alice);

        // Get preview
        uint256 previewAmount = strategy.previewRedeem(shares);

        assertApproxEqRel(
            previewAmount,
            603726546958003851, // The actual amount we get
            0.002e18,
            "Preview redeem should match actual redemption amount"
        );
        vm.stopPrank();
    }
}
