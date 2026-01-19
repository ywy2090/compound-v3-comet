// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometMainInterface.sol";
import "./IERC20NonStandard.sol";
import "./IPriceFeed.sol";
import "./IAssetListFactory.sol";
import "./IAssetListFactoryHolder.sol";
import "./IAssetList.sol";

/**
 * @title Compound Comet 合约（扩展资产列表版本）
 * @notice 高效的单体化货币市场协议 - 支持更多抵押资产
 *
 * @dev ============ 与标准 Comet.sol 的主要区别 ============
 * @dev 1. 支持最多 24 个抵押资产（标准版本仅支持 15 个）
 * @dev 2. 使用外部 AssetList 合约存储资产配置，节省主合约空间
 * @dev 3. 使用扩展的位标志系统（uint16 assetsIn + uint8 _reserved）支持 24 个资产
 * @dev 4. 通过 AssetListFactory 动态创建资产列表
 *
 * @dev ============ 核心逻辑（与 Comet.sol 相同）============
 * @dev 以下函数的实现逻辑与标准 Comet.sol 完全相同：
 * @dev - supplyBase / supplyCollateral: 供应基础资产和抵押资产
 * @dev - withdrawBase / withdrawCollateral: 提取资产
 * @dev - transferBase / transferCollateral: 转账资产
 * @dev - buyCollateral: 购买抵押品（补充储备金）
 * @dev - accrueInternal: 利息和奖励累积
 * @dev - updateBasePrincipal: 更新本金和奖励
 * @dev - 暂停功能和权限管理
 *
 * @dev ============ 已添加详细注释的关键函数 ============
 * @dev - constructor: 构造函数，创建外部 AssetList
 * @dev - getAssetInfo: 从外部 AssetList 读取资产信息
 * @dev - isInAsset: 扩展版本，支持 24 个资产的位标志检查
 * @dev - updateAssetsIn: 扩展版本，更新两个位标志字段
 * @dev - isBorrowCollateralized: 使用扩展位标志
 * @dev - isLiquidatable: 使用扩展位标志
 * @dev - absorbInternal: 使用扩展位标志
 *
 * @dev 其他未添加详细注释的函数逻辑与 Comet.sol 相同，请参考 Comet.sol 的注释
 *
 * @author Compound
 */
