// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LoopToken is ERC20 {
    address public strategy;

    modifier onlyStrategy() {
        if (msg.sender != strategy) revert NotAuthorized();
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address _strategy
    ) ERC20(name, symbol) {
        strategy = _strategy;
    }

    function burn(address from, uint256 amount) external onlyStrategy {
        _burn(from, amount);
    }

    error NotAuthorized();
}
