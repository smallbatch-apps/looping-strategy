// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LoopingSimpleStrategy} from "../src/LoopingSimpleStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

contract LoopSimpleStrategyTest is Test {
    LoopingSimpleStrategy public strategy;
    IPool public lendingPool;
    IERC20 public weth;

    // Create users to assign roles to
    address deployer = makeAddr("deployer");
    address riskManager = makeAddr("riskManager");
    address operator = makeAddr("operator");
    address user = makeAddr("user");
    address keeper = makeAddr("keeper");

    function setUp() public {
        // create mocks for pool and rate provider
        MockPool mockPool = new MockPool(IPoolAddressesProvider(address(0)));

        weth = IERC20(address(new MockERC20("Wrapped Ether", "WETH")));
        lendingPool = IPool(address(mockPool));

        vm.startPrank(deployer);
        strategy = new LoopingSimpleStrategy();

        // Grant roles
        // Oerator roles
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), operator);
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), operator);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), operator);

        // Risk manager roles
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), riskManager);
        strategy.grantRole(strategy.PAUSER_ROLE(), riskManager);
        strategy.grantRole(strategy.UNPAUSER_ROLE(), riskManager);

        // Keeper roles
        strategy.grantRole(strategy.PROCESSOR_ROLE(), keeper);
        vm.stopPrank();

        // operator does most of the setup
        vm.startPrank(operator);
        MockProvider mockProvider = new MockProvider();
        mockProvider.setRate(address(weth), 1e18);

        strategy.setProvider(address(mockProvider));
        strategy.setLendingPool(address(lendingPool));
        strategy.setEthDerivative(address(weth));
        strategy.addAsset(address(weth), true);
        vm.stopPrank();

        vm.prank(riskManager);
        strategy.setLtv(7500, 8000, 9500);

        // finally, assign some currency to the pool and user
        deal(address(weth), user, 100 ether);
        deal(address(weth), address(lendingPool), 100 ether);
    }

    function test_Deposit_BasicFlow() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(user);
        weth.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, user);
        vm.stopPrank();

        (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(
            address(strategy)
        );

        assertApproxEqRel(
            totalDebt,
            3 ether,
            4e16,
            "Should achieve ~3x leverage through looping"
        );
    }

    // There is no intention of testing much of the functionality, as this is covered in the LoopStrategyTest.
    // This is intended to just be a simpler version of the setup, lacking the initializer and using the StrategyStorage pattern.
    // The purpose of this version is to improve on usage of the underlying Vault patterns, and it is probably closer overall to production-ready
}