contract CometWithExtendedAssetList is CometMainInterface {
    /** General configuration constants **/

    /// @notice The admin of the protocol
    address public immutable override governor;

    /// @notice The account which may trigger pauses
    address public immutable override pauseGuardian;

    /// @notice The address of the base token contract
    address public immutable override baseToken;

    /// @notice The address of the price feed for the base token
    address public immutable override baseTokenPriceFeed;

    /// @notice The address of the extension contract delegate
    address public immutable override extensionDelegate;

    /// @notice The point in the supply rates separating the low interest rate slope and the high interest rate slope (factor)
    /// @dev uint64
    uint public immutable override supplyKink;

    /// @notice Per second supply interest rate slope applied when utilization is below kink (factor)
    /// @dev uint64
    uint public immutable override supplyPerSecondInterestRateSlopeLow;

    /// @notice Per second supply interest rate slope applied when utilization is above kink (factor)
    /// @dev uint64
    uint public immutable override supplyPerSecondInterestRateSlopeHigh;

    /// @notice Per second supply base interest rate (factor)
    /// @dev uint64
    uint public immutable override supplyPerSecondInterestRateBase;

    /// @notice The point in the borrow rate separating the low interest rate slope and the high interest rate slope (factor)
    /// @dev uint64
    uint public immutable override borrowKink;

    /// @notice Per second borrow interest rate slope applied when utilization is below kink (factor)
    /// @dev uint64
    uint public immutable override borrowPerSecondInterestRateSlopeLow;

    /// @notice Per second borrow interest rate slope applied when utilization is above kink (factor)
    /// @dev uint64
    uint public immutable override borrowPerSecondInterestRateSlopeHigh;

    /// @notice Per second borrow base interest rate (factor)
    /// @dev uint64
    uint public immutable override borrowPerSecondInterestRateBase;

    /// @notice The fraction of the liquidation penalty that goes to buyers of collateral instead of the protocol
    /// @dev uint64
    uint public immutable override storeFrontPriceFactor;

    /// @notice The scale for base token (must be less than 18 decimals)
    /// @dev uint64
    uint public immutable override baseScale;

    /// @notice The scale for reward tracking
    /// @dev uint64
    uint public immutable override trackingIndexScale;

    /// @notice The speed at which supply rewards are tracked (in trackingIndexScale)
    /// @dev uint64
    uint public immutable override baseTrackingSupplySpeed;

    /// @notice The speed at which borrow rewards are tracked (in trackingIndexScale)
    /// @dev uint64
    uint public immutable override baseTrackingBorrowSpeed;

    /// @notice The minimum amount of base principal wei for rewards to accrue
    /// @dev This must be large enough so as to prevent division by base wei from overflowing the 64 bit indices
    /// @dev uint104
    uint public immutable override baseMinForRewards;

    /// @notice The minimum base amount required to initiate a borrow
    uint public immutable override baseBorrowMin;

    /// @notice The minimum base token reserves which must be held before collateral is hodled
    uint public immutable override targetReserves;

    /// @notice The number of decimals for wrapped base token
    uint8 public immutable override decimals;

    /// @notice The number of assets this contract actually supports
    uint8 public immutable override numAssets;

    /// @notice Factor to divide by when accruing rewards in order to preserve 6 decimals (i.e. baseScale / 1e6)
    uint internal immutable accrualDescaleFactor;

    /// @notice 外部资产列表合约的地址
    /// @dev 存储所有抵押资产的配置信息（最多 24 个）
    /// @dev 使用外部合约可以突破主合约的大小限制
    address public immutable assetList;

    /// @dev 该合约支持的最大资产数量（24 个）
    /// @dev 使用 uint16 assetsIn (16位) + uint8 _reserved (8位) = 24 位标志
    uint8 internal constant MAX_ASSETS_FOR_ASSET_LIST = 24;

    /**
     * @notice 构造函数 - 创建新的协议实例
     * @dev 与标准 Comet 的区别：
     * @dev 1. 检查资产数量上限为 24 个
     * @dev 2. 通过 AssetListFactory 创建外部资产列表
     * @param config 初始配置参数映射
     **/
    constructor(Configuration memory config) {
        // Sanity checks
        uint8 decimals_ = IERC20NonStandard(config.baseToken).decimals();
        if (decimals_ > MAX_BASE_DECIMALS) revert BadDecimals();
        if (config.storeFrontPriceFactor > FACTOR_SCALE) revert BadDiscount();
        if (config.assetConfigs.length > MAX_ASSETS_FOR_ASSET_LIST)
            revert TooManyAssets();
        if (config.baseMinForRewards == 0) revert BadMinimum();
        if (
            IPriceFeed(config.baseTokenPriceFeed).decimals() !=
            PRICE_FEED_DECIMALS
        ) revert BadDecimals();

        // Copy configuration
        unchecked {
            governor = config.governor;
            pauseGuardian = config.pauseGuardian;
            baseToken = config.baseToken;
            baseTokenPriceFeed = config.baseTokenPriceFeed;
            extensionDelegate = config.extensionDelegate;
            storeFrontPriceFactor = config.storeFrontPriceFactor;

            decimals = decimals_;
            baseScale = uint64(10 ** decimals_);
            trackingIndexScale = config.trackingIndexScale;
            if (baseScale < BASE_ACCRUAL_SCALE) revert BadDecimals();
            accrualDescaleFactor = baseScale / BASE_ACCRUAL_SCALE;

            baseMinForRewards = config.baseMinForRewards;
            baseTrackingSupplySpeed = config.baseTrackingSupplySpeed;
            baseTrackingBorrowSpeed = config.baseTrackingBorrowSpeed;

            baseBorrowMin = config.baseBorrowMin;
            targetReserves = config.targetReserves;
        }

        // Set interest rate model configs
        unchecked {
            supplyKink = config.supplyKink;
            supplyPerSecondInterestRateSlopeLow =
                config.supplyPerYearInterestRateSlopeLow /
                SECONDS_PER_YEAR;
            supplyPerSecondInterestRateSlopeHigh =
                config.supplyPerYearInterestRateSlopeHigh /
                SECONDS_PER_YEAR;
            supplyPerSecondInterestRateBase =
                config.supplyPerYearInterestRateBase /
                SECONDS_PER_YEAR;
            borrowKink = config.borrowKink;
            borrowPerSecondInterestRateSlopeLow =
                config.borrowPerYearInterestRateSlopeLow /
                SECONDS_PER_YEAR;
            borrowPerSecondInterestRateSlopeHigh =
                config.borrowPerYearInterestRateSlopeHigh /
                SECONDS_PER_YEAR;
            borrowPerSecondInterestRateBase =
                config.borrowPerYearInterestRateBase /
                SECONDS_PER_YEAR;
        }

        // 设置资产信息
        // 与标准 Comet 的区别：使用外部 AssetList 合约存储资产配置
        numAssets = uint8(config.assetConfigs.length);

        // 步骤 1: 从扩展代理获取 AssetListFactory 地址
        // 步骤 2: 调用工厂创建新的 AssetList 合约实例
        // 步骤 3: 将资产配置传递给新创建的 AssetList 合约
        assetList = IAssetListFactory(
            IAssetListFactoryHolder(extensionDelegate).assetListFactory()
        ).createAssetList(config.assetConfigs);
    }

    /**
     * @dev Prevents marked functions from being reentered
     * Note: this restrict contracts from calling comet functions in their hooks.
     * Doing so will cause the transaction to revert.
     */
    modifier nonReentrant() {
        nonReentrantBefore();
        _;
        nonReentrantAfter();
    }

    /**
     * @dev Checks that the reentrancy flag is not set and then sets the flag
     */
    function nonReentrantBefore() internal {
        bytes32 slot = REENTRANCY_GUARD_FLAG_SLOT;
        uint256 status;
        assembly ("memory-safe") {
            status := sload(slot)
        }

        if (status == REENTRANCY_GUARD_ENTERED) revert ReentrantCallBlocked();
        assembly ("memory-safe") {
            sstore(slot, REENTRANCY_GUARD_ENTERED)
        }
    }

    /**
     * @dev Unsets the reentrancy flag
     */
    function nonReentrantAfter() internal {
        bytes32 slot = REENTRANCY_GUARD_FLAG_SLOT;
        uint256 status;
        assembly ("memory-safe") {
            sstore(slot, REENTRANCY_GUARD_NOT_ENTERED)
        }
    }

    /**
     * @notice Initialize storage for the contract
     * @dev Can be used from constructor or proxy
     */
    function initializeStorage() external override {
        if (lastAccrualTime != 0) revert AlreadyInitialized();

        // Initialize aggregates
        lastAccrualTime = getNowInternal();
        baseSupplyIndex = BASE_INDEX_SCALE;
        baseBorrowIndex = BASE_INDEX_SCALE;

        // Implicit initialization (not worth increasing contract size)
        // trackingSupplyIndex = 0;
        // trackingBorrowIndex = 0;
    }

    /**
     * @notice 获取第 i 个资产的完整信息
     * @dev 与标准 Comet 的区别：从外部 AssetList 合约读取
     * @dev 标准 Comet 从内部不可变变量读取（asset00_a, asset00_b 等）
     * @dev 这里委托给外部合约，节省主合约空间
     * @param i 资产索引（0-23）
     * @return 资产信息结构体，包含地址、价格预言机、抵押率等
     */
    function getAssetInfo(
        uint8 i
    ) public view override returns (AssetInfo memory) {
        // 调用外部 AssetList 合约的 getAssetInfo 函数
        return IAssetList(assetList).getAssetInfo(i);
    }

    /**
     * @dev Determine index of asset that matches given address
     */
    function getAssetInfoByAddress(
        address asset
    ) public view override returns (AssetInfo memory) {
        for (uint8 i = 0; i < numAssets; ) {
            AssetInfo memory assetInfo = getAssetInfo(i);
            if (assetInfo.asset == asset) {
                return assetInfo;
            }
            unchecked {
                i++;
            }
        }
        revert BadAsset();
    }

    /**
     * @return The current timestamp
     **/
    function getNowInternal() internal view virtual returns (uint40) {
        if (block.timestamp >= 2 ** 40) revert TimestampTooLarge();
        return uint40(block.timestamp);
    }

    /**
     * @dev Calculate accrued interest indices for base token supply and borrows
     **/
    function accruedInterestIndices(
        uint timeElapsed
    ) internal view returns (uint64, uint64) {
        uint64 baseSupplyIndex_ = baseSupplyIndex;
        uint64 baseBorrowIndex_ = baseBorrowIndex;
        if (timeElapsed > 0) {
            uint utilization = getUtilization();
            uint supplyRate = getSupplyRate(utilization);
            uint borrowRate = getBorrowRate(utilization);
            baseSupplyIndex_ += safe64(
                mulFactor(baseSupplyIndex_, supplyRate * timeElapsed)
            );
            baseBorrowIndex_ += safe64(
                mulFactor(baseBorrowIndex_, borrowRate * timeElapsed)
            );
        }
        return (baseSupplyIndex_, baseBorrowIndex_);
    }

    /**
     * @dev Accrue interest (and rewards) in base token supply and borrows
     **/
    function accrueInternal() internal {
        uint40 now_ = getNowInternal();
        uint timeElapsed = uint256(now_ - lastAccrualTime);
        if (timeElapsed > 0) {
            (baseSupplyIndex, baseBorrowIndex) = accruedInterestIndices(
                timeElapsed
            );
            if (totalSupplyBase >= baseMinForRewards) {
                trackingSupplyIndex += safe64(
                    divBaseWei(
                        baseTrackingSupplySpeed * timeElapsed,
                        totalSupplyBase
                    )
                );
            }
            if (totalBorrowBase >= baseMinForRewards) {
                trackingBorrowIndex += safe64(
                    divBaseWei(
                        baseTrackingBorrowSpeed * timeElapsed,
                        totalBorrowBase
                    )
                );
            }
            lastAccrualTime = now_;
        }
    }

    /**
     * @notice Accrue interest and rewards for an account
     **/
    function accrueAccount(address account) external override {
        accrueInternal();

        UserBasic memory basic = userBasic[account];
        updateBasePrincipal(account, basic, basic.principal);
    }

    /**
     * @dev Note: Does not accrue interest first
     * @param utilization The utilization to check the supply rate for
     * @return The per second supply rate at `utilization`
     */
    function getSupplyRate(
        uint utilization
    ) public view override returns (uint64) {
        if (utilization <= supplyKink) {
            // interestRateBase + interestRateSlopeLow * utilization
            return
                safe64(
                    supplyPerSecondInterestRateBase +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeLow,
                            utilization
                        )
                );
        } else {
            // interestRateBase + interestRateSlopeLow * kink + interestRateSlopeHigh * (utilization - kink)
            return
                safe64(
                    supplyPerSecondInterestRateBase +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeLow,
                            supplyKink
                        ) +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeHigh,
                            (utilization - supplyKink)
                        )
                );
        }
    }

    /**
     * @dev Note: Does not accrue interest first
     * @param utilization The utilization to check the borrow rate for
     * @return The per second borrow rate at `utilization`
     */
    function getBorrowRate(
        uint utilization
    ) public view override returns (uint64) {
        if (utilization <= borrowKink) {
            // interestRateBase + interestRateSlopeLow * utilization
            return
                safe64(
                    borrowPerSecondInterestRateBase +
                        mulFactor(
                            borrowPerSecondInterestRateSlopeLow,
                            utilization
                        )
                );
        } else {
            // interestRateBase + interestRateSlopeLow * kink + interestRateSlopeHigh * (utilization - kink)
            return
                safe64(
                    borrowPerSecondInterestRateBase +
                        mulFactor(
                            borrowPerSecondInterestRateSlopeLow,
                            borrowKink
                        ) +
                        mulFactor(
                            borrowPerSecondInterestRateSlopeHigh,
                            (utilization - borrowKink)
                        )
                );
        }
    }

    /**
     * @dev Note: Does not accrue interest first
     * @return The utilization rate of the base asset
     */
    function getUtilization() public view override returns (uint) {
        uint totalSupply_ = presentValueSupply(
            baseSupplyIndex,
            totalSupplyBase
        );
        uint totalBorrow_ = presentValueBorrow(
            baseBorrowIndex,
            totalBorrowBase
        );
        if (totalSupply_ == 0) {
            return 0;
        } else {
            return (totalBorrow_ * FACTOR_SCALE) / totalSupply_;
        }
    }

    /**
     * @notice Get the current price from a feed
     * @param priceFeed The address of a price feed
     * @return The price, scaled by `PRICE_SCALE`
     */
    function getPrice(
        address priceFeed
    ) public view override returns (uint256) {
        (, int price, , , ) = IPriceFeed(priceFeed).latestRoundData();
        if (price <= 0) revert BadPrice();
        return uint256(price);
    }

    /**
     * @notice Gets the total balance of protocol collateral reserves for an asset
     * @dev Note: Reverts if collateral reserves are somehow negative, which should not be possible
     * @param asset The collateral asset
     */
    function getCollateralReserves(
        address asset
    ) public view override returns (uint) {
        return
            IERC20NonStandard(asset).balanceOf(address(this)) -
            totalsCollateral[asset].totalSupplyAsset;
    }

    /**
     * @notice Gets the total amount of protocol reserves of the base asset
     */
    function getReserves() public view override returns (int) {
        (
            uint64 baseSupplyIndex_,
            uint64 baseBorrowIndex_
        ) = accruedInterestIndices(getNowInternal() - lastAccrualTime);
        uint balance = IERC20NonStandard(baseToken).balanceOf(address(this));
        uint totalSupply_ = presentValueSupply(
            baseSupplyIndex_,
            totalSupplyBase
        );
        uint totalBorrow_ = presentValueBorrow(
            baseBorrowIndex_,
            totalBorrowBase
        );
        return
            signed256(balance) -
            signed256(totalSupply_) +
            signed256(totalBorrow_);
    }

    /**
     * @notice 检查账户是否有足够抵押品支持借贷
     * @dev 与标准 Comet 的区别：
     * @dev 1. 读取 _reserved 字段以支持资产 16-23
     * @dev 2. 将 _reserved 传递给 isInAsset 函数
     * @dev 3. 可以遍历最多 24 个资产
     * @param account 要检查的账户地址
     * @return 如果抵押充足返回 true，否则返回 false
     */
    function isBorrowCollateralized(
        address account
    ) public view override returns (bool) {
        // 步骤 1: 读取用户本金
        int104 principal = userBasic[account].principal;

        // 步骤 2: 如果本金 ≥ 0（没有借贷），则无需抵押
        if (principal >= 0) {
            return true;
        }

        // 步骤 3: 读取用户的资产位标志（包含扩展字段）
        uint16 assetsIn = userBasic[account].assetsIn; // 资产 0-15
        uint8 _reserved = userBasic[account]._reserved; // 资产 16-23（扩展支持）

        // 步骤 4: 初始化流动性（负值，表示债务的美元价值）
        int liquidity = signedMulPrice(
            presentValue(principal),
            getPrice(baseTokenPriceFeed),
            uint64(baseScale)
        );

        // 步骤 5: 遍历用户的所有抵押资产（最多 24 个）
        for (uint8 i = 0; i < numAssets; ) {
            // 使用扩展版本的 isInAsset，传入 _reserved 参数
            if (isInAsset(assetsIn, i, _reserved)) {
                if (liquidity >= 0) {
                    return true;
                }

                AssetInfo memory asset = getAssetInfo(i);
                uint newAmount = mulPrice(
                    userCollateral[account][asset.asset].balance,
                    getPrice(asset.priceFeed),
                    asset.scale
                );
                liquidity += signed256(
                    mulFactor(newAmount, asset.borrowCollateralFactor)
                );
            }
            unchecked {
                i++;
            }
        }

        return liquidity >= 0;
    }

    /**
     * @notice 检查账户是否可被清算
     * @dev 与标准 Comet 的区别：
     * @dev 1. 读取 _reserved 字段以支持资产 16-23
     * @dev 2. 将 _reserved 传递给 isInAsset 函数
     * @dev 3. 可以遍历最多 24 个资产
     * @param account 要检查的账户地址
     * @return 如果可被清算返回 true，否则返回 false
     */
    function isLiquidatable(
        address account
    ) public view override returns (bool) {
        // 步骤 1: 读取用户本金
        int104 principal = userBasic[account].principal;

        // 步骤 2: 如果本金 ≥ 0（没有借贷），则不能被清算
        if (principal >= 0) {
            return false;
        }

        // 步骤 3: 读取用户的资产位标志（包含扩展字段）
        uint16 assetsIn = userBasic[account].assetsIn; // 资产 0-15
        uint8 _reserved = userBasic[account]._reserved; // 资产 16-23（扩展支持）

        // 步骤 4: 初始化流动性（负值，表示债务的美元价值）
        int liquidity = signedMulPrice(
            presentValue(principal),
            getPrice(baseTokenPriceFeed),
            uint64(baseScale)
        );

        // 步骤 5: 遍历用户的所有抵押资产（最多 24 个）
        for (uint8 i = 0; i < numAssets; ) {
            // 使用扩展版本的 isInAsset，传入 _reserved 参数
            if (isInAsset(assetsIn, i, _reserved)) {
                if (liquidity >= 0) {
                    return false;
                }

                AssetInfo memory asset = getAssetInfo(i);
                uint newAmount = mulPrice(
                    userCollateral[account][asset.asset].balance,
                    getPrice(asset.priceFeed),
                    asset.scale
                );
                liquidity += signed256(
                    mulFactor(newAmount, asset.liquidateCollateralFactor)
                );
            }
            unchecked {
                i++;
            }
        }

        return liquidity < 0;
    }

    /**
     * @dev The change in principal broken into repay and supply amounts
     */
    function repayAndSupplyAmount(
        int104 oldPrincipal,
        int104 newPrincipal
    ) internal pure returns (uint104, uint104) {
        // If the new principal is less than the old principal, then no amount has been repaid or supplied
        if (newPrincipal < oldPrincipal) return (0, 0);

        if (newPrincipal <= 0) {
            return (uint104(newPrincipal - oldPrincipal), 0);
        } else if (oldPrincipal >= 0) {
            return (0, uint104(newPrincipal - oldPrincipal));
        } else {
            return (uint104(-oldPrincipal), uint104(newPrincipal));
        }
    }

    /**
     * @dev The change in principal broken into withdraw and borrow amounts
     */
    function withdrawAndBorrowAmount(
        int104 oldPrincipal,
        int104 newPrincipal
    ) internal pure returns (uint104, uint104) {
        // If the new principal is greater than the old principal, then no amount has been withdrawn or borrowed
        if (newPrincipal > oldPrincipal) return (0, 0);

        if (newPrincipal >= 0) {
            return (uint104(oldPrincipal - newPrincipal), 0);
        } else if (oldPrincipal <= 0) {
            return (0, uint104(oldPrincipal - newPrincipal));
        } else {
            return (uint104(oldPrincipal), uint104(-newPrincipal));
        }
    }

    /**
     * @notice Pauses different actions within Comet
     * @param supplyPaused Boolean for pausing supply actions
     * @param transferPaused Boolean for pausing transfer actions
     * @param withdrawPaused Boolean for pausing withdraw actions
     * @param absorbPaused Boolean for pausing absorb actions
     * @param buyPaused Boolean for pausing buy actions
     */
    function pause(
        bool supplyPaused,
        bool transferPaused,
        bool withdrawPaused,
        bool absorbPaused,
        bool buyPaused
    ) external override {
        if (msg.sender != governor && msg.sender != pauseGuardian)
            revert Unauthorized();

        pauseFlags =
            uint8(0) |
            (toUInt8(supplyPaused) << PAUSE_SUPPLY_OFFSET) |
            (toUInt8(transferPaused) << PAUSE_TRANSFER_OFFSET) |
            (toUInt8(withdrawPaused) << PAUSE_WITHDRAW_OFFSET) |
            (toUInt8(absorbPaused) << PAUSE_ABSORB_OFFSET) |
            (toUInt8(buyPaused) << PAUSE_BUY_OFFSET);

        emit PauseAction(
            supplyPaused,
            transferPaused,
            withdrawPaused,
            absorbPaused,
            buyPaused
        );
    }

    /**
     * @return Whether or not supply actions are paused
     */
    function isSupplyPaused() public view override returns (bool) {
        return toBool(pauseFlags & (uint8(1) << PAUSE_SUPPLY_OFFSET));
    }

    /**
     * @return Whether or not transfer actions are paused
     */
    function isTransferPaused() public view override returns (bool) {
        return toBool(pauseFlags & (uint8(1) << PAUSE_TRANSFER_OFFSET));
    }

    /**
     * @return Whether or not withdraw actions are paused
     */
    function isWithdrawPaused() public view override returns (bool) {
        return toBool(pauseFlags & (uint8(1) << PAUSE_WITHDRAW_OFFSET));
    }

    /**
     * @return Whether or not absorb actions are paused
     */
    function isAbsorbPaused() public view override returns (bool) {
        return toBool(pauseFlags & (uint8(1) << PAUSE_ABSORB_OFFSET));
    }

    /**
     * @return Whether or not buy actions are paused
     */
    function isBuyPaused() public view override returns (bool) {
        return toBool(pauseFlags & (uint8(1) << PAUSE_BUY_OFFSET));
    }

    /**
     * @dev Multiply a number by a factor
     */
    function mulFactor(uint n, uint factor) internal pure returns (uint) {
        return (n * factor) / FACTOR_SCALE;
    }

    /**
     * @dev Divide a number by an amount of base
     */
    function divBaseWei(uint n, uint baseWei) internal view returns (uint) {
        return (n * baseScale) / baseWei;
    }

    /**
     * @dev Multiply a `fromScale` quantity by a price, returning a common price quantity
     */
    function mulPrice(
        uint n,
        uint price,
        uint64 fromScale
    ) internal pure returns (uint) {
        return (n * price) / fromScale;
    }

    /**
     * @dev Multiply a signed `fromScale` quantity by a price, returning a common price quantity
     */
    function signedMulPrice(
        int n,
        uint price,
        uint64 fromScale
    ) internal pure returns (int) {
        return (n * signed256(price)) / int256(uint256(fromScale));
    }

    /**
     * @dev Divide a common price quantity by a price, returning a `toScale` quantity
     */
    function divPrice(
        uint n,
        uint price,
        uint64 toScale
    ) internal pure returns (uint) {
        return (n * toScale) / price;
    }

    /**
     * @dev 检查用户是否持有某个抵押资产（扩展版本，支持 24 个资产）
     * @dev 与标准 Comet 的区别：使用两个位标志字段支持 24 个资产
     * @dev - assetsIn (uint16): 存储资产 0-15 的位标志
     * @dev - _reserved (uint8): 存储资产 16-23 的位标志
     *
     * @dev 示例：
     * @dev assetsIn = 0b0000000000000101 (持有资产 0 和 2)
     * @dev _reserved = 0b00000011 (持有资产 16 和 17)
     *
     * @param assetsIn 用户的资产位标志（位 0-15）
     * @param assetOffset 资产的索引位置（0-23）
     * @param _reserved 用户的扩展资产位标志（位 16-23）
     * @return 如果用户持有该资产返回 true，否则返回 false
     */
    function isInAsset(
        uint16 assetsIn,
        uint8 assetOffset,
        uint8 _reserved
    ) internal pure returns (bool) {
        if (assetOffset < 16) {
            // 情况 1: 资产 0-15，检查 assetsIn 的对应位
            // 例如：assetOffset = 2，检查第 2 位
            return (assetsIn & (uint16(1) << assetOffset)) != 0;
        } else if (assetOffset < 24) {
            // 情况 2: 资产 16-23，检查 _reserved 的对应位
            // 例如：assetOffset = 18，检查 _reserved 的第 (18-16=2) 位
            return (_reserved & (uint8(1) << (assetOffset - 16))) != 0;
        }
        // 情况 3: assetOffset >= 24（不应该发生）
        return false;
    }

    /**
     * @dev 更新用户的 assetsIn 位标志（扩展版本，支持 24 个资产）
     * @dev 与标准 Comet 的区别：需要同时更新 assetsIn 和 _reserved 两个字段
     * @dev 当用户首次持有某资产时设置对应位，余额清零时清除对应位
     *
     * @dev 这个标志用于：
     * @dev 1. 清算时快速遍历用户持有的抵押品
     * @dev 2. 抵押检查时只计算相关资产
     *
     * @param account 用户地址
     * @param assetInfo 资产信息（包含 offset）
     * @param initialUserBalance 操作前的余额
     * @param finalUserBalance 操作后的余额
     */
    function updateAssetsIn(
        address account,
        AssetInfo memory assetInfo,
        uint128 initialUserBalance,
        uint128 finalUserBalance
    ) internal {
        if (initialUserBalance == 0 && finalUserBalance != 0) {
            // 从 0 变为非 0：设置对应位
            if (assetInfo.offset < 16) {
                // 资产 0-15：设置 assetsIn 的对应位
                // 例如：资产 2，设置第 2 位
                // assetsIn |= 0b0000000000000100
                userBasic[account].assetsIn |= (uint16(1) << assetInfo.offset);
            } else if (assetInfo.offset < 24) {
                // 资产 16-23：设置 _reserved 的对应位
                // 例如：资产 18，设置 _reserved 的第 (18-16=2) 位
                // _reserved |= 0b00000100
                userBasic[account]._reserved |= (uint8(1) <<
                    (assetInfo.offset - 16));
            }
        } else if (initialUserBalance != 0 && finalUserBalance == 0) {
            // 从非 0 变为 0：清除对应位
            if (assetInfo.offset < 16) {
                // 资产 0-15：清除 assetsIn 的对应位
                // 例如：资产 2，清除第 2 位
                // assetsIn &= ~0b0000000000000100 = assetsIn & 0b1111111111111011
                userBasic[account].assetsIn &= ~(uint16(1) << assetInfo.offset);
            } else if (assetInfo.offset < 24) {
                // 资产 16-23：清除 _reserved 的对应位
                // 例如：资产 18，清除 _reserved 的第 (18-16=2) 位
                // _reserved &= ~0b00000100 = _reserved & 0b11111011
                userBasic[account]._reserved &= ~(uint8(1) <<
                    (assetInfo.offset - 16));
            }
        }
        // 其他情况（非 0 → 非 0，或 0 → 0）不需要更新
    }

    /**
     * @dev Write updated principal to store and tracking participation
     */
    function updateBasePrincipal(
        address account,
        UserBasic memory basic,
        int104 principalNew
    ) internal {
        int104 principal = basic.principal;
        basic.principal = principalNew;

        if (principal >= 0) {
            uint indexDelta = uint256(
                trackingSupplyIndex - basic.baseTrackingIndex
            );
            basic.baseTrackingAccrued += safe64(
                (uint104(principal) * indexDelta) /
                    trackingIndexScale /
                    accrualDescaleFactor
            );
        } else {
            uint indexDelta = uint256(
                trackingBorrowIndex - basic.baseTrackingIndex
            );
            basic.baseTrackingAccrued += safe64(
                (uint104(-principal) * indexDelta) /
                    trackingIndexScale /
                    accrualDescaleFactor
            );
        }

        if (principalNew >= 0) {
            basic.baseTrackingIndex = trackingSupplyIndex;
        } else {
            basic.baseTrackingIndex = trackingBorrowIndex;
        }

        userBasic[account] = basic;
    }

    /**
     * @dev Safe ERC20 transfer in and returns the final amount transferred (taking into account any fees)
     * @dev Note: Safely handles non-standard ERC-20 tokens that do not return a value. See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(
        address asset,
        address from,
        uint amount
    ) internal returns (uint) {
        uint256 preTransferBalance = IERC20NonStandard(asset).balanceOf(
            address(this)
        );
        IERC20NonStandard(asset).transferFrom(from, address(this), amount);
        bool success;
        assembly ("memory-safe") {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        if (!success) revert TransferInFailed();
        return
            IERC20NonStandard(asset).balanceOf(address(this)) -
            preTransferBalance;
    }

    /**
     * @dev Safe ERC20 transfer out
     * @dev Note: Safely handles non-standard ERC-20 tokens that do not return a value. See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address asset, address to, uint amount) internal {
        IERC20NonStandard(asset).transfer(to, amount);
        bool success;
        assembly ("memory-safe") {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        if (!success) revert TransferOutFailed();
    }

    /**
     * @notice Supply an amount of asset to the protocol
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supply(address asset, uint amount) external override {
        return
            supplyInternal(msg.sender, msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Supply an amount of asset to dst
     * @param dst The address which will hold the balance
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supplyTo(
        address dst,
        address asset,
        uint amount
    ) external override {
        return supplyInternal(msg.sender, msg.sender, dst, asset, amount);
    }

    /**
     * @notice Supply an amount of asset from `from` to dst, if allowed
     * @param from The supplier address
     * @param dst The address which will hold the balance
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supplyFrom(
        address from,
        address dst,
        address asset,
        uint amount
    ) external override {
        return supplyInternal(msg.sender, from, dst, asset, amount);
    }

    /**
     * @dev Supply either collateral or base asset, depending on the asset, if operator is allowed
     * @dev Note: Specifying an `amount` of uint256.max will repay all of `dst`'s accrued base borrow balance
     */
    function supplyInternal(
        address operator,
        address from,
        address dst,
        address asset,
        uint amount
    ) internal nonReentrant {
        if (isSupplyPaused()) revert Paused();
        if (!hasPermission(from, operator)) revert Unauthorized();

        if (asset == baseToken) {
            if (amount == type(uint256).max) {
                amount = borrowBalanceOf(dst);
            }
            return supplyBase(from, dst, amount);
        } else {
            return supplyCollateral(from, dst, asset, safe128(amount));
        }
    }

    /**
     * @dev Supply an amount of base asset from `from` to dst
     */
    function supplyBase(address from, address dst, uint256 amount) internal {
        amount = doTransferIn(baseToken, from, amount);

        accrueInternal();

        UserBasic memory dstUser = userBasic[dst];
        int104 dstPrincipal = dstUser.principal;
        int256 dstBalance = presentValue(dstPrincipal) + signed256(amount);
        int104 dstPrincipalNew = principalValue(dstBalance);

        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            dstPrincipal,
            dstPrincipalNew
        );

        totalSupplyBase += supplyAmount;
        totalBorrowBase -= repayAmount;

        updateBasePrincipal(dst, dstUser, dstPrincipalNew);

        emit Supply(from, dst, amount);

        if (supplyAmount > 0) {
            emit Transfer(
                address(0),
                dst,
                presentValueSupply(baseSupplyIndex, supplyAmount)
            );
        }
    }

    /**
     * @dev Supply an amount of collateral asset from `from` to dst
     */
    function supplyCollateral(
        address from,
        address dst,
        address asset,
        uint128 amount
    ) internal {
        amount = safe128(doTransferIn(asset, from, amount));

        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        TotalsCollateral memory totals = totalsCollateral[asset];
        totals.totalSupplyAsset += amount;
        if (totals.totalSupplyAsset > assetInfo.supplyCap)
            revert SupplyCapExceeded();

        uint128 dstCollateral = userCollateral[dst][asset].balance;
        uint128 dstCollateralNew = dstCollateral + amount;

        totalsCollateral[asset] = totals;
        userCollateral[dst][asset].balance = dstCollateralNew;

        updateAssetsIn(dst, assetInfo, dstCollateral, dstCollateralNew);

        emit SupplyCollateral(from, dst, asset, amount);
    }

    /**
     * @notice ERC20 transfer an amount of base token to dst
     * @param dst The recipient address
     * @param amount The quantity to transfer
     * @return true
     */
    function transfer(
        address dst,
        uint amount
    ) external override returns (bool) {
        transferInternal(msg.sender, msg.sender, dst, baseToken, amount);
        return true;
    }

    /**
     * @notice ERC20 transfer an amount of base token from src to dst, if allowed
     * @param src The sender address
     * @param dst The recipient address
     * @param amount The quantity to transfer
     * @return true
     */
    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external override returns (bool) {
        transferInternal(msg.sender, src, dst, baseToken, amount);
        return true;
    }

    /**
     * @notice Transfer an amount of asset to dst
     * @param dst The recipient address
     * @param asset The asset to transfer
     * @param amount The quantity to transfer
     */
    function transferAsset(
        address dst,
        address asset,
        uint amount
    ) external override {
        return transferInternal(msg.sender, msg.sender, dst, asset, amount);
    }

    /**
     * @notice Transfer an amount of asset from src to dst, if allowed
     * @param src The sender address
     * @param dst The recipient address
     * @param asset The asset to transfer
     * @param amount The quantity to transfer
     */
    function transferAssetFrom(
        address src,
        address dst,
        address asset,
        uint amount
    ) external override {
        return transferInternal(msg.sender, src, dst, asset, amount);
    }

    /**
     * @dev Transfer either collateral or base asset, depending on the asset, if operator is allowed
     * @dev Note: Specifying an `amount` of uint256.max will transfer all of `src`'s accrued base balance
     */
    function transferInternal(
        address operator,
        address src,
        address dst,
        address asset,
        uint amount
    ) internal nonReentrant {
        if (isTransferPaused()) revert Paused();
        if (!hasPermission(src, operator)) revert Unauthorized();
        if (src == dst) revert NoSelfTransfer();

        if (asset == baseToken) {
            if (amount == type(uint256).max) {
                amount = balanceOf(src);
            }
            return transferBase(src, dst, amount);
        } else {
            return transferCollateral(src, dst, asset, safe128(amount));
        }
    }

    /**
     * @dev Transfer an amount of base asset from src to dst, borrowing if possible/necessary
     */
    function transferBase(address src, address dst, uint256 amount) internal {
        accrueInternal();

        UserBasic memory srcUser = userBasic[src];
        UserBasic memory dstUser = userBasic[dst];

        int104 srcPrincipal = srcUser.principal;
        int104 dstPrincipal = dstUser.principal;
        int256 srcBalance = presentValue(srcPrincipal) - signed256(amount);
        int256 dstBalance = presentValue(dstPrincipal) + signed256(amount);
        int104 srcPrincipalNew = principalValue(srcBalance);
        int104 dstPrincipalNew = principalValue(dstBalance);

        (
            uint104 withdrawAmount,
            uint104 borrowAmount
        ) = withdrawAndBorrowAmount(srcPrincipal, srcPrincipalNew);
        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            dstPrincipal,
            dstPrincipalNew
        );

        // Note: Instead of `total += addAmount - subAmount` to avoid underflow errors.
        totalSupplyBase = totalSupplyBase + supplyAmount - withdrawAmount;
        totalBorrowBase = totalBorrowBase + borrowAmount - repayAmount;

        updateBasePrincipal(src, srcUser, srcPrincipalNew);
        updateBasePrincipal(dst, dstUser, dstPrincipalNew);

        if (srcBalance < 0) {
            if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
            if (!isBorrowCollateralized(src)) revert NotCollateralized();
        }

        if (withdrawAmount > 0) {
            emit Transfer(
                src,
                address(0),
                presentValueSupply(baseSupplyIndex, withdrawAmount)
            );
        }

        if (supplyAmount > 0) {
            emit Transfer(
                address(0),
                dst,
                presentValueSupply(baseSupplyIndex, supplyAmount)
            );
        }
    }

    /**
     * @dev Transfer an amount of collateral asset from src to dst
     */
    function transferCollateral(
        address src,
        address dst,
        address asset,
        uint128 amount
    ) internal {
        uint128 srcCollateral = userCollateral[src][asset].balance;
        uint128 dstCollateral = userCollateral[dst][asset].balance;
        uint128 srcCollateralNew = srcCollateral - amount;
        uint128 dstCollateralNew = dstCollateral + amount;

        userCollateral[src][asset].balance = srcCollateralNew;
        userCollateral[dst][asset].balance = dstCollateralNew;

        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        updateAssetsIn(src, assetInfo, srcCollateral, srcCollateralNew);
        updateAssetsIn(dst, assetInfo, dstCollateral, dstCollateralNew);

        // Note: no accrue interest, BorrowCF < LiquidationCF covers small changes
        if (!isBorrowCollateralized(src)) revert NotCollateralized();

        emit TransferCollateral(src, dst, asset, amount);
    }

    /**
     * @notice Withdraw an amount of asset from the protocol
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdraw(address asset, uint amount) external override {
        return
            withdrawInternal(msg.sender, msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Withdraw an amount of asset to `to`
     * @param to The recipient address
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdrawTo(
        address to,
        address asset,
        uint amount
    ) external override {
        return withdrawInternal(msg.sender, msg.sender, to, asset, amount);
    }

    /**
     * @notice Withdraw an amount of asset from src to `to`, if allowed
     * @param src The sender address
     * @param to The recipient address
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdrawFrom(
        address src,
        address to,
        address asset,
        uint amount
    ) external override {
        return withdrawInternal(msg.sender, src, to, asset, amount);
    }

    /**
     * @dev Withdraw either collateral or base asset, depending on the asset, if operator is allowed
     * @dev Note: Specifying an `amount` of uint256.max will withdraw all of `src`'s accrued base balance
     */
    function withdrawInternal(
        address operator,
        address src,
        address to,
        address asset,
        uint amount
    ) internal nonReentrant {
        if (isWithdrawPaused()) revert Paused();
        if (!hasPermission(src, operator)) revert Unauthorized();

        if (asset == baseToken) {
            if (amount == type(uint256).max) {
                amount = balanceOf(src);
            }
            return withdrawBase(src, to, amount);
        } else {
            return withdrawCollateral(src, to, asset, safe128(amount));
        }
    }

    /**
     * @dev Withdraw an amount of base asset from src to `to`, borrowing if possible/necessary
     */
    function withdrawBase(address src, address to, uint256 amount) internal {
        accrueInternal();

        UserBasic memory srcUser = userBasic[src];
        int104 srcPrincipal = srcUser.principal;
        int256 srcBalance = presentValue(srcPrincipal) - signed256(amount);
        int104 srcPrincipalNew = principalValue(srcBalance);

        (
            uint104 withdrawAmount,
            uint104 borrowAmount
        ) = withdrawAndBorrowAmount(srcPrincipal, srcPrincipalNew);

        totalSupplyBase -= withdrawAmount;
        totalBorrowBase += borrowAmount;

        updateBasePrincipal(src, srcUser, srcPrincipalNew);

        if (srcBalance < 0) {
            if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
            if (!isBorrowCollateralized(src)) revert NotCollateralized();
        }

        doTransferOut(baseToken, to, amount);

        emit Withdraw(src, to, amount);

        if (withdrawAmount > 0) {
            emit Transfer(
                src,
                address(0),
                presentValueSupply(baseSupplyIndex, withdrawAmount)
            );
        }
    }

    /**
     * @dev Withdraw an amount of collateral asset from src to `to`
     */
    function withdrawCollateral(
        address src,
        address to,
        address asset,
        uint128 amount
    ) internal {
        uint128 srcCollateral = userCollateral[src][asset].balance;
        uint128 srcCollateralNew = srcCollateral - amount;

        totalsCollateral[asset].totalSupplyAsset -= amount;
        userCollateral[src][asset].balance = srcCollateralNew;

        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        updateAssetsIn(src, assetInfo, srcCollateral, srcCollateralNew);

        // Note: no accrue interest, BorrowCF < LiquidationCF covers small changes
        if (!isBorrowCollateralized(src)) revert NotCollateralized();

        doTransferOut(asset, to, amount);

        emit WithdrawCollateral(src, to, asset, amount);
    }

    /**
     * @notice Absorb a list of underwater accounts onto the protocol balance sheet
     * @param absorber The recipient of the incentive paid to the caller of absorb
     * @param accounts The list of underwater accounts to absorb
     */
    function absorb(
        address absorber,
        address[] calldata accounts
    ) external override {
        if (isAbsorbPaused()) revert Paused();

        uint startGas = gasleft();
        accrueInternal();
        for (uint i = 0; i < accounts.length; ) {
            absorbInternal(absorber, accounts[i]);
            unchecked {
                i++;
            }
        }
        uint gasUsed = startGas - gasleft();

        // Note: liquidator points are an imperfect tool for governance,
        //  to be used while evaluating strategies for incentivizing absorption.
        // Using gas price instead of base fee would more accurately reflect spend,
        //  but is also subject to abuse if refunds were to be given automatically.
        LiquidatorPoints memory points = liquidatorPoints[absorber];
        points.numAbsorbs++;
        points.numAbsorbed += safe64(accounts.length);
        points.approxSpend += safe128(gasUsed * block.basefee);
        liquidatorPoints[absorber] = points;
    }

    /**
     * @dev 清算账户（内部函数）
     * @dev 将用户的抵押品和债务转移到协议，协议储备金承担坏账
     * @dev 与标准 Comet 的区别：
     * @dev 1. 读取 _reserved 字段以支持资产 16-23
     * @dev 2. 将 _reserved 传递给 isInAsset 函数
     * @dev 3. 可以没收最多 24 个资产
     * @param absorber 清算执行人（会获得清算积分奖励）
     * @param account 被清算的账户
     */
    function absorbInternal(address absorber, address account) internal {
        // 步骤 1: 检查账户是否满足清算条件
        if (!isLiquidatable(account)) revert NotLiquidatable();

        // 步骤 2: 读取账户的当前状态（包含扩展字段）
        UserBasic memory accountUser = userBasic[account];
        int104 oldPrincipal = accountUser.principal;
        int256 oldBalance = presentValue(oldPrincipal);
        uint16 assetsIn = accountUser.assetsIn; // 资产 0-15
        uint8 _reserved = accountUser._reserved; // 资产 16-23（扩展支持）

        // 步骤 3: 获取基础资产价格
        uint256 basePrice = getPrice(baseTokenPriceFeed);
        uint256 deltaValue = 0;

        // 步骤 4: 遍历并没收用户的所有抵押品（最多 24 个）
        for (uint8 i = 0; i < numAssets; ) {
            // 使用扩展版本的 isInAsset，传入 _reserved 参数
            if (isInAsset(assetsIn, i, _reserved)) {
                AssetInfo memory assetInfo = getAssetInfo(i);
                address asset = assetInfo.asset;
                uint128 seizeAmount = userCollateral[account][asset].balance;
                userCollateral[account][asset].balance = 0;
                totalsCollateral[asset].totalSupplyAsset -= seizeAmount;

                uint256 value = mulPrice(
                    seizeAmount,
                    getPrice(assetInfo.priceFeed),
                    assetInfo.scale
                );
                deltaValue += mulFactor(value, assetInfo.liquidationFactor);

                emit AbsorbCollateral(
                    absorber,
                    account,
                    asset,
                    seizeAmount,
                    value
                );
            }
            unchecked {
                i++;
            }
        }

        uint256 deltaBalance = divPrice(
            deltaValue,
            basePrice,
            uint64(baseScale)
        );
        int256 newBalance = oldBalance + signed256(deltaBalance);
        // New balance will not be negative, all excess debt absorbed by reserves
        if (newBalance < 0) {
            newBalance = 0;
        }

        int104 newPrincipal = principalValue(newBalance);
        updateBasePrincipal(account, accountUser, newPrincipal);

        // reset assetsIn
        userBasic[account].assetsIn = 0;
        userBasic[account]._reserved = 0;

        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            oldPrincipal,
            newPrincipal
        );

        // Reserves are decreased by increasing total supply and decreasing borrows
        //  the amount of debt repaid by reserves is `newBalance - oldBalance`
        totalSupplyBase += supplyAmount;
        totalBorrowBase -= repayAmount;

        uint256 basePaidOut = unsigned256(newBalance - oldBalance);
        uint256 valueOfBasePaidOut = mulPrice(
            basePaidOut,
            basePrice,
            uint64(baseScale)
        );
        emit AbsorbDebt(absorber, account, basePaidOut, valueOfBasePaidOut);

        if (newPrincipal > 0) {
            emit Transfer(
                address(0),
                account,
                presentValueSupply(baseSupplyIndex, unsigned104(newPrincipal))
            );
        }
    }

    /**
     * @notice Buy collateral from the protocol using base tokens, increasing protocol reserves
       A minimum collateral amount should be specified to indicate the maximum slippage acceptable for the buyer.
     * @param asset The asset to buy
     * @param minAmount The minimum amount of collateral tokens that should be received by the buyer
     * @param baseAmount The amount of base tokens used to buy the collateral
     * @param recipient The recipient address
     */
    function buyCollateral(
        address asset,
        uint minAmount,
        uint baseAmount,
        address recipient
    ) external override nonReentrant {
        if (isBuyPaused()) revert Paused();

        int reserves = getReserves();
        if (reserves >= 0 && uint(reserves) >= targetReserves)
            revert NotForSale();

        // Note: Re-entrancy can skip the reserves check above on a second buyCollateral call.
        baseAmount = doTransferIn(baseToken, msg.sender, baseAmount);

        uint collateralAmount = quoteCollateral(asset, baseAmount);
        if (collateralAmount < minAmount) revert TooMuchSlippage();
        if (collateralAmount > getCollateralReserves(asset))
            revert InsufficientReserves();

        // Note: Pre-transfer hook can re-enter buyCollateral with a stale collateral ERC20 balance.
        //  Assets should not be listed which allow re-entry from pre-transfer now, as too much collateral could be bought.
        //  This is also a problem if quoteCollateral derives its discount from the collateral ERC20 balance.
        doTransferOut(asset, recipient, safe128(collateralAmount));

        emit BuyCollateral(msg.sender, asset, baseAmount, collateralAmount);
    }

    /**
     * @notice Gets the quote for a collateral asset in exchange for an amount of base asset
     * @param asset The collateral asset to get the quote for
     * @param baseAmount The amount of the base asset to get the quote for
     * @return The quote in terms of the collateral asset
     */
    function quoteCollateral(
        address asset,
        uint baseAmount
    ) public view override returns (uint) {
        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        uint256 assetPrice = getPrice(assetInfo.priceFeed);
        // Store front discount is derived from the collateral asset's liquidationFactor and storeFrontPriceFactor
        // discount = storeFrontPriceFactor * (1e18 - liquidationFactor)
        uint256 discountFactor = mulFactor(
            storeFrontPriceFactor,
            FACTOR_SCALE - assetInfo.liquidationFactor
        );
        uint256 assetPriceDiscounted = mulFactor(
            assetPrice,
            FACTOR_SCALE - discountFactor
        );
        uint256 basePrice = getPrice(baseTokenPriceFeed);
        // # of collateral assets
        // = (TotalValueOfBaseAmount / DiscountedPriceOfCollateralAsset) * assetScale
        // = ((basePrice * baseAmount / baseScale) / assetPriceDiscounted) * assetScale
        return
            (basePrice * baseAmount * assetInfo.scale) /
            assetPriceDiscounted /
            baseScale;
    }

    /**
     * @notice Withdraws base token reserves if called by the governor
     * @param to An address of the receiver of withdrawn reserves
     * @param amount The amount of reserves to be withdrawn from the protocol
     */
    function withdrawReserves(address to, uint amount) external override {
        if (msg.sender != governor) revert Unauthorized();

        int reserves = getReserves();
        if (reserves < 0 || amount > unsigned256(reserves))
            revert InsufficientReserves();

        doTransferOut(baseToken, to, amount);

        emit WithdrawReserves(to, amount);
    }

    /**
     * @notice Sets Comet's ERC20 allowance of an asset for a manager
     * @dev Only callable by governor
     * @dev Note: Setting the `asset` as Comet's address will allow the manager
     * to withdraw from Comet's Comet balance
     * @dev Note: For USDT, if there is non-zero prior allowance, it must be reset to 0 first before setting a new value in proposal
     * @param asset The asset that the manager will gain approval of
     * @param manager The account which will be allowed or disallowed
     * @param amount The amount of an asset to approve
     */
    function approveThis(
        address manager,
        address asset,
        uint amount
    ) external override {
        if (msg.sender != governor) revert Unauthorized();

        IERC20NonStandard(asset).approve(manager, amount);
    }

    /**
     * @notice Get the total number of tokens in circulation
     * @dev Note: uses updated interest indices to calculate
     * @return The supply of tokens
     **/
    function totalSupply() external view override returns (uint256) {
        (uint64 baseSupplyIndex_, ) = accruedInterestIndices(
            getNowInternal() - lastAccrualTime
        );
        return presentValueSupply(baseSupplyIndex_, totalSupplyBase);
    }

    /**
     * @notice Get the total amount of debt
     * @dev Note: uses updated interest indices to calculate
     * @return The amount of debt
     **/
    function totalBorrow() external view override returns (uint256) {
        (, uint64 baseBorrowIndex_) = accruedInterestIndices(
            getNowInternal() - lastAccrualTime
        );
        return presentValueBorrow(baseBorrowIndex_, totalBorrowBase);
    }

    /**
     * @notice Query the current positive base balance of an account or zero
     * @dev Note: uses updated interest indices to calculate
     * @param account The account whose balance to query
     * @return The present day base balance magnitude of the account, if positive
     */
    function balanceOf(address account) public view override returns (uint256) {
        (uint64 baseSupplyIndex_, ) = accruedInterestIndices(
            getNowInternal() - lastAccrualTime
        );
        int104 principal = userBasic[account].principal;
        return
            principal > 0
                ? presentValueSupply(baseSupplyIndex_, unsigned104(principal))
                : 0;
    }

    /**
     * @notice Query the current negative base balance of an account or zero
     * @dev Note: uses updated interest indices to calculate
     * @param account The account whose balance to query
     * @return The present day base balance magnitude of the account, if negative
     */
    function borrowBalanceOf(
        address account
    ) public view override returns (uint256) {
        (, uint64 baseBorrowIndex_) = accruedInterestIndices(
            getNowInternal() - lastAccrualTime
        );
        int104 principal = userBasic[account].principal;
        return
            principal < 0
                ? presentValueBorrow(baseBorrowIndex_, unsigned104(-principal))
                : 0;
    }

    /**
     * @notice Fallback to calling the extension delegate for everything else
     */
    fallback() external payable {
        address delegate = extensionDelegate;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), delegate, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
