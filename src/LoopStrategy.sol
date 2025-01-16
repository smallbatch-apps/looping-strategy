// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {console2} from "forge-std/console2.sol";
import {Vault} from "@yieldnest-vault/contracts/Vault.sol";

contract LoopingStrategy is Vault {
    using SafeERC20 for IERC20;
    IPool public immutable lendingPool;
    IERC20 public immutable ethDerivative;

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
        if (_maxLtv > _warningLtv) revert InvalidLtvThresholds();
        if (_warningLtv > _emergencyLtv) revert InvalidLtvThresholds();

        lendingPool = IPool(_lendingPool);
        ethDerivative = IERC20(_ethDerivative);
        MAX_LTV_THRESHOLD = _maxLtv;
        WARNING_LTV_THRESHOLD = _warningLtv;
        EMERGENCY_LTV_THRESHOLD = _emergencyLtv;
        _getVaultStorage().buffer = address(this);
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC20_init("Looping WETH Vault", "loopWETH");
        __ERC20Permit_init("Looping WETH Vault");
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(BUFFER_MANAGER_ROLE, address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROVIDER_MANAGER_ROLE, msg.sender);
        _grantRole(UNPAUSER_ROLE, msg.sender);
        _grantRole(ASSET_MANAGER_ROLE, msg.sender);

        _getVaultStorage().buffer = address(this);

        _initialize(
            msg.sender,
            "Looping WETH Vault",
            "loopWETH",
            18,
            0,
            false,
            true
        );

        ethDerivative.approve(address(lendingPool), type(uint256).max);
    }

    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal override {
        if (asset_ != asset()) {
            revert InvalidAsset(asset_);
        }
        if (assets == 0) {
            revert ZeroAmount();
        }

        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);
        _loopDeposit(assets);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        lendingPool.withdraw(address(ethDerivative), assets, receiver);

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        return _withdrawAsset(asset(), assets, receiver, owner);
    }

    function _withdrawAsset(
        address asset_,
        uint256 assets,
        address receiver,
        address owner
    ) internal returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _withdrawAsset(asset_, msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function _withdrawAsset(
        address asset_,
        address /* caller */,
        address receiver,
        address /* owner */,
        uint256 assets,
        uint256 /* shares */
    ) internal virtual {
        _unwind(assets);

        // NOTE: burn already happened in base vault
        IERC20(asset_).safeTransfer(receiver, assets);
    }

    function checkAndRebalance() public {
        if (shouldEmergencyUnwind()) {
            _emergencyUnwind();
        } else if (shouldWarningUnwind()) {
            _warningUnwind();
        } else if (_canIncreaseLeverage()) {
            _increaseLeverage();
        }
    }

    function _canIncreaseLeverage() public view returns (bool) {
        (, , , , uint256 currentLtv, ) = lendingPool.getUserAccountData(
            address(this)
        );
        return currentLtv < MAX_LTV_THRESHOLD;
    }

    function _increaseLeverage() internal {
        (uint256 totalCollateral, , , , , ) = lendingPool.getUserAccountData(
            address(this)
        );
        IERC20(asset()).approve(address(lendingPool), type(uint256).max);
        uint256 borrowAmount = (totalCollateral * MAX_LTV_THRESHOLD) / 10000;

        // essentially the deposit function but once-off
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

    // ==== UNWINDING ====

    function shouldWarningUnwind() public view returns (bool) {
        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(address(this));
        return ltv >= WARNING_LTV_THRESHOLD;
    }

    function shouldEmergencyUnwind() public view returns (bool) {
        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(address(this));

        return ltv >= EMERGENCY_LTV_THRESHOLD;
    }

    function _unwind(uint256 amount) internal {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
            .getUserAccountData(address(this));
        uint256 debtToRepay = (amount * totalDebt) / totalCollateral;

        lendingPool.withdraw(address(ethDerivative), amount, address(this));

        ethDerivative.approve(address(lendingPool), debtToRepay);
        lendingPool.repay(
            address(ethDerivative),
            debtToRepay,
            2,
            address(this)
        );
    }

    function _warningUnwind() internal {
        (
            uint256 totalCollateral,
            uint256 totalDebt,
            ,
            ,
            uint256 currentLtv,

        ) = lendingPool.getUserAccountData(address(this));

        uint256 targetDebt = (totalCollateral * MAX_LTV_THRESHOLD) / 10000;
        if (totalDebt > targetDebt) {
            uint256 excessDebt = totalDebt - targetDebt;
            uint256 amountToUnwind = (excessDebt * totalCollateral) / totalDebt;
            _unwind(amountToUnwind);
            emit WarningUnwind(currentLtv);
        }
    }

    function _emergencyUnwind() internal {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
            .getUserAccountData(address(this));

        // Target 70% LTV
        uint256 targetLTV = 7000;

        // Keep 20% of collateral
        uint256 remainingCollateral = (totalCollateral * 20) / 100;
        // Target debt should be 70% of remaining collateral
        uint256 targetDebt = (remainingCollateral * targetLTV) / 10000;

        uint256 amountToUnwind = totalCollateral - remainingCollateral;
        uint256 debtToRepay = totalDebt - targetDebt;

        // Custom unwind with specific debt repayment
        lendingPool.withdraw(
            address(ethDerivative),
            amountToUnwind,
            address(this)
        );
        ethDerivative.approve(address(lendingPool), debtToRepay);
        lendingPool.repay(
            address(ethDerivative),
            debtToRepay,
            2,
            address(this)
        );
    }

    event EmergencyUnwind(
        uint256 ltv,
        uint256 totalCollateral,
        uint256 totalDebt
    );
    event WarningUnwind(uint256 ltv);

    // ==== LOOPING ====

    function _loopDeposit(uint256 initialAmount) internal {
        // Approve first
        IERC20(asset()).approve(address(lendingPool), type(uint256).max);

        lendingPool.deposit(asset(), initialAmount, address(this), 0);

        uint256 currentAmount = initialAmount;
        while (currentAmount > 0) {
            uint256 borrowAmount = (currentAmount * MAX_LTV_THRESHOLD) / 10000;
            uint256 borrowPercentage = (borrowAmount * 10000) / initialAmount;

            if (borrowPercentage < 200) break;

            (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
                .getUserAccountData(address(this));
            uint256 newDebt = totalDebt + borrowAmount;
            uint256 projectedLtv = (newDebt * 10000) / totalCollateral;

            if (projectedLtv >= EMERGENCY_LTV_THRESHOLD) break;
            if (projectedLtv >= WARNING_LTV_THRESHOLD) break;

            // Borrow
            lendingPool.borrow(asset(), borrowAmount, 2, 0, address(this));

            // Approve and deposit
            IERC20(asset()).approve(address(lendingPool), borrowAmount);
            lendingPool.deposit(asset(), borrowAmount, address(this), 0);

            currentAmount = borrowAmount;
        }
    }

    function previewDeposit(
        uint256 assets
    ) public view virtual override returns (uint256) {
        if (totalSupply() == 0) return assets;
        return (assets * totalSupply()) / totalAssets();
    }

    function previewMint(
        uint256 shares
    ) public view virtual override returns (uint256) {
        if (totalSupply() == 0) return shares;
        return (shares * totalAssets() + totalSupply() - 1) / totalSupply();
    }

    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (assets * totalSupply() + totalAssets() - 1) / totalAssets();
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        if (totalSupply() == 0) return 0;

        (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
            .getUserAccountData(address(this));

        uint256 proportion = (shares * 1e18) / totalSupply();
        uint256 netPosition = totalCollateral - totalDebt;

        // Update efficiency factor from 74.5% to 60.3%
        return (netPosition * proportion * 603) / (1000 * 1e18);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 totalCollateralETH, uint256 totalDebtETH, , , , ) = lendingPool
            .getUserAccountData(address(this));
        return totalCollateralETH - totalDebtETH;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 shares = balanceOf(owner);
        return convertToAssets(shares);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = previewRedeem(shares);

        // Unwind position - this already includes the withdraw
        _unwind(assets);

        return super.redeem(shares, receiver, owner);
    }

    function _effectiveLTV(
        uint256 internalPercentage
    ) internal view returns (uint256) {
        return (MAX_LTV_THRESHOLD * internalPercentage) / 10000;
    }

    error InvalidLtvThresholds();
    error WouldExceedEmergencyThreshold();
    error WouldExceedWarningThreshold();
}
