// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometMainInterface.sol";
import "./IERC20NonStandard.sol";
import "./IPriceFeed.sol";

/**
 * @title Compound's Comet Contract
 * @notice An efficient monolithic money market protocol
 * @dev 中文：主合约，负责存取款、借贷、清算、利率与储备计算
 * @author Compound
 */
contract Comet is CometMainInterface {
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

    /** Collateral asset configuration (packed) **/

    uint256 internal immutable asset00_a;
    uint256 internal immutable asset00_b;
    uint256 internal immutable asset01_a;
    uint256 internal immutable asset01_b;
    uint256 internal immutable asset02_a;
    uint256 internal immutable asset02_b;
    uint256 internal immutable asset03_a;
    uint256 internal immutable asset03_b;
    uint256 internal immutable asset04_a;
    uint256 internal immutable asset04_b;
    uint256 internal immutable asset05_a;
    uint256 internal immutable asset05_b;
    uint256 internal immutable asset06_a;
    uint256 internal immutable asset06_b;
    uint256 internal immutable asset07_a;
    uint256 internal immutable asset07_b;
    uint256 internal immutable asset08_a;
    uint256 internal immutable asset08_b;
    uint256 internal immutable asset09_a;
    uint256 internal immutable asset09_b;
    uint256 internal immutable asset10_a;
    uint256 internal immutable asset10_b;
    uint256 internal immutable asset11_a;
    uint256 internal immutable asset11_b;

    /**
     * @notice Construct a new protocol instance
     * @param config The mapping of initial/constant parameters
     **/
    constructor(Configuration memory config) {
        // Sanity checks
        uint8 decimals_ = IERC20NonStandard(config.baseToken).decimals();
        if (decimals_ > MAX_BASE_DECIMALS) revert BadDecimals();
        if (config.storeFrontPriceFactor > FACTOR_SCALE) revert BadDiscount();
        if (config.assetConfigs.length > MAX_ASSETS) revert TooManyAssets();
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

        // Set asset info
        numAssets = uint8(config.assetConfigs.length);

        (asset00_a, asset00_b) = getPackedAssetInternal(config.assetConfigs, 0);
        (asset01_a, asset01_b) = getPackedAssetInternal(config.assetConfigs, 1);
        (asset02_a, asset02_b) = getPackedAssetInternal(config.assetConfigs, 2);
        (asset03_a, asset03_b) = getPackedAssetInternal(config.assetConfigs, 3);
        (asset04_a, asset04_b) = getPackedAssetInternal(config.assetConfigs, 4);
        (asset05_a, asset05_b) = getPackedAssetInternal(config.assetConfigs, 5);
        (asset06_a, asset06_b) = getPackedAssetInternal(config.assetConfigs, 6);
        (asset07_a, asset07_b) = getPackedAssetInternal(config.assetConfigs, 7);
        (asset08_a, asset08_b) = getPackedAssetInternal(config.assetConfigs, 8);
        (asset09_a, asset09_b) = getPackedAssetInternal(config.assetConfigs, 9);
        (asset10_a, asset10_b) = getPackedAssetInternal(
            config.assetConfigs,
            10
        );
        (asset11_a, asset11_b) = getPackedAssetInternal(
            config.assetConfigs,
            11
        );
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
     * @dev Checks and gets the packed asset info for storage
     */
    function getPackedAssetInternal(
        AssetConfig[] memory assetConfigs,
        uint i
    ) internal view returns (uint256, uint256) {
        AssetConfig memory assetConfig;
        if (i < assetConfigs.length) {
            assembly {
                assetConfig := mload(add(add(assetConfigs, 0x20), mul(i, 0x20)))
            }
        } else {
            return (0, 0);
        }
        address asset = assetConfig.asset;
        address priceFeed = assetConfig.priceFeed;
        uint8 decimals_ = assetConfig.decimals;

        // Short-circuit if asset is nil
        if (asset == address(0)) {
            return (0, 0);
        }

        // Sanity check price feed and asset decimals
        if (IPriceFeed(priceFeed).decimals() != PRICE_FEED_DECIMALS)
            revert BadDecimals();
        if (IERC20NonStandard(asset).decimals() != decimals_)
            revert BadDecimals();

        // Ensure collateral factors are within range
        if (
            assetConfig.borrowCollateralFactor >=
            assetConfig.liquidateCollateralFactor
        ) revert BorrowCFTooLarge();
        if (assetConfig.liquidateCollateralFactor > MAX_COLLATERAL_FACTOR)
            revert LiquidateCFTooLarge();

        unchecked {
            // Keep 4 decimals for each factor
            uint64 descale = FACTOR_SCALE / 1e4;
            uint16 borrowCollateralFactor = uint16(
                assetConfig.borrowCollateralFactor / descale
            );
            uint16 liquidateCollateralFactor = uint16(
                assetConfig.liquidateCollateralFactor / descale
            );
            uint16 liquidationFactor = uint16(
                assetConfig.liquidationFactor / descale
            );

            // Be nice and check descaled values are still within range
            if (borrowCollateralFactor >= liquidateCollateralFactor)
                revert BorrowCFTooLarge();

            // Keep whole units of asset for supply cap
            uint64 supplyCap = uint64(
                assetConfig.supplyCap / (10 ** decimals_)
            );

            uint256 word_a = ((uint160(asset) << 0) |
                (uint256(borrowCollateralFactor) << 160) |
                (uint256(liquidateCollateralFactor) << 176) |
                (uint256(liquidationFactor) << 192));
            uint256 word_b = ((uint160(priceFeed) << 0) |
                (uint256(decimals_) << 160) |
                (uint256(supplyCap) << 168));

            return (word_a, word_b);
        }
    }

    /**
     * @notice Get the i-th asset info, according to the order they were passed in originally
     * @param i The index of the asset info to get
     * @return The asset info object
     */
    function getAssetInfo(
        uint8 i
    ) public view override returns (AssetInfo memory) {
        if (i >= numAssets) revert BadAsset();

        uint256 word_a;
        uint256 word_b;

        if (i == 0) {
            word_a = asset00_a;
            word_b = asset00_b;
        } else if (i == 1) {
            word_a = asset01_a;
            word_b = asset01_b;
        } else if (i == 2) {
            word_a = asset02_a;
            word_b = asset02_b;
        } else if (i == 3) {
            word_a = asset03_a;
            word_b = asset03_b;
        } else if (i == 4) {
            word_a = asset04_a;
            word_b = asset04_b;
        } else if (i == 5) {
            word_a = asset05_a;
            word_b = asset05_b;
        } else if (i == 6) {
            word_a = asset06_a;
            word_b = asset06_b;
        } else if (i == 7) {
            word_a = asset07_a;
            word_b = asset07_b;
        } else if (i == 8) {
            word_a = asset08_a;
            word_b = asset08_b;
        } else if (i == 9) {
            word_a = asset09_a;
            word_b = asset09_b;
        } else if (i == 10) {
            word_a = asset10_a;
            word_b = asset10_b;
        } else if (i == 11) {
            word_a = asset11_a;
            word_b = asset11_b;
        } else {
            revert Absurd();
        }

        address asset = address(uint160(word_a & type(uint160).max));
        uint64 rescale = FACTOR_SCALE / 1e4;
        uint64 borrowCollateralFactor = uint64(
            ((word_a >> 160) & type(uint16).max) * rescale
        );
        uint64 liquidateCollateralFactor = uint64(
            ((word_a >> 176) & type(uint16).max) * rescale
        );
        uint64 liquidationFactor = uint64(
            ((word_a >> 192) & type(uint16).max) * rescale
        );

        address priceFeed = address(uint160(word_b & type(uint160).max));
        uint8 decimals_ = uint8(((word_b >> 160) & type(uint8).max));
        uint64 scale = uint64(10 ** decimals_);
        uint128 supplyCap = uint128(
            ((word_b >> 168) & type(uint64).max) * scale
        );

        return
            AssetInfo({
                offset: i,
                asset: asset,
                priceFeed: priceFeed,
                scale: scale,
                borrowCollateralFactor: borrowCollateralFactor,
                liquidateCollateralFactor: liquidateCollateralFactor,
                liquidationFactor: liquidationFactor,
                supplyCap: supplyCap
            });
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
     * @dev 计算累积利息指数（供应和借贷）
     * @dev 根据经过的时间和当前利率，计算新的指数值
     * @param timeElapsed 自上次累积以来经过的时间（秒）
     * @return 新的供应指数和借贷指数
     **/
    function accruedInterestIndices(
        uint timeElapsed
    ) internal view returns (uint64, uint64) {
        // 读取当前的供应和借贷指数
        uint64 baseSupplyIndex_ = baseSupplyIndex;
        uint64 baseBorrowIndex_ = baseBorrowIndex;

        if (timeElapsed > 0) {
            // 步骤 1: 计算当前的资金利用率（借贷量 / 供应量）
            uint utilization = getUtilization();

            // 步骤 2: 根据利用率计算供应利率和借贷利率（每秒）
            uint supplyRate = getSupplyRate(utilization);
            uint borrowRate = getBorrowRate(utilization);

            // 步骤 3: 计算累积的利息并更新指数
            // 公式：新指数 = 旧指数 × (1 + 利率 × 时间)
            // 这里简化为：新指数 = 旧指数 + 旧指数 × 利率 × 时间
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
     * @dev 累积利息和奖励（全局操作）
     * @dev 更新全局的供应/借贷指数和奖励追踪指数
     **/
    function accrueInternal() internal {
        // 步骤 1: 获取当前时间并计算经过的时间
        uint40 now_ = getNowInternal();
        uint timeElapsed = uint256(now_ - lastAccrualTime);

        if (timeElapsed > 0) {
            // 步骤 2: 更新供应和借贷的利息指数
            (baseSupplyIndex, baseBorrowIndex) = accruedInterestIndices(
                timeElapsed
            );

            // 步骤 3: 更新供应奖励追踪指数
            // 只有当总供应量达到最小要求时才累积奖励
            // 公式：奖励增量 = (奖励速度 × 时间) / 总供应量
            if (totalSupplyBase >= baseMinForRewards) {
                trackingSupplyIndex += safe64(
                    divBaseWei(
                        baseTrackingSupplySpeed * timeElapsed,
                        totalSupplyBase
                    )
                );
            }

            // 步骤 4: 更新借贷奖励追踪指数
            // 只有当总借贷量达到最小要求时才累积奖励
            if (totalBorrowBase >= baseMinForRewards) {
                trackingBorrowIndex += safe64(
                    divBaseWei(
                        baseTrackingBorrowSpeed * timeElapsed,
                        totalBorrowBase
                    )
                );
            }

            // 步骤 5: 更新最后累积时间戳
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
     * @dev 使用 borrowCollateralFactor（较低阈值）检查
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

        // 步骤 3: 初始化流动性（负值，表示债务的美元价值）
        uint16 assetsIn = userBasic[account].assetsIn;
        int liquidity = signedMulPrice(
            presentValue(principal), // 负值，当前债务金额
            getPrice(baseTokenPriceFeed), // 基础资产价格
            uint64(baseScale) // 缩放因子
        ); // liquidity < 0，表示需要抵押品来覆盖的债务价值

        // 步骤 4: 遍历用户的所有抵押资产，累加抵押价值
        for (uint8 i = 0; i < numAssets; ) {
            if (isInAsset(assetsIn, i)) {
                // 提前退出：如果流动性已经 ≥ 0，说明抵押充足
                if (liquidity >= 0) {
                    return true;
                }

                // 4.1: 获取该抵押资产的配置
                AssetInfo memory asset = getAssetInfo(i);

                // 4.2: 计算抵押品的美元价值
                uint newAmount = mulPrice(
                    userCollateral[account][asset.asset].balance, // 抵押品数量
                    getPrice(asset.priceFeed), // 抵押品价格
                    asset.scale // 缩放因子
                );

                // 4.3: 应用借贷抵押率，累加到流动性
                // borrowCollateralFactor 通常为 0.8-0.9（80%-90%）
                // 例如：$100 的 ETH × 0.8 = $80 的借贷能力
                liquidity += signed256(
                    mulFactor(newAmount, asset.borrowCollateralFactor)
                );
            }
            unchecked {
                i++;
            }
        }

        // 步骤 5: 返回流动性是否 ≥ 0
        // liquidity ≥ 0 表示抵押品价值 ≥ 债务价值，可以借贷
        return liquidity >= 0;
    }

    /**
     * @notice 检查账户是否可被清算
     * @dev 使用 liquidateCollateralFactor（较高阈值）检查
     * @dev liquidateCollateralFactor > borrowCollateralFactor，提供安全缓冲
     *
     * 清算判断公式：
     * ===============================================
     *
     * 1. 债务价值计算：
     *    debtValue = |presentValue(principal)| × basePrice / baseScale
     *    其中：
     *    - presentValue(principal) < 0 （本金为负数表示债务）
     *    - basePrice：基础资产价格（例如 USDC = 1.0）
     *    - baseScale：基础资产精度缩放（10^baseDecimals）
     *
     * 2. 抵押品价值计算（应用清算因子）：
     *    collateralValue = Σ (collateralBalance_i × collateralPrice_i / collateralScale_i × liquidateCollateralFactor_i)
     *    对所有抵押品 i：
     *    - collateralBalance_i：用户抵押的第 i 种资产数量
     *    - collateralPrice_i：第 i 种资产的价格（如 ETH = $3000）
     *    - collateralScale_i：第 i 种资产的精度缩放（10^decimals）
     *    - liquidateCollateralFactor_i：清算抵押率（如 0.85 = 85%）
     *
     * 3. 流动性计算（Liquidity）：
     *    liquidity = -debtValue + collateralValue
     *              = -|principal| × basePrice / baseScale
     *                + Σ (balance_i × price_i / scale_i × liquidateFactor_i)
     *
     * 4. 清算条件：
     *    可清算 ⟺ liquidity < 0
     *    即：collateralValue < debtValue
     *    即：实际抵押价值 < 债务价值
     *
     * 清算阈值示例：
     * ===============================================
     * 假设：
     * - 借款：$1000 USDC（债务）
     * - 抵押：1 ETH，价格 $3000
     * - liquidateCollateralFactor = 0.85（85%）
     *
     * 计算：
     * - debtValue = $1000
     * - collateralValue = 1 ETH × $3000 × 0.85 = $2550
     * - liquidity = -$1000 + $2550 = $1550 > 0
     * - 结果：不可清算（抵押充足）
     *
     * 如果 ETH 价格跌至 $1200：
     * - collateralValue = 1 ETH × $1200 × 0.85 = $1020
     * - liquidity = -$1000 + $1020 = $20 > 0
     * - 结果：仍不可清算（刚好安全）
     *
     * 如果 ETH 价格跌至 $1100：
     * - collateralValue = 1 ETH × $1100 × 0.85 = $935
     * - liquidity = -$1000 + $935 = -$65 < 0
     * - 结果：可清算（抵押不足）
     *
     * 清算阈值价格：
     * - liquidationPrice = debtValue / (collateralAmount × liquidateFactor)
     *                    = $1000 / (1 ETH × 0.85)
     *                    = $1176.47
     *
     * 与借贷能力的关系：
     * ===============================================
     * - borrowCollateralFactor = 0.80 (80%) → 借贷能力
     * - liquidateCollateralFactor = 0.85 (85%) → 清算阈值
     * - 差距 = 5% → 安全缓冲区
     *
     * 这意味着：
     * 1. 用户最多可借：$3000 × 0.80 = $2400
     * 2. 清算触发于：$3000 × 0.85 = $2550 债务水平
     * 3. 价格下跌到 $2550/$0.85 = $3000 时触发清算
     *
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

        // 步骤 3: 初始化流动性（负值，表示债务的美元价值）
        // 公式：liquidity = presentValue(principal) × basePrice / baseScale
        // 由于 principal < 0，所以 liquidity < 0
        uint16 assetsIn = userBasic[account].assetsIn;
        int liquidity = signedMulPrice(
            presentValue(principal), // 负值，当前债务金额（已考虑利息累积）
            getPrice(baseTokenPriceFeed), // 基础资产价格（如 USDC = 1.0）
            uint64(baseScale) // 缩放因子（如 10^6 for USDC）
        ); // liquidity < 0，表示需要抵押品来覆盖的债务价值（美元）

        // 步骤 4: 遍历用户的所有抵押资产，累加抵押价值
        // 公式：liquidity += Σ (balance_i × price_i / scale_i × liquidateFactor_i)
        for (uint8 i = 0; i < numAssets; ) {
            if (isInAsset(assetsIn, i)) {
                // 提前退出：如果流动性已经 ≥ 0，说明抵押充足，不能清算
                if (liquidity >= 0) {
                    return false;
                }

                // 4.1: 获取该抵押资产的配置
                AssetInfo memory asset = getAssetInfo(i);

                // 4.2: 计算抵押品的美元价值
                // 公式：collateralValue = balance × price / scale
                uint newAmount = mulPrice(
                    userCollateral[account][asset.asset].balance, // 抵押品数量（原始单位）
                    getPrice(asset.priceFeed), // 抵押品价格（美元，如 ETH = $3000）
                    asset.scale // 缩放因子（10^decimals）
                ); // 结果：抵押品的美元价值（无因子调整）

                // 4.3: 应用清算抵押率，累加到流动性
                // 公式：adjustedValue = collateralValue × liquidateCollateralFactor
                // liquidateCollateralFactor 通常为 0.85-0.95（85%-95%）
                // 比 borrowCollateralFactor 高 5-10%，提供安全缓冲区
                // 例如：
                //   - $100 的 ETH × 0.85 = $85 的清算阈值
                //   - 当债务达到 $85 时触发清算
                //   - 而借贷能力只有 $80（borrowCollateralFactor = 0.80）
                liquidity += signed256(
                    mulFactor(newAmount, asset.liquidateCollateralFactor)
                );
            }
            unchecked {
                i++;
            }
        }

        // 步骤 5: 返回流动性是否 < 0
        // liquidity < 0 表示 adjustedCollateralValue < debtValue，可以清算
        // 注意：这里与 isBorrowCollateralized 的返回值相反
        //   - isBorrowCollateralized: liquidity >= 0 → true (可借贷)
        //   - isLiquidatable: liquidity < 0 → true (可清算)
        return liquidity < 0;
    }

    /**
     * @dev 将本金变化分解为还款和供应两部分
     * @dev 用于供应或转账操作，当本金增加时调用
     * @dev 返回 (还款金额, 供应金额)
     * @param oldPrincipal 旧本金（可正可负）
     * @param newPrincipal 新本金（可正可负）
     * @return repayAmount 还款金额（如果从负变正或负变更少负）
     * @return supplyAmount 供应金额（如果从正变更正或负变正）
     */
    function repayAndSupplyAmount(
        int104 oldPrincipal,
        int104 newPrincipal
    ) internal pure returns (uint104, uint104) {
        // 情况 0: 本金减少，不是还款或供应操作
        if (newPrincipal < oldPrincipal) return (0, 0);

        // 情况 1: 都是负数（借贷状态）
        // 例如：-100 → -50，还款 50
        if (newPrincipal <= 0) {
            return (uint104(newPrincipal - oldPrincipal), 0); // newPrincipal - oldPrincipal > 0
        }
        // 情况 2: 都是正数（供应状态）
        // 例如：50 → 100，供应 50
        else if (oldPrincipal >= 0) {
            return (0, uint104(newPrincipal - oldPrincipal));
        }
        // 情况 3: 从负变正（借贷 → 供应）
        // 例如：-50 → 30，先还款 50，再供应 30
        else {
            return (uint104(-oldPrincipal), uint104(newPrincipal));
        }
    }

    /**
     * @dev 将本金变化分解为提款和借贷两部分
     * @dev 用于提款或转账操作，当本金减少时调用
     * @dev 返回 (提款金额, 借贷金额)
     * @param oldPrincipal 旧本金（可正可负）
     * @param newPrincipal 新本金（可正可负）
     * @return withdrawAmount 提款金额（如果从正变更少正或正变负）
     * @return borrowAmount 借贷金额（如果从正变负或负变更负）
     */
    function withdrawAndBorrowAmount(
        int104 oldPrincipal,
        int104 newPrincipal
    ) internal pure returns (uint104, uint104) {
        // 情况 0: 本金增加，不是提款或借贷操作
        if (newPrincipal > oldPrincipal) return (0, 0);

        // 情况 1: 都是正数（供应状态）
        // 例如：100 → 50，提款 50
        if (newPrincipal >= 0) {
            return (uint104(oldPrincipal - newPrincipal), 0);
        }
        // 情况 2: 都是负数（借贷状态）
        // 例如：-50 → -100，借贷 50
        else if (oldPrincipal <= 0) {
            return (0, uint104(oldPrincipal - newPrincipal)); // oldPrincipal - newPrincipal > 0
        }
        // 情况 3: 从正变负（供应 → 借贷）
        // 例如：30 → -50，先提款 30，再借贷 50
        else {
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
     * @dev 乘以因子（百分比计算）
     * @dev 公式：结果 = n × factor / FACTOR_SCALE
     * @dev 例如：100 × 0.8e18 / 1e18 = 80（应用 80% 的因子）
     * @param n 被乘数
     * @param factor 因子（以 FACTOR_SCALE 为单位，1e18 = 100%）
     * @return 应用因子后的结果
     */
    function mulFactor(uint n, uint factor) internal pure returns (uint) {
        return (n * factor) / FACTOR_SCALE;
    }

    /**
     * @dev 按基础资产数量除法（用于奖励计算）
     * @dev 公式：结果 = n × baseScale / baseWei
     * @dev 将奖励速度（每秒）转换为每单位本金的奖励
     * @param n 分子（通常是奖励速度 × 时间）
     * @param baseWei 分母（通常是总供应或总借贷量）
     * @return 每单位的奖励增量
     */
    function divBaseWei(uint n, uint baseWei) internal view returns (uint) {
        return (n * baseScale) / baseWei;
    }

    /**
     * @dev 将资产数量乘以价格，转换为美元价值
     * @dev 公式：美元价值 = 数量 × 价格 / 资产缩放因子
     * @dev 例如：10 ETH × 2000 USD/ETH / 1e18 = 20000 USD（以 PRICE_SCALE 为单位）
     * @param n 资产数量（原始单位）
     * @param price 资产价格（以 PRICE_SCALE 为单位）
     * @param fromScale 资产的缩放因子（10^decimals）
     * @return 美元价值（以 PRICE_SCALE 为单位）
     */
    function mulPrice(
        uint n,
        uint price,
        uint64 fromScale
    ) internal pure returns (uint) {
        return (n * price) / fromScale;
    }

    /**
     * @dev 将有符号资产数量乘以价格，转换为美元价值
     * @dev 与 mulPrice 相同，但支持负数（用于债务计算）
     * @param n 有符号资产数量（负数表示债务）
     * @param price 资产价格（以 PRICE_SCALE 为单位）
     * @param fromScale 资产的缩放因子（10^decimals）
     * @return 有符号美元价值（负数表示债务）
     */
    function signedMulPrice(
        int n,
        uint price,
        uint64 fromScale
    ) internal pure returns (int) {
        return (n * signed256(price)) / int256(uint256(fromScale));
    }

    /**
     * @dev 将美元价值除以价格，转换为资产数量
     * @dev 公式：数量 = 美元价值 × 资产缩放因子 / 价格
     * @dev 这是 mulPrice 的逆运算
     * @param n 美元价值（以 PRICE_SCALE 为单位）
     * @param price 资产价格（以 PRICE_SCALE 为单位）
     * @param toScale 资产的缩放因子（10^decimals）
     * @return 资产数量（原始单位）
     */
    function divPrice(
        uint n,
        uint price,
        uint64 toScale
    ) internal pure returns (uint) {
        return (n * toScale) / price;
    }

    /**
     * @dev 检查用户是否持有某个抵押资产（通过位标志）
     * @dev 使用位运算快速检查，避免遍历所有资产
     * @dev 例如：assetsIn = 0b0000000000000101，assetOffset = 0
     * @dev      结果：(0b0101 & 0b0001) != 0 = true（持有资产 0）
     * @param assetsIn 用户的资产位标志（uint16，最多 16 个资产）
     * @param assetOffset 资产的索引位置（0-15）
     * @return 如果用户持有该资产返回 true，否则返回 false
     */
    function isInAsset(
        uint16 assetsIn,
        uint8 assetOffset
    ) internal pure returns (bool) {
        return (assetsIn & (uint16(1) << assetOffset) != 0);
    }

    /**
     * @dev 更新用户的 assetsIn 位标志
     * @dev 当用户首次持有某资产时设置对应位，余额清零时清除对应位
     * @dev 这个标志用于：
     * @dev 1. 清算时快速遍历用户持有的抵押品
     * @dev 2. 抵押检查时只计算相关资产
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
            // 例如：资产 2，offset = 2，设置第 2 位
            // assetsIn |= 0b0000000000000100
            userBasic[account].assetsIn |= (uint16(1) << assetInfo.offset);
        } else if (initialUserBalance != 0 && finalUserBalance == 0) {
            // 从非 0 变为 0：清除对应位
            // 例如：资产 2，offset = 2，清除第 2 位
            // assetsIn &= ~0b0000000000000100 = assetsIn & 0b1111111111111011
            userBasic[account].assetsIn &= ~(uint16(1) << assetInfo.offset);
        }
        // 其他情况（非 0 → 非 0，或 0 → 0）不需要更新
    }

    /**
     * @dev 更新用户本金并计算累积奖励
     * @dev 这个函数在每次余额变动时调用，确保奖励准确计算
     * @param account 用户地址
     * @param basic 用户的基础数据（内存副本）
     * @param principalNew 新的本金值
     */
    function updateBasePrincipal(
        address account,
        UserBasic memory basic,
        int104 principalNew
    ) internal {
        // 步骤 1: 保存旧本金并更新为新本金
        int104 principal = basic.principal;
        basic.principal = principalNew;

        // 步骤 2: 计算自上次更新以来累积的奖励
        if (principal >= 0) {
            // 如果旧本金 ≥ 0（供应状态），使用供应奖励索引
            uint indexDelta = uint256(
                trackingSupplyIndex - basic.baseTrackingIndex
            );
            // 奖励增量 = 本金 × 索引增量 / 缩放因子
            // 除以 accrualDescaleFactor 是为了保持 6 位小数精度
            basic.baseTrackingAccrued += safe64(
                (uint104(principal) * indexDelta) /
                    trackingIndexScale /
                    accrualDescaleFactor
            );
        } else {
            // 如果旧本金 < 0（借贷状态），使用借贷奖励索引
            uint indexDelta = uint256(
                trackingBorrowIndex - basic.baseTrackingIndex
            );
            // 使用绝对值计算（-principal 转为正数）
            basic.baseTrackingAccrued += safe64(
                (uint104(-principal) * indexDelta) /
                    trackingIndexScale /
                    accrualDescaleFactor
            );
        }

        // 步骤 3: 更新用户的奖励追踪索引快照
        // 根据新本金的状态选择对应的索引
        if (principalNew >= 0) {
            // 新状态为供应，使用供应索引
            basic.baseTrackingIndex = trackingSupplyIndex;
        } else {
            // 新状态为借贷，使用借贷索引
            basic.baseTrackingIndex = trackingBorrowIndex;
        }

        // 步骤 4: 将更新后的数据写回存储
        userBasic[account] = basic;
    }

    /**
     * @dev 安全转入 ERC20 代币，返回实际转入金额
     * @dev 兼容非标准 ERC20 代币（如 USDT 不返回 bool）
     * @dev 通过余额差计算实际转入量，处理手续费代币（如部分转账会扣费）
     * @param asset 代币地址
     * @param from 转出方地址
     * @param amount 期望转入数量
     * @return 实际转入数量（可能与 amount 不同）
     */
    function doTransferIn(
        address asset,
        address from,
        uint amount
    ) internal returns (uint) {
        // 步骤 1: 记录转账前的余额
        uint256 preTransferBalance = IERC20NonStandard(asset).balanceOf(
            address(this)
        );

        // 步骤 2: 执行 transferFrom 调用
        IERC20NonStandard(asset).transferFrom(from, address(this), amount);

        // 步骤 3: 检查转账是否成功（使用汇编处理非标准代币）
        bool success;
        assembly ("memory-safe") {
            switch returndatasize()
            case 0 {
                // 没有返回数据（非标准 ERC-20，如 USDT）
                // 假设成功（如果失败会 revert）
                success := not(0) // true
            }
            case 32 {
                // 返回 32 字节（标准 ERC-20，返回 bool）
                returndatacopy(0, 0, 32)
                success := mload(0) // 读取返回的 bool 值
            }
            default {
                // 返回其他大小的数据（极度非标准）
                // 直接 revert
                revert(0, 0)
            }
        }

        // 步骤 4: 如果 success = false，回滚交易
        if (!success) revert TransferInFailed();

        // 步骤 5: 通过余额差计算实际转入量
        // 这样可以处理带手续费的代币（实际到账 < amount）
        return
            IERC20NonStandard(asset).balanceOf(address(this)) -
            preTransferBalance;
    }

    /**
     * @dev 安全转出 ERC20 代币
     * @dev 兼容非标准 ERC20 代币（如 USDT 不返回 bool）
     * @dev 使用汇编检查返回值，确保转账成功
     * @param asset 代币地址
     * @param to 接收方地址
     * @param amount 转出数量
     */
    function doTransferOut(address asset, address to, uint amount) internal {
        // 步骤 1: 执行 transfer 调用
        IERC20NonStandard(asset).transfer(to, amount);

        // 步骤 2: 检查转账是否成功（使用汇编处理非标准代币）
        bool success;
        assembly ("memory-safe") {
            switch returndatasize()
            case 0 {
                // 没有返回数据（非标准 ERC-20，如 USDT）
                // 假设成功（如果失败会 revert）
                success := not(0) // true
            }
            case 32 {
                // 返回 32 字节（标准 ERC-20，返回 bool）
                returndatacopy(0, 0, 32)
                success := mload(0) // 读取返回的 bool 值
            }
            default {
                // 返回其他大小的数据（极度非标准）
                // 直接 revert
                revert(0, 0)
            }
        }

        // 步骤 3: 如果 success = false，回滚交易
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
     * @dev 供应基础资产（内部函数）
     * @dev 支持两种场景：1) 增加供应余额  2) 偿还借贷债务
     * @param from 资产来源地址
     * @param dst 接收供应余额的目标地址
     * @param amount 供应数量
     */
    function supplyBase(address from, address dst, uint256 amount) internal {
        // 步骤 1: 转入代币，获取实际转入数量（处理手续费代币）
        amount = doTransferIn(baseToken, from, amount);

        // 步骤 2: 累积全局利息和奖励
        accrueInternal();

        // 步骤 3: 读取目标用户的当前本金
        UserBasic memory dstUser = userBasic[dst];
        int104 dstPrincipal = dstUser.principal;

        // 步骤 4: 计算新的余额和本金
        // 如果 dstPrincipal < 0（有借贷），供应会优先偿还债务
        int256 dstBalance = presentValue(dstPrincipal) + signed256(amount);
        int104 dstPrincipalNew = principalValue(dstBalance);

        // 步骤 5: 分解为还款和供应两部分
        // 例如：从 -50 变为 +30，则 repayAmount=50，supplyAmount=30
        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            dstPrincipal,
            dstPrincipalNew
        );

        // 步骤 6: 更新全局供应和借贷总量
        totalSupplyBase += supplyAmount; // 增加供应
        totalBorrowBase -= repayAmount; // 减少借贷

        // 步骤 7: 更新用户本金并计算奖励
        updateBasePrincipal(dst, dstUser, dstPrincipalNew);

        // 步骤 8: 触发事件
        emit Supply(from, dst, amount);

        // 步骤 9: 如果是净供应（非还款），触发 ERC20 Transfer 事件
        if (supplyAmount > 0) {
            emit Transfer(
                address(0),
                dst,
                presentValueSupply(baseSupplyIndex, supplyAmount)
            );
        }
    }

    /**
     * @dev 供应抵押资产（内部函数）
     * @dev 抵押品不计利息，仅用于借贷时的抵押担保
     * @param from 资产来源地址
     * @param dst 接收抵押品的目标地址
     * @param asset 抵押资产地址
     * @param amount 供应数量
     */
    function supplyCollateral(
        address from,
        address dst,
        address asset,
        uint128 amount
    ) internal {
        // 步骤 1: 转入抵押资产，获取实际转入数量
        amount = safe128(doTransferIn(asset, from, amount));

        // 步骤 2: 获取该资产的配置信息（价格、抵押率等）
        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);

        // 步骤 3: 更新该资产的全局总供应量
        TotalsCollateral memory totals = totalsCollateral[asset];
        totals.totalSupplyAsset += amount;

        // 步骤 4: 检查是否超过该资产的供应上限（风险控制）
        if (totals.totalSupplyAsset > assetInfo.supplyCap)
            revert SupplyCapExceeded();

        // 步骤 5: 计算用户的新抵押品余额
        uint128 dstCollateral = userCollateral[dst][asset].balance;
        uint128 dstCollateralNew = dstCollateral + amount;

        // 步骤 6: 更新存储
        totalsCollateral[asset] = totals;
        userCollateral[dst][asset].balance = dstCollateralNew;

        // 步骤 7: 更新用户的 assetsIn 位标志
        // 记录用户持有哪些抵押资产（用于清算时遍历）
        updateAssetsIn(dst, assetInfo, dstCollateral, dstCollateralNew);

        // 步骤 8: 触发事件
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
     * @dev 转账基础资产（内部函数）
     * @dev 支持从供应余额转出，或在余额不足时自动借贷
     * @param src 转出地址
     * @param dst 接收地址
     * @param amount 转账数量
     */
    function transferBase(address src, address dst, uint256 amount) internal {
        // 步骤 1: 累积全局利息和奖励
        accrueInternal();

        // 步骤 2: 读取双方用户的当前本金
        UserBasic memory srcUser = userBasic[src];
        UserBasic memory dstUser = userBasic[dst];

        int104 srcPrincipal = srcUser.principal;
        int104 dstPrincipal = dstUser.principal;

        // 步骤 3: 计算转账后的新余额
        // src 减少 amount（可能变负，即借贷）
        // dst 增加 amount（可能从负变正，即还款）
        int256 srcBalance = presentValue(srcPrincipal) - signed256(amount);
        int256 dstBalance = presentValue(dstPrincipal) + signed256(amount);
        int104 srcPrincipalNew = principalValue(srcBalance);
        int104 dstPrincipalNew = principalValue(dstBalance);

        // 步骤 4: 分解 src 的操作（提款或借贷）
        (
            uint104 withdrawAmount,
            uint104 borrowAmount
        ) = withdrawAndBorrowAmount(srcPrincipal, srcPrincipalNew);

        // 步骤 5: 分解 dst 的操作（还款或供应）
        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            dstPrincipal,
            dstPrincipalNew
        );

        // 步骤 6: 更新全局总量
        // 注意：使用 a + b - c 而非 a += b - c 以避免下溢错误
        totalSupplyBase = totalSupplyBase + supplyAmount - withdrawAmount;
        totalBorrowBase = totalBorrowBase + borrowAmount - repayAmount;

        // 步骤 7: 更新双方用户的本金和奖励
        updateBasePrincipal(src, srcUser, srcPrincipalNew);
        updateBasePrincipal(dst, dstUser, dstPrincipalNew);

        // 步骤 8: 如果 src 转账后变为借贷状态，检查抵押和最小借贷要求
        if (srcBalance < 0) {
            // 检查借贷金额是否达到最小值
            if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
            // 检查是否有足够抵押品
            if (!isBorrowCollateralized(src)) revert NotCollateralized();
        }

        // 步骤 9: 触发 ERC20 Transfer 事件
        // 如果 src 提款了，触发销毁事件
        if (withdrawAmount > 0) {
            emit Transfer(
                src,
                address(0),
                presentValueSupply(baseSupplyIndex, withdrawAmount)
            );
        }

        // 如果 dst 净供应了，触发铸造事件
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
     * @dev 提取基础资产（内部函数）
     * @dev 如果余额不足，会自动借贷以满足提款需求
     * @param src 提款账户
     * @param to 接收地址
     * @param amount 提款数量
     */
    function withdrawBase(address src, address to, uint256 amount) internal {
        // 步骤 1: 累积全局利息和奖励
        accrueInternal();

        // 步骤 2: 读取用户当前本金
        UserBasic memory srcUser = userBasic[src];
        int104 srcPrincipal = srcUser.principal;

        // 步骤 3: 计算提款后的新余额
        // 如果供应余额不足，余额会变负（即借贷）
        int256 srcBalance = presentValue(srcPrincipal) - signed256(amount);
        int104 srcPrincipalNew = principalValue(srcBalance);

        // 步骤 4: 分解为提款和借贷两部分
        // 例如：从 +30 变为 -20，则 withdrawAmount=30，borrowAmount=20
        (
            uint104 withdrawAmount,
            uint104 borrowAmount
        ) = withdrawAndBorrowAmount(srcPrincipal, srcPrincipalNew);

        // 步骤 5: 更新全局供应和借贷总量
        totalSupplyBase -= withdrawAmount; // 减少供应
        totalBorrowBase += borrowAmount; // 增加借贷

        // 步骤 6: 更新用户本金和奖励
        updateBasePrincipal(src, srcUser, srcPrincipalNew);

        // 步骤 7: 如果提款后变为借贷状态，检查抵押和最小借贷要求
        if (srcBalance < 0) {
            // 检查借贷金额是否达到最小值（防止灰尘账户）
            if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
            // 检查是否有足够抵押品支持借贷
            if (!isBorrowCollateralized(src)) revert NotCollateralized();
        }

        // 步骤 8: 转出代币到目标地址
        doTransferOut(baseToken, to, amount);

        // 步骤 9: 触发事件
        emit Withdraw(src, to, amount);

        // 步骤 10: 如果是净提款（非借贷），触发 ERC20 销毁事件
        if (withdrawAmount > 0) {
            emit Transfer(
                src,
                address(0),
                presentValueSupply(baseSupplyIndex, withdrawAmount)
            );
        }
    }

    /**
     * @dev 提取抵押资产（内部函数）
     * @dev 必须保证提取后仍有足够抵押品支持借贷
     * @param src 提款账户
     * @param to 接收地址
     * @param asset 抵押资产地址
     * @param amount 提款数量
     */
    function withdrawCollateral(
        address src,
        address to,
        address asset,
        uint128 amount
    ) internal {
        // 步骤 1: 计算提款后的新余额
        uint128 srcCollateral = userCollateral[src][asset].balance;
        uint128 srcCollateralNew = srcCollateral - amount;

        // 步骤 2: 更新全局和用户的抵押品余额
        totalsCollateral[asset].totalSupplyAsset -= amount;
        userCollateral[src][asset].balance = srcCollateralNew;

        // 步骤 3: 更新用户的 assetsIn 位标志
        // 如果余额变为 0，清除该资产的位标志
        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        updateAssetsIn(src, assetInfo, srcCollateral, srcCollateralNew);

        // 步骤 4: 检查提款后是否仍有足够抵押品
        // 注意：这里不累积利息，因为 BorrowCF < LiquidationCF 的安全边际可以覆盖小额变化
        if (!isBorrowCollateralized(src)) revert NotCollateralized();

        // 步骤 5: 转出抵押资产到目标地址
        doTransferOut(asset, to, amount);

        // 步骤 6: 触发事件
        emit WithdrawCollateral(src, to, asset, amount);
    }

    /**
     * @notice 清算水下账户（二阶段清算的第一阶段）
     * @dev ⚠️ 重要：这是 Comet 创新的二阶段清算机制的第一步
     *
     * 为什么 absorb 和 buyCollateral 是两个独立的接口？
     * ========================================
     *
     * 传统协议（Compound V2, Aave）：
     * - 一步完成：清算者支付债务 → 立即获得抵押品
     * - 需要大量资本（清算者必须持有债务代币）
     * - 门槛高，参与者少
     *
     * Comet 创新设计 - 二阶段清算：
     *
     * 【阶段 1: absorb（本函数）】
     * - 目的：快速清除风险账户
     * - 执行者：任何人（零资本要求！）
     * - 过程：协议没收抵押品，协议承担债务
     * - 奖励：清算者获得积分（延迟奖励）
     * - 优先级：高（紧急风控）
     *
     * 【阶段 2: buyCollateral（独立接口）】
     * - 目的：补充协议储备金
     * - 执行者：套利者、做市商、普通用户
     * - 过程：用户支付 USDC，获得折扣抵押品
     * - 奖励：折扣价格（即时收益）
     * - 优先级：低（慢慢恢复）
     *
     * 设计优势：
     * ✅ 降低清算门槛（不需要资金）
     * ✅ 提高响应速度（立即清算）
     * ✅ 提高系统安全（快速控制风险）
     * ✅ Gas 效率更高（批量清算）
     * ✅ 创造双市场（清算 + 套利）
     *
     * 例子：
     * 1. Bob 调用 absorb(bob, [alice])
     *    - Alice 的 10 ETH 被协议没收
     *    - Alice 的 $15,000 债务被协议承担
     *    - Bob 获得积分，但不需要支付任何 USDC
     *    - Bob 也不会获得任何 ETH
     *
     * 2. 之后，Carol 调用 buyCollateral
     *    - Carol 支付 $8,075 USDC
     *    - Carol 获得 5 ETH（折扣价 $1,615/ETH vs 市价 $1,700）
     *    - 协议储备金增加 $8,075
     *
     * @param absorber 清算执行者（会获得清算积分奖励）
     * @param accounts 要清算的账户列表（可批量）
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
     * @dev 清算账户（内部函数）- 全账户清算模式
     * @dev 将用户的抵押品和债务转移到协议，协议储备金承担坏账
     *
     * ⚠️ 重要：全账户清算机制
     * =====================================
     *
     * Comet 采用全账户清算（Whole Account Liquidation），而非单资产清算：
     *
     * 【清算判断】
     * 1. 基于所有抵押品的总价值 vs 总债务
     *    - 公式：总流动性 = Σ(抵押品价值 × 清算因子) - 债务价值
     *    - 触发条件：总流动性 < 0
     *    - 不区分单个资产是否"安全"
     *
     * 【清算执行】
     * 2. 没收所有抵押品（100%）
     *    - 遍历用户的所有抵押资产
     *    - 每个资产的余额全部清零
     *    - 不存在部分清算的概念
     *
     * 【示例场景】
     * 假设用户抵押了三种资产：
     *
     * 初始状态：
     * - ETH:  1个，价格 $3000，清算因子 0.85 → 调整价值 $2550
     * - WBTC: 0.1个，价格 $40000，清算因子 0.85 → 调整价值 $3400
     * - LINK: 100个，价格 $15，清算因子 0.75 → 调整价值 $1125
     * - 总调整价值：$7075
     * - 债务：$6000
     * - 总流动性：$7075 - $6000 = $1075 > 0 ✅ 安全
     *
     * 价格下跌后：
     * - ETH 跌至 $2500 → 调整价值 $2125
     * - WBTC 跌至 $35000 → 调整价值 $2975
     * - LINK 跌至 $10 → 调整价值 $750
     * - 总调整价值：$5850
     * - 债务：$6000
     * - 总流动性：$5850 - $6000 = -$150 < 0 ❌ 可清算
     *
     * 清算执行（本函数）：
     * ✅ 没收所有 ETH（1个，即使单独看抵押充足）
     * ✅ 没收所有 WBTC（0.1个，即使单独看抵押充足）
     * ✅ 没收所有 LINK（100个，主要风险来源但不单独清算）
     * ❌ 不能选择性清算部分资产
     *
     * 【与其他协议对比】
     * - Compound V2: 部分清算（最多 50%单次）
     * - Aave V2/V3: 部分清算（可配置）
     * - Comet V3:   全账户清算（100%）
     *
     * 【设计权衡】
     * 优点：
     * - Gas 效率极高（一次性完成）
     * - 协议风险极低（快速清除不良账户）
     * - 实现逻辑简单（代码清晰）
     *
     * 缺点：
     * - 用户体验较差（轻微超额也会失去所有抵押品）
     * - 需要更高的超额抵押率（资本效率较低）
     *
     * @param absorber 清算执行人（会获得清算积分奖励）
     * @param account 被清算的账户
     */
    function absorbInternal(address absorber, address account) internal {
        // 步骤 1: 检查账户是否满足清算条件（抵押率低于清算阈值）
        // 注意：isLiquidatable 函数检查的是总流动性，不是单个资产
        if (!isLiquidatable(account)) revert NotLiquidatable();

        // 步骤 2: 读取账户的当前状态
        UserBasic memory accountUser = userBasic[account];
        int104 oldPrincipal = accountUser.principal; // 必须为负（有债务）
        int256 oldBalance = presentValue(oldPrincipal); // 当前债务金额（负值）
        uint16 assetsIn = accountUser.assetsIn; // 记录用户持有哪些抵押资产（位标志）

        // 步骤 3: 获取基础资产价格，用于价值转换
        uint256 basePrice = getPrice(baseTokenPriceFeed);
        uint256 deltaValue = 0; // 累积抵押品的总价值

        // 步骤 4: 🔥 关键循环 - 遍历并没收用户的所有抵押品
        // 注意：这里会没收所有资产，不区分哪个资产导致的清算
        for (uint8 i = 0; i < numAssets; ) {
            if (isInAsset(assetsIn, i)) {
                AssetInfo memory assetInfo = getAssetInfo(i);
                address asset = assetInfo.asset;

                // 4.1: 🔥 没收该抵押资产的全部余额（100%）
                // 关键点：不管这个资产本身是否"安全"，都会被全部没收
                // 例如：即使 ETH 抵押充足，只是其他资产（如 LINK）不足导致总流动性为负，
                //       ETH 也会被 100% 没收，不存在"只没收 LINK"的选项
                uint128 seizeAmount = userCollateral[account][asset].balance;
                userCollateral[account][asset].balance = 0; // 余额清零！
                totalsCollateral[asset].totalSupplyAsset -= seizeAmount;

                // 4.2: 计算抵押品价值（应用清算惩罚因子）
                // liquidationFactor 通常为 0.93-0.97（93%-97%）
                // 剩余 3-7% = 清算激励 + 协议储备（惩罚用户）
                uint256 value = mulPrice(
                    seizeAmount,
                    getPrice(assetInfo.priceFeed),
                    assetInfo.scale
                );
                deltaValue += mulFactor(value, assetInfo.liquidationFactor); // 打折后的价值

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

        // 步骤 5: 将抵押品价值转换为基础资产数量
        uint256 deltaBalance = divPrice(
            deltaValue,
            basePrice,
            uint64(baseScale)
        );
        int256 newBalance = oldBalance + signed256(deltaBalance);

        // 步骤 6: 如果抵押品不足以覆盖债务，剩余坏账由协议储备金承担
        if (newBalance < 0) {
            newBalance = 0; // 将余额清零，协议吸收损失
        }

        // 步骤 7: 计算新本金并更新用户状态
        int104 newPrincipal = principalValue(newBalance);
        updateBasePrincipal(account, accountUser, newPrincipal);

        // 步骤 8: 🔥 清空用户的 assetsIn 标志（已没收所有抵押品）
        // 这个操作确认：用户不再持有任何抵押品
        // 对比其他协议：
        //   - Compound V2: 可能只清算部分，assetsIn 不会全部清零
        //   - Aave: 可能只清算部分，用户还保留部分抵押品
        //   - Comet: 全部清零，用户失去所有抵押品
        userBasic[account].assetsIn = 0;

        // 步骤 9: 分解为还款和供应两部分
        (uint104 repayAmount, uint104 supplyAmount) = repayAndSupplyAmount(
            oldPrincipal,
            newPrincipal
        );

        // 步骤 10: 更新全局总量
        // 协议通过增加供应和减少借贷来吸收坏账
        // 实际由储备金支付的金额 = newBalance - oldBalance
        totalSupplyBase += supplyAmount;
        totalBorrowBase -= repayAmount;

        // 步骤 11: 触发债务吸收事件
        uint256 basePaidOut = unsigned256(newBalance - oldBalance);
        uint256 valueOfBasePaidOut = mulPrice(
            basePaidOut,
            basePrice,
            uint64(baseScale)
        );
        emit AbsorbDebt(absorber, account, basePaidOut, valueOfBasePaidOut);

        // 步骤 12: 如果清算后账户有余额（抵押品超额），触发铸造事件
        if (newPrincipal > 0) {
            emit Transfer(
                address(0),
                account,
                presentValueSupply(baseSupplyIndex, unsigned104(newPrincipal))
            );
        }
    }

    /**
     * @notice 从协议购买折扣抵押品（二阶段清算机制的第二阶段）
     * @dev 💡 这是 absorb 的补充，不是清算的替代
     *
     * 为什么需要独立的购买接口？
     * ================================================================
     *
     * 与 absorb 的关系：
     *
     * absorb（阶段 1）：
     * - 目标：快速清算不良账户
     * - 参与者：清算机器人（零资本）
     * - 激励：积分奖励
     * - 结果：协议承担债务，持有抵押品
     *
     * buyCollateral（阶段 2，本函数）：
     * - 目标：恢复协议储备金
     * - 参与者：套利者、做市商、普通用户
     * - 激励：折扣价格
     * - 结果：协议收回基础资产，释放抵押品
     *
     * 为什么分离？
     * ================================================================
     *
     * 1. 时间解耦
     *    - 清算：紧急（需要立即执行）
     *    - 购买：从容（可以慢慢卖出）
     *    - 好处：不会因为购买者不足而延迟清算
     *
     * 2. 资金解耦
     *    - 清算：零资本（任何人参与）
     *    - 购买：需要资金（套利者参与）
     *    - 好处：扩大清算参与者范围
     *
     * 3. 风险解耦
     *    - 清算：协议承担风险（短期）
     *    - 购买：购买者承担风险（价格波动）
     *    - 好处：协议快速控制系统性风险
     *
     * 4. 激励解耦
     *    - 清算：积分奖励（未来分配）
     *    - 购买：即时折扣（立即收益）
     *    - 好处：双重市场，双重激励
     *
     * 工作原理：
     * ================================================================
     *
     * 触发条件：
     * - 协议储备金 < 目标储备金
     * - 通常在 absorb 之后触发
     *
     * 折扣计算：
     * - 折扣 = storeFrontPriceFactor × (1 - liquidationFactor)
     * - 例如：0.9 × (1 - 0.95) = 0.045 = 4.5%
     * - 购买价 = 市场价 × (1 - 4.5%) = 95.5% 市场价
     *
     * 套利机会：
     * - 假设 ETH 市场价 $2000
     * - 购买价：$2000 × 0.955 = $1910
     * - 套利空间：$90/ETH（4.5%）
     *
     * 限制条件：
     * ✅ 只在储备金不足时开放（保护协议）
     * ✅ 滑点保护（保护购买者）
     * ✅ 检查协议抵押品储备（防止超卖）
     *
     * 实际案例：
     * ================================================================
     *
     * 场景：absorb 后，协议持有 10 ETH，储备金不足 $10,000
     *
     * Carol 购买：
     * ```solidity
     * comet.buyCollateral(
     *     ETH,                 // 要买的资产
     *     5 ether,             // 最少买 5 ETH（滑点保护）
     *     8075 * 1e6,          // 支付 $8,075 USDC
     *     carol                // 接收地址
     * );
     * ```
     *
     * 结果：
     * - Carol 支付：$8,075 USDC
     * - Carol 获得：5 ETH（市场价 $8,500）
     * - Carol 利润：$425（5%）
     * - 协议储备金：+$8,075（恢复中）
     * - 协议剩余：5 ETH（继续出售）
     *
     * 对比传统协议：
     * ================================================================
     *
     * 传统协议（一步清算）：
     * - 清算者立即获得所有抵押品
     * - 协议无法控制抵押品分配
     * - 可能被大户垄断
     *
     * Comet（二步清算）：
     * - 协议先获得抵押品
     * - 通过市场机制慢慢出售
     * - 任何人都有机会购买
     * - 价格发现更公平
     *
     * 注意事项：
     * ================================================================
     *
     * ⚠️ 不能直接清算（必须先 absorb）
     * ⚠️ 储备金充足时无法购买（NotForSale）
     * ⚠️ 需要自己计算折扣（调用 quoteCollateral）
     * ⚠️ 价格可能波动（使用 minAmount 保护）
     *
     * @param asset 要购买的抵押资产
     * @param minAmount 最小接收数量（滑点保护）
     * @param baseAmount 支付的基础资产数量
     * @param recipient 接收抵押品的地址
     */
    function buyCollateral(
        address asset,
        uint minAmount,
        uint baseAmount,
        address recipient
    ) external override nonReentrant {
        // 步骤 1: 检查购买功能是否被暂停
        if (isBuyPaused()) revert Paused();

        // 步骤 2: 检查协议储备金状态
        // 只有当储备金低于目标值时才允许购买（激励用户补充储备金）
        int reserves = getReserves();
        if (reserves >= 0 && uint(reserves) >= targetReserves)
            revert NotForSale();

        // 步骤 3: 转入基础资产
        // 注意：重入攻击可能跳过上面的储备金检查
        baseAmount = doTransferIn(baseToken, msg.sender, baseAmount);

        // 步骤 4: 计算可购买的抵押品数量（应用折扣）
        uint collateralAmount = quoteCollateral(asset, baseAmount);

        // 步骤 5: 检查滑点（实际获得的数量是否 ≥ 最小要求）
        if (collateralAmount < minAmount) revert TooMuchSlippage();

        // 步骤 6: 检查协议是否有足够的抵押品储备
        if (collateralAmount > getCollateralReserves(asset))
            revert InsufficientReserves();

        // 步骤 7: 转出抵押品给接收者
        // 注意：某些代币的 pre-transfer hook 可能导致重入
        // 不应该列出允许重入的资产，否则可能购买过多抵押品
        doTransferOut(asset, recipient, safe128(collateralAmount));

        // 步骤 8: 触发事件
        emit BuyCollateral(msg.sender, asset, baseAmount, collateralAmount);
    }

    /**
     * @notice 计算购买抵押品的报价（用基础资产换抵押资产）
     * @dev 应用折扣，激励用户补充协议储备金
     * @param asset 要购买的抵押资产
     * @param baseAmount 支付的基础资产数量
     * @return 可获得的抵押资产数量
     */
    function quoteCollateral(
        address asset,
        uint baseAmount
    ) public view override returns (uint) {
        // 步骤 1: 获取抵押资产的配置和价格
        AssetInfo memory assetInfo = getAssetInfoByAddress(asset);
        uint256 assetPrice = getPrice(assetInfo.priceFeed);

        // 步骤 2: 计算折扣因子
        // 折扣公式：discount = storeFrontPriceFactor × (1 - liquidationFactor)
        // 例如：storeFrontPriceFactor=0.9，liquidationFactor=0.95
        //       discount = 0.9 × (1 - 0.95) = 0.9 × 0.05 = 0.045 = 4.5%
        uint256 discountFactor = mulFactor(
            storeFrontPriceFactor,
            FACTOR_SCALE - assetInfo.liquidationFactor
        );

        // 步骤 3: 计算折扣后的抵押品价格
        // 折扣后价格 = 原价 × (1 - 折扣因子)
        uint256 assetPriceDiscounted = mulFactor(
            assetPrice,
            FACTOR_SCALE - discountFactor
        );

        // 步骤 4: 获取基础资产价格
        uint256 basePrice = getPrice(baseTokenPriceFeed);

        // 步骤 5: 计算可获得的抵押资产数量
        // 公式推导：
        // 1. 基础资产的美元价值 = basePrice × baseAmount / baseScale
        // 2. 可购买的抵押资产数量 = 美元价值 / 折扣后价格
        // 3. 转换为抵押资产单位 = 数量 × assetScale
        // 最终：collateralAmount = basePrice × baseAmount × assetScale / (assetPriceDiscounted × baseScale)
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
