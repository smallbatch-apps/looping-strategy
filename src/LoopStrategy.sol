// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {Vault} from "@yieldnest-vault/contracts/Vault.sol";

contract LoopingStrategy is Vault {
    IPool public immutable lendingPool;
    IERC20 public immutable ethDerivative;
    uint256 public totalBorrowed;

    // safety margins are configured in the constructor based on risk profile for asset
    // note that these are a percentage of the protocol's max LTV - they are a safety margin
    uint256 public immutable MAX_LTV_THRESHOLD; // allow up to 80% of the protocol's max leverage
    uint256 public immutable WARNING_LTV_THRESHOLD; // warn at 85% of the protocol's max leverage
    uint256 public immutable EMERGENCY_LTV_THRESHOLD; // emergency at 95% of the protocol's max leverage

    constructor(
        address _lendingPool,
        address _ethDerivative,
        uint256 _maxLtv,
        uint256 _warningLtv,
        uint256 _emergencyLtv
    ) {
        if (_maxLtvBps < _warningLtvBps) revert InvalidLtvThresholds();
        if (_warningLtvBps < _emergencyLtvBps) revert InvalidLtvThresholds();

        lendingPool = IPool(_lendingPool);
        ethDerivative = IERC20(_ethDerivative);

        MAX_LTV_THRESHOLD = _maxLtv;
        WARNING_LTV_THRESHOLD = _warningLtv;
        EMERGENCY_LTV_THRESHOLD = _emergencyLtv;

        IERC20(_ethDerivative).approve(_lendingPool, type(uint256).max);
    }

    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal override {
        if (asset_ != address(ethDerivative)) revert InvalidAsset();
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        // Looping-specific logic
        _loopDeposit(asset_, assets);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (asset_ != address(ethDerivative)) revert InvalidAsset();

        lendingPool.withdraw(address(ethDerivative), assets, receiver);

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _loopDeposit(address asset_, uint256 amount) internal {
        ethDerivative.approve(address(lendingPool), amount);
        lendingPool.deposit(address(ethDerivative), amount, address(this), 0);

        uint256 borrowAmount = amount / 2;

        lendingPool.borrow(
            address(ethDerivative),
            borrowAmount,
            2,
            0,
            address(this)
        );
        lendingPool.deposit(
            address(ethDerivative),
            borrowAmount,
            address(this),
            0
        );
    }

    function totalAssets() public view override returns (uint256) {
        // Example: Calculate total assets (collateral - debt)
        (uint256 totalCollateralETH, uint256 totalDebtETH, , , , ) = lendingPool
            .getUserAccountData(address(this));
        return totalCollateralETH - totalDebtETH;
    }

    function _effectiveLTV(
        uint256 internalPercentage
    ) internal view returns (uint256) {
        return (MAX_LTV_THRESHOLD * internalPercentage) / 10000;
    }

    error InvalidAsset();
    error InvalidLtvThresholds();
}
