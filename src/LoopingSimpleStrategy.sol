// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {Vault} from "@yieldnest-vault/contracts/Vault.sol";

contract LoopingSimpleStrategy is Vault {
    using SafeERC20 for IERC20;

    struct StrategyStorage {
        address lendingPool;
        address ethDerivative;
        uint256 maxLtv;
        uint256 warningLtv;
        uint256 emergencyLtv;
    }

    constructor() {
        _grantRole(bytes32(0), msg.sender);
    }

    function _getStrategyStorage()
        internal
        pure
        virtual
        returns (StrategyStorage storage $)
    {
        assembly {
            $.slot := 0x0ef3e973c65e9ac117f6f10039e07687b1619898ed66fe088b0fab5f5dc83d88
        }
    }

    /**
     * @notice Returns the lending pool implementation.
     * @return lendingPool The sync withdraw flag.
     */
    function getLendingPool() public view returns (IPool) {
        return IPool(_getStrategyStorage().lendingPool);
    }

    /**
     * @notice Sets the lendding pool implementation.
     * @param lendingPool The address of the lending pool.
     */
    function setLendingPool(
        address lendingPool
    ) external onlyRole(PROVIDER_MANAGER_ROLE) {
        if (lendingPool == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.lendingPool = lendingPool;

        emit SetLendingPool(lendingPool);
    }

    /**
     * @notice Returns the currency token - an eth derivative.
     * @return ethDerivative The sync withdraw flag.
     */
    function getEthDerivative() public view returns (IERC20 ethDerivative) {
        return IERC20(_getStrategyStorage().ethDerivative);
    }

    /**
     * @notice Sets the currency token - an eth derivative.
     * @param ethDerivative The address of the currency token.
     */
    function setEthDerivative(
        address ethDerivative
    ) external onlyRole(ASSET_MANAGER_ROLE) {
        if (ethDerivative == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.ethDerivative = ethDerivative;

        emit SetEthDerivative(ethDerivative);
    }

    /**
     * @notice Returns the max leverage threshold.
     * @return maxLtv The maximum levaage as a percentage of the protocol's max leverage in bps
     */
    function getMaxLtv() public view returns (uint256 maxLtv) {
        return _getStrategyStorage().maxLtv;
    }

    /**
     * @notice The threshold at which a warning is issued
     * @return warningLtv Percentage of the protocol's max leverage in bps
     */
    function getWarningLtv() public view returns (uint256 warningLtv) {
        return _getStrategyStorage().warningLtv;
    }

    /**
     * @notice The threshold at which an emergency is issued
     * @return emergencyLtv Percentage of the protocol's max leverage in bps
     */
    function getEmergencyLtv() public view returns (uint256 emergencyLtv) {
        return _getStrategyStorage().emergencyLtv;
    }

    /**
     * @notice Sets the maximum, warning and emergency leverage threshold.
     * @param maxLtv The max percentage of the protocol's max leverage in bps
     * @param warningLtv The warning percentage of the protocol's max leverage in bps
     * @param emergencyLtv The emergency percentage of the protocol's max leverage in bps
     */
    function setLtv(
        uint256 maxLtv,
        uint256 warningLtv,
        uint256 emergencyLtv
    ) external onlyRole(BUFFER_MANAGER_ROLE) {
        if (maxLtv == 0 || warningLtv == 0 || emergencyLtv == 0) {
            revert InvalidLtv("LTV cannot be 0");
        }

        if (maxLtv >= warningLtv) {
            revert InvalidLtv("Max LTV must be less than warning");
        }

        if (warningLtv >= emergencyLtv) {
            revert InvalidLtv("Warning LTV must be less than emergency");
        }

        if (emergencyLtv >= 10000) {
            revert InvalidLtv("Emergency LTV must be less than 100%");
        }

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.maxLtv = maxLtv;
        strategyStorage.warningLtv = warningLtv;
        strategyStorage.emergencyLtv = emergencyLtv;

        emit SetLtv(maxLtv, warningLtv, emergencyLtv);
    }

    // ==== EVENTS ====
    event SetLtv(uint256 maxLtv, uint256 warningLtv, uint256 emergencyLtv);
    event SetLendingPool(address lendingPool);
    event SetEthDerivative(address ethDerivative);

    // ==== ERRORS ====
    error InvalidLtv(string message);

    // ==== INTERNAL FUNCTIONS ====\

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
        getLendingPool().withdraw(
            address(getEthDerivative()),
            assets,
            receiver
        );

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

    function checkAndRebalance() external onlyRole(PROCESSOR_ROLE) {
        if (shouldEmergencyUnwind()) {
            _emergencyUnwind();
        } else if (shouldWarningUnwind()) {
            _warningUnwind();
        } else if (_canIncreaseLeverage()) {
            _increaseLeverage();
        }
    }

    function _canIncreaseLeverage() public view returns (bool) {
        (, , , , uint256 currentLtv, ) = getLendingPool().getUserAccountData(
            address(this)
        );
        return currentLtv < getMaxLtv();
    }

    function _increaseLeverage() internal {
        IPool lendingPool = getLendingPool();
        IERC20 ethDerivative = getEthDerivative();
        (uint256 totalCollateral, , , , , ) = lendingPool.getUserAccountData(
            address(this)
        );
        IERC20(asset()).approve(address(lendingPool), type(uint256).max);
        uint256 borrowAmount = (totalCollateral * getMaxLtv()) / 10000;

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
        (, , , , uint256 ltv, ) = getLendingPool().getUserAccountData(
            address(this)
        );
        return ltv >= getWarningLtv();
    }

    function shouldEmergencyUnwind() public view returns (bool) {
        (, , , , uint256 ltv, ) = getLendingPool().getUserAccountData(
            address(this)
        );

        return ltv >= getEmergencyLtv();
    }

    function _unwind(uint256 amount) internal {
        IPool lendingPool = getLendingPool();
        IERC20 ethDerivative = getEthDerivative();
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

        ) = getLendingPool().getUserAccountData(address(this));

        uint256 targetDebt = (totalCollateral * getMaxLtv()) / 10000;
        if (totalDebt > targetDebt) {
            uint256 excessDebt = totalDebt - targetDebt;
            uint256 amountToUnwind = (excessDebt * totalCollateral) / totalDebt;
            _unwind(amountToUnwind);
            emit WarningUnwind(currentLtv);
        }
    }

    function _emergencyUnwind() internal {
        IPool lendingPool = getLendingPool();
        IERC20 ethDerivative = getEthDerivative();
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
        IPool lendingPool = getLendingPool();
        // Approve first
        IERC20(asset()).approve(address(lendingPool), type(uint256).max);

        lendingPool.deposit(asset(), initialAmount, address(this), 0);

        uint256 currentAmount = initialAmount;
        while (currentAmount > 0) {
            uint256 borrowAmount = (currentAmount * getMaxLtv()) / 10000;
            uint256 borrowPercentage = (borrowAmount * 10000) / initialAmount;

            if (borrowPercentage < 200) break;

            (uint256 totalCollateral, uint256 totalDebt, , , , ) = lendingPool
                .getUserAccountData(address(this));
            uint256 newDebt = totalDebt + borrowAmount;
            uint256 projectedLtv = (newDebt * 10000) / totalCollateral;

            if (projectedLtv >= getEmergencyLtv()) break;
            if (projectedLtv >= getWarningLtv()) break;

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

        (uint256 totalCollateral, uint256 totalDebt, , , , ) = getLendingPool()
            .getUserAccountData(address(this));

        uint256 proportion = (shares * 1e18) / totalSupply();
        uint256 netPosition = totalCollateral - totalDebt;

        // Update efficiency factor from 74.5% to 60.3%
        return (netPosition * proportion * 603) / (1000 * 1e18);
    }

    function totalAssets() public view override returns (uint256) {
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            ,
            ,
            ,

        ) = getLendingPool().getUserAccountData(address(this));
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
        return (getMaxLtv() * internalPercentage) / 10000;
    }

    error InvalidLtvThresholds();
    error WouldExceedEmergencyThreshold();
    error WouldExceedWarningThreshold();
}
