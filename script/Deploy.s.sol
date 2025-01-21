// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {LoopingStrategy} from "../src/LoopingStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IPriceOracleGetter} from "@aave/contracts/interfaces/IPriceOracleGetter.sol";
import {console2} from "forge-std/console2.sol";

contract DeployLoopingStrategy is Script {
    // Constants from test
    uint256 constant MAX_LTV_THRESHOLD = 8000; // 80%
    uint256 constant WARNING_THRESHOLD = 8500; // 85%
    uint256 constant EMERGENCY_THRESHOLD = 9000; // 90%

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address lendingPool = vm.envAddress("LENDING_POOL"); // Aave V3 pool
        address weth = vm.envAddress("WETH");
        address admin = vm.envAddress("ADMIN");
        address priceOracle = vm.envAddress("PRICE_ORACLE"); // Aave price oracle

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        LoopingStrategy implementation = new LoopingStrategy(
            lendingPool,
            weth,
            MAX_LTV_THRESHOLD,
            WARNING_THRESHOLD,
            EMERGENCY_THRESHOLD
        );

        // Initialize data
        bytes memory initData = abi.encodeWithSelector(
            LoopingStrategy.initialize.selector
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            initData
        );

        // Get strategy instance
        LoopingStrategy strategy = LoopingStrategy(payable(address(proxy)));

        // Configure strategy
        strategy.setProvider(priceOracle);
        strategy.addAsset(weth, true);
        strategy.unpause();

        vm.stopBroadcast();

        console2.log("Deployment Summary:");
        console2.log("Implementation:", address(implementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Using Aave Pool:", lendingPool);
        console2.log("Using Price Oracle:", priceOracle);
    }
}
