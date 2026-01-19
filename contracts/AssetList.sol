// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./IPriceFeed.sol";
import "./IERC20NonStandard.sol";
import "./CometMainInterface.sol";
import "./CometCore.sol";

/**
 * @title Compound 资产列表合约
 * @notice 用于存储和管理扩展的抵押资产列表（最多 24 个资产）
 * @dev 使用紧凑的打包格式将资产信息存储在不可变变量中
 * @dev 每个资产占用 2 个 uint256 变量（word_a 和 word_b）
 * @dev 这个合约被 CometWithExtendedAssetList 使用，支持比标准 Comet（15 个）更多的资产
 * @author Compound
 */
contract AssetList {
    /// @dev 价格预言机要求的小数位数（8 位）
    uint8 internal constant PRICE_FEED_DECIMALS = 8;

    /// @dev 因子的缩放单位（1e18 = 100%）
    uint64 internal constant FACTOR_SCALE = 1e18;

    /// @dev 抵押因子的最大值（1.0 = 100%）
    uint64 internal constant MAX_COLLATERAL_FACTOR = FACTOR_SCALE;

    // ============ 资产存储（紧凑打包格式）============
    // 每个资产使用 2 个 uint256 变量存储：
    // - asset{XX}_a: 存储资产地址 + 借贷抵押率 + 清算阈值 + 清算惩罚
    // - asset{XX}_b: 存储价格预言机地址 + 小数位数 + 供应上限
    // 使用不可变变量以节省 gas（部署后不可更改）

    /// @dev 资产 0 的打包数据（第一部分）
    uint256 internal immutable asset00_a;
    /// @dev 资产 0 的打包数据（第二部分）
    uint256 internal immutable asset00_b;
    /// @dev 资产 1 的打包数据（第一部分）
    uint256 internal immutable asset01_a;
    /// @dev 资产 1 的打包数据（第二部分）
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
    uint256 internal immutable asset12_a;
    uint256 internal immutable asset12_b;
    uint256 internal immutable asset13_a;
    uint256 internal immutable asset13_b;
    uint256 internal immutable asset14_a;
    uint256 internal immutable asset14_b;
    uint256 internal immutable asset15_a;
    uint256 internal immutable asset15_b;
    uint256 internal immutable asset16_a;
    uint256 internal immutable asset16_b;
    uint256 internal immutable asset17_a;
    uint256 internal immutable asset17_b;
    uint256 internal immutable asset18_a;
    uint256 internal immutable asset18_b;
    uint256 internal immutable asset19_a;
    uint256 internal immutable asset19_b;
    uint256 internal immutable asset20_a;
    uint256 internal immutable asset20_b;
    uint256 internal immutable asset21_a;
    uint256 internal immutable asset21_b;
    uint256 internal immutable asset22_a;
    uint256 internal immutable asset22_b;
    uint256 internal immutable asset23_a;
    uint256 internal immutable asset23_b;

    /// @notice 该合约实际支持的资产数量（最多 24 个）
    uint8 public immutable numAssets;

    /**
     * @notice 构造函数 - 初始化资产列表
     * @dev 将资产配置打包并存储到不可变变量中
     * @dev 每个资产会被验证并打包成 2 个 uint256
     * @param assetConfigs 资产配置数组（最多 24 个）
     */
    constructor(CometConfiguration.AssetConfig[] memory assetConfigs) {
        // 步骤 1: 记录资产数量
        uint8 _numAssets = uint8(assetConfigs.length);
        numAssets = _numAssets;

        // 步骤 2: 打包并存储每个资产的配置
        // 对于不存在的资产索引，getPackedAssetInternal 会返回 (0, 0)
        (asset00_a, asset00_b) = getPackedAssetInternal(assetConfigs, 0);
        (asset01_a, asset01_b) = getPackedAssetInternal(assetConfigs, 1);
        (asset02_a, asset02_b) = getPackedAssetInternal(assetConfigs, 2);
        (asset03_a, asset03_b) = getPackedAssetInternal(assetConfigs, 3);
        (asset04_a, asset04_b) = getPackedAssetInternal(assetConfigs, 4);
        (asset05_a, asset05_b) = getPackedAssetInternal(assetConfigs, 5);
        (asset06_a, asset06_b) = getPackedAssetInternal(assetConfigs, 6);
        (asset07_a, asset07_b) = getPackedAssetInternal(assetConfigs, 7);
        (asset08_a, asset08_b) = getPackedAssetInternal(assetConfigs, 8);
        (asset09_a, asset09_b) = getPackedAssetInternal(assetConfigs, 9);
        (asset10_a, asset10_b) = getPackedAssetInternal(assetConfigs, 10);
        (asset11_a, asset11_b) = getPackedAssetInternal(assetConfigs, 11);
        (asset12_a, asset12_b) = getPackedAssetInternal(assetConfigs, 12);
        (asset13_a, asset13_b) = getPackedAssetInternal(assetConfigs, 13);
        (asset14_a, asset14_b) = getPackedAssetInternal(assetConfigs, 14);
        (asset15_a, asset15_b) = getPackedAssetInternal(assetConfigs, 15);
        (asset16_a, asset16_b) = getPackedAssetInternal(assetConfigs, 16);
        (asset17_a, asset17_b) = getPackedAssetInternal(assetConfigs, 17);
        (asset18_a, asset18_b) = getPackedAssetInternal(assetConfigs, 18);
        (asset19_a, asset19_b) = getPackedAssetInternal(assetConfigs, 19);
        (asset20_a, asset20_b) = getPackedAssetInternal(assetConfigs, 20);
        (asset21_a, asset21_b) = getPackedAssetInternal(assetConfigs, 21);
        (asset22_a, asset22_b) = getPackedAssetInternal(assetConfigs, 22);
        (asset23_a, asset23_b) = getPackedAssetInternal(assetConfigs, 23);
    }

    /**
     * @dev 检查并打包资产配置，存储为 2 个 uint256 变量
     *
     * @dev 打包格式（word_a，256 位）：
     * @dev - 位 0-159 (160位): 资产合约地址
     * @dev - 位 160-175 (16位): 借贷抵押率（缩放为 4 位小数）
     * @dev - 位 176-191 (16位): 清算阈值（缩放为 4 位小数）
     * @dev - 位 192-207 (16位): 清算惩罚因子（缩放为 4 位小数）
     *
     * @dev 打包格式（word_b，256 位）：
     * @dev - 位 0-159 (160位): 价格预言机地址
     * @dev - 位 160-167 (8位): 资产小数位数
     * @dev - 位 168-231 (64位): 供应上限（整数单位）
     *
     * @param assetConfigs 资产配置数组
     * @param i 要获取的资产索引
     * @return word_a 第一部分打包数据
     * @return word_b 第二部分打包数据
     */
    function getPackedAssetInternal(
        CometConfiguration.AssetConfig[] memory assetConfigs,
        uint i
    ) internal view returns (uint256, uint256) {
        // 步骤 1: 从数组中读取资产配置
        CometConfiguration.AssetConfig memory assetConfig;
        if (i < assetConfigs.length) {
            // 使用汇编直接访问内存，提高效率
            assembly {
                assetConfig := mload(add(add(assetConfigs, 0x20), mul(i, 0x20)))
            }
        } else {
            // 索引超出范围，返回空配置
            return (0, 0);
        }

        // 步骤 2: 提取配置字段
        address asset = assetConfig.asset;
        address priceFeed = assetConfig.priceFeed;
        uint8 decimals_ = assetConfig.decimals;

        // 步骤 3: 如果资产地址为空，返回空配置
        if (asset == address(0)) {
            return (0, 0);
        }

        // 步骤 4: 验证价格预言机和资产小数位数
        if (IPriceFeed(priceFeed).decimals() != PRICE_FEED_DECIMALS)
            revert CometMainInterface.BadDecimals();
        if (IERC20NonStandard(asset).decimals() != decimals_)
            revert CometMainInterface.BadDecimals();

        // 步骤 5: 验证抵押因子的范围
        // borrowCollateralFactor 必须 < liquidateCollateralFactor（留有安全缓冲）
        if (
            assetConfig.borrowCollateralFactor >=
            assetConfig.liquidateCollateralFactor
        ) revert CometMainInterface.BorrowCFTooLarge();
        // liquidateCollateralFactor 不能超过 100%
        if (assetConfig.liquidateCollateralFactor > MAX_COLLATERAL_FACTOR)
            revert CometMainInterface.LiquidateCFTooLarge();

        unchecked {
            // 步骤 6: 缩放因子，减少存储空间
            // 将 18 位小数缩放为 4 位小数（除以 1e14）
            // 例如：0.8e18 → 8000（保留 4 位小数）
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

            // 步骤 7: 再次验证缩放后的值仍在有效范围内
            if (borrowCollateralFactor >= liquidateCollateralFactor)
                revert CometMainInterface.BorrowCFTooLarge();

            // 步骤 8: 将供应上限转换为整数单位（去掉小数）
            // 例如：1000e18（1000 个代币）→ 1000
            uint64 supplyCap = uint64(
                assetConfig.supplyCap / (10 ** decimals_)
            );

            // 步骤 9: 打包第一部分数据（word_a）
            // 使用位运算将多个值打包到一个 uint256 中
            // | 运算符用于组合不同位置的数据
            uint256 word_a = ((uint160(asset) << 0) | // 位 0-159: 资产地址
                (uint256(borrowCollateralFactor) << 160) | // 位 160-175: 借贷抵押率
                (uint256(liquidateCollateralFactor) << 176) | // 位 176-191: 清算阈值
                (uint256(liquidationFactor) << 192)); // 位 192-207: 清算惩罚

            // 步骤 10: 打包第二部分数据（word_b）
            uint256 word_b = ((uint160(priceFeed) << 0) | // 位 0-159: 价格预言机地址
                (uint256(decimals_) << 160) | // 位 160-167: 小数位数
                (uint256(supplyCap) << 168)); // 位 168-231: 供应上限

            return (word_a, word_b);
        }
    }

    /**
     * @notice 获取第 i 个资产的完整信息
     * @dev 从打包的不可变变量中解包并重建资产信息
     * @dev 这个函数将紧凑存储的数据还原为可读的结构体
     * @param i 资产索引（0-23）
     * @return 资产信息结构体，包含地址、价格预言机、抵押率等
     */
    function getAssetInfo(
        uint8 i
    ) public view returns (CometCore.AssetInfo memory) {
        // 步骤 1: 验证索引是否在有效范围内
        if (i >= numAssets) revert CometMainInterface.BadAsset();

        // 步骤 2: 根据索引读取对应的打包数据
        // 使用一系列 if 语句而非 if-else，避免过长的条件链
        uint256 word_a;
        uint256 word_b;
        if (i == 0) {
            word_a = asset00_a;
            word_b = asset00_b;
        }
        if (i == 1) {
            word_a = asset01_a;
            word_b = asset01_b;
        }
        if (i == 2) {
            word_a = asset02_a;
            word_b = asset02_b;
        }
        if (i == 3) {
            word_a = asset03_a;
            word_b = asset03_b;
        }
        if (i == 4) {
            word_a = asset04_a;
            word_b = asset04_b;
        }
        if (i == 5) {
            word_a = asset05_a;
            word_b = asset05_b;
        }
        if (i == 6) {
            word_a = asset06_a;
            word_b = asset06_b;
        }
        if (i == 7) {
            word_a = asset07_a;
            word_b = asset07_b;
        }
        if (i == 8) {
            word_a = asset08_a;
            word_b = asset08_b;
        }
        if (i == 9) {
            word_a = asset09_a;
            word_b = asset09_b;
        }
        if (i == 10) {
            word_a = asset10_a;
            word_b = asset10_b;
        }
        if (i == 11) {
            word_a = asset11_a;
            word_b = asset11_b;
        }
        if (i == 12) {
            word_a = asset12_a;
            word_b = asset12_b;
        }
        if (i == 13) {
            word_a = asset13_a;
            word_b = asset13_b;
        }
        if (i == 14) {
            word_a = asset14_a;
            word_b = asset14_b;
        }
        if (i == 15) {
            word_a = asset15_a;
            word_b = asset15_b;
        }
        if (i == 16) {
            word_a = asset16_a;
            word_b = asset16_b;
        }
        if (i == 17) {
            word_a = asset17_a;
            word_b = asset17_b;
        }
        if (i == 18) {
            word_a = asset18_a;
            word_b = asset18_b;
        }
        if (i == 19) {
            word_a = asset19_a;
            word_b = asset19_b;
        }
        if (i == 20) {
            word_a = asset20_a;
            word_b = asset20_b;
        }
        if (i == 21) {
            word_a = asset21_a;
            word_b = asset21_b;
        }
        if (i == 22) {
            word_a = asset22_a;
            word_b = asset22_b;
        }
        if (i == 23) {
            word_a = asset23_a;
            word_b = asset23_b;
        }

        // 步骤 3: 从 word_a 中解包数据
        // 使用位运算和掩码提取不同位置的值
        address asset = address(uint160(word_a & type(uint160).max)); // 提取位 0-159: 资产地址

        // 步骤 4: 恢复因子的原始缩放（从 4 位小数恢复到 18 位小数）
        uint64 rescale = FACTOR_SCALE / 1e4; // 1e14
        // 例如：8000（4 位小数）× 1e14 = 0.8e18（18 位小数）
        uint64 borrowCollateralFactor = uint64(
            ((word_a >> 160) & type(uint16).max) * rescale
        ); // 位 160-175
        uint64 liquidateCollateralFactor = uint64(
            ((word_a >> 176) & type(uint16).max) * rescale
        ); // 位 176-191
        uint64 liquidationFactor = uint64(
            ((word_a >> 192) & type(uint16).max) * rescale
        ); // 位 192-207

        // 步骤 5: 从 word_b 中解包数据
        address priceFeed = address(uint160(word_b & type(uint160).max)); // 位 0-159: 价格预言机地址
        uint8 decimals_ = uint8(((word_b >> 160) & type(uint8).max)); // 位 160-167: 小数位数

        // 步骤 6: 计算缩放因子和恢复供应上限
        uint64 scale = uint64(10 ** decimals_); // 10^decimals
        uint128 supplyCap = uint128(
            ((word_b >> 168) & type(uint64).max) * scale
        ); // 位 168-231: 供应上限（还原为原始单位）

        // 步骤 7: 构建并返回资产信息结构体
        return
            CometCore.AssetInfo({
                offset: i, // 资产索引
                asset: asset, // 资产地址
                priceFeed: priceFeed, // 价格预言机地址
                scale: scale, // 缩放因子（10^decimals）
                borrowCollateralFactor: borrowCollateralFactor, // 借贷抵押率
                liquidateCollateralFactor: liquidateCollateralFactor, // 清算阈值
                liquidationFactor: liquidationFactor, // 清算惩罚因子
                supplyCap: supplyCap // 供应上限
            });
    }
}
