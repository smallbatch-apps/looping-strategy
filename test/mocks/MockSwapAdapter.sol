// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IParaSwapAdapter, PermitSignature} from "src/interfaces/IParaSwapAdapter.sol";

contract MockSwapAdapter is IParaSwapAdapter {
    IPool public immutable pool;

    constructor(address _pool) {
        pool = IPool(_pool);
    }

    function swapAndSupply(
        IERC20 assetToSwapFrom,
        IERC20 assetToSwapTo,
        uint256 amountToSwap,
        uint256 /* minAmountToReceive */,
        uint256 /* swapAllBalance */,
        bytes calldata /* swapCalldata */,
        address /* augustus */,
        PermitSignature calldata /* permitParams */
    ) external {
        assetToSwapFrom.transferFrom(msg.sender, address(this), amountToSwap);
        pool.supply(address(assetToSwapTo), amountToSwap, msg.sender, 0);
    }
}
