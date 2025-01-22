// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct PermitSignature {
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IParaSwapAdapter {
    function swapAndSupply(
        IERC20 assetToSwapFrom,
        IERC20 assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountToReceive,
        uint256 swapAllBalance,
        bytes calldata swapCalldata,
        address augustus,
        PermitSignature calldata permitParams
    ) external;
}
