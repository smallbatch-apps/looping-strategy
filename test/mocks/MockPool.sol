// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {Pool} from "@aave/contracts/protocol/pool/Pool.sol";
import {Pool} from "@aave/contracts/protocol/pool/Pool.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console2} from "forge-std/console2.sol";

contract MockPool is Pool {
    using SafeERC20 for IERC20;

    constructor(IPoolAddressesProvider provider) Pool(provider) {}

    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDebt;
    mapping(address => mapping(address => bool)) public userAssetCollateral;

    uint256 private mockLtv;
    mapping(address => uint256) public poolTokens;

    function setLTV(uint256 _ltv) external {
        mockLtv = _ltv;
    }

    function setUserDebt(address user, uint256 amount) external {
        userDebt[user] = amount;
    }

    function setUserCollateral(address user, uint256 amount) external {
        userCollateral[user] = amount;
    }

    function setPoolTokens(address asset, uint256 amount) external {
        poolTokens[asset] = amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256,
        uint16,
        address onBehalfOf
    ) public virtual override {
        // First update the pool's token balance
        poolTokens[asset] += amount;
        userDebt[onBehalfOf] += amount;

        // Then transfer the tokens
        IERC20(asset).transfer(msg.sender, amount);
    }

    function getUserAccountData(
        address user
    )
        external
        view
        virtual
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        uint256 collateral = userCollateral[user];
        uint256 debt = userDebt[user];

        uint256 currentLtv = userCollateral[user] == 0
            ? 0
            : (userDebt[user] * 10000) / userCollateral[user];

        uint256 health = debt == 0
            ? 10 ether
            : (collateral * 8000) / (debt * 100);

        return (collateral, debt, 0, 8000, currentLtv, health);
    }

    // Required override from abstract
    function getRevision() internal pure override returns (uint256) {
        return 1;
    }

    function initialize(
        IPoolAddressesProvider /* provider */
    ) external virtual override {
        revert NotImplemented();
    }

    function mintUnbacked(
        address /* asset */,
        uint256 /* amount */,
        address /* onBehalfOf */,
        uint16 /* referralCode */
    ) external virtual override {
        revert NotImplemented();
    }

    function backUnbacked(
        address /* asset */,
        uint256 /* amount */,
        uint256 /* fee */
    ) external virtual override returns (uint256) {
        revert NotImplemented();
    }

    function supplyWithPermit(
        address /* asset */,
        uint256 /* amount */,
        address /* onBehalfOf */,
        uint16 /* referralCode */,
        uint256 /* deadline */,
        uint8 /* permitV */,
        bytes32 /* permitR */,
        bytes32 /* permitS */
    ) public virtual override {
        revert NotImplemented();
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) public override returns (uint256) {
        require(
            userCollateral[msg.sender] >= amount,
            "Insufficient collateral"
        );
        require(poolTokens[asset] >= amount, "Insufficient pool tokens");

        userCollateral[msg.sender] -= amount;
        poolTokens[asset] -= amount;

        // Transfer tokens from pool
        IERC20(asset).transfer(to, amount);

        if (userDebt[msg.sender] > 0) {
            mockLtv =
                (userDebt[msg.sender] * 10000) /
                userCollateral[msg.sender];
        }
        return amount;
    }

    function repay(
        address /*asset*/,
        uint256 amount,
        uint256 /*rateMode*/,
        address onBehalfOf
    ) public override returns (uint256) {
        userDebt[onBehalfOf] -= amount;
        return amount;
    }

    function repayWithPermit(
        address /* asset */,
        uint256 /* amount */,
        uint256 /* interestRateMode */,
        address /* onBehalfOf */,
        uint256 /* deadline */,
        uint8 /* permitV */,
        bytes32 /* permitR */,
        bytes32 /* permitS */
    ) public virtual override returns (uint256) {
        revert NotImplemented();
    }

    function repayWithATokens(
        address /* asset */,
        uint256 /* amount */,
        uint256 /* interestRateMode */
    ) public virtual override returns (uint256) {
        revert NotImplemented();
    }

    function swapBorrowRateMode(
        address /* asset */,
        uint256 /* interestRateMode */
    ) public virtual override {
        revert NotImplemented();
    }

    function setUserUseReserveAsCollateral(
        address /* asset */,
        bool /* useAsCollateral */
    ) public virtual override {
        revert NotImplemented();
    }

    function liquidationCall(
        address /* collateralAsset */,
        address /* debtAsset */,
        address /* user */,
        uint256 /* debtToCover */,
        bool /* receiveAToken */
    ) public virtual override {
        revert NotImplemented();
    }

    function flashLoan(
        address /* receiverAddress */,
        address[] calldata /* assets */,
        uint256[] calldata /* amounts */,
        uint256[] calldata /* interestRateModes */,
        address /* onBehalfOf */,
        bytes calldata /* params */,
        uint16 /* referralCode */
    ) public virtual override {
        revert NotImplemented();
    }

    function flashLoanSimple(
        address /* receiverAddress */,
        address /* asset */,
        uint256 /* amount */,
        bytes calldata /* params */,
        uint16 /* referralCode */
    ) public virtual override {
        revert NotImplemented();
    }

    function mintToTreasury(
        address[] calldata /* assets */
    ) external virtual override {
        revert NotImplemented();
    }

    function getReserveData(
        address /* asset */
    )
        external
        view
        virtual
        override
        returns (DataTypes.ReserveDataLegacy memory)
    {
        revert NotImplemented();
    }

    function getUserConfiguration(
        address /* user */
    )
        external
        view
        virtual
        override
        returns (DataTypes.UserConfigurationMap memory)
    {
        revert NotImplemented();
    }

    function getConfiguration(
        address /* asset */
    )
        external
        view
        virtual
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        revert NotImplemented();
    }

    function getReserveNormalizedIncome(
        address /* asset */
    ) external view virtual override returns (uint256) {
        revert NotImplemented();
    }

    function getReserveNormalizedVariableDebt(
        address /* asset */
    ) external view virtual override returns (uint256) {
        revert NotImplemented();
    }

    function getReservesList()
        external
        view
        virtual
        override
        returns (address[] memory)
    {
        revert NotImplemented();
    }

    function getReservesCount()
        external
        view
        virtual
        override
        returns (uint256)
    {
        revert NotImplemented();
    }

    function BRIDGE_PROTOCOL_FEE()
        public
        view
        virtual
        override
        returns (uint256)
    {
        revert NotImplemented();
    }

    function FLASHLOAN_PREMIUM_TOTAL()
        public
        view
        virtual
        override
        returns (uint128)
    {
        revert NotImplemented();
    }

    function FLASHLOAN_PREMIUM_TO_PROTOCOL()
        public
        view
        virtual
        override
        returns (uint128)
    {
        revert NotImplemented();
    }

    function MAX_NUMBER_RESERVES()
        public
        view
        virtual
        override
        returns (uint16)
    {
        revert NotImplemented();
    }

    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT()
        public
        view
        virtual
        override
        returns (uint256)
    {
        revert NotImplemented();
    }

    function finalizeTransfer(
        address /* asset */,
        address /* from */,
        address /* to */,
        uint256 /* amount */,
        uint256 /* balanceFromBefore */,
        uint256 /* balanceToBefore */
    ) external virtual override {
        revert NotImplemented();
    }

    function initReserve(
        address /* asset */,
        address /* aTokenAddress */,
        address /* stableDebtAddress */,
        address /* variableDebtAddress */,
        address /* interestRateStrategyAddress */
    ) external virtual override {
        revert NotImplemented();
    }

    function dropReserve(address /* asset */) external virtual override {
        revert NotImplemented();
    }

    function setReserveInterestRateStrategyAddress(
        address /* asset */,
        address /* rateStrategyAddress */
    ) external virtual override {
        revert NotImplemented();
    }

    function setConfiguration(
        address /* asset */,
        DataTypes.ReserveConfigurationMap calldata /* configuration */
    ) external virtual override {
        revert NotImplemented();
    }

    function updateBridgeProtocolFee(
        uint256 /* protocolFee */
    ) external virtual override {
        revert NotImplemented();
    }

    function updateFlashloanPremiums(
        uint128 /* flashLoanPremiumTotal */,
        uint128 /* flashLoanPremiumToProtocol */
    ) external virtual override {
        revert NotImplemented();
    }

    function configureEModeCategory(
        uint8 /* id */,
        DataTypes.EModeCategory memory /* category */
    ) external virtual override {
        revert NotImplemented();
    }

    function getEModeCategoryData(
        uint8 /* id */
    ) external view virtual override returns (DataTypes.EModeCategory memory) {
        revert NotImplemented();
    }

    function setUserEMode(uint8 /* categoryId */) external virtual override {
        revert NotImplemented();
    }

    function getUserEMode(
        address /* user */
    ) external view virtual override returns (uint256) {
        revert NotImplemented();
    }

    function resetIsolationModeTotalDebt(
        address /* asset */
    ) external virtual override {
        revert NotImplemented();
    }

    function rescueTokens(
        address /* token */,
        address /* to */,
        uint256 /* amount */
    ) external virtual override {
        revert NotImplemented();
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external override {
        // Check if we already have the new tokens
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));

        // If balance hasn't increased, we need to transfer
        if (balanceAfter <= balanceBefore) {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }

        userCollateral[onBehalfOf] += amount;
        poolTokens[asset] += amount;
    }

    function getVirtualUnderlyingBalance(
        address /* asset */
    ) external view virtual override returns (uint128) {
        revert NotImplemented();
    }

    error NotImplemented();
}
