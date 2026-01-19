// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

/**
 * @title Compound's Comet Configuration Interface
 * @title Compound Comet 配置接口
 * @dev 定义了 Comet 协议的配置数据结构
 * @dev 中文：部署与参数配置的数据结构集合
 * @author Compound
 */
contract CometConfiguration {
    /**
     * @dev CometExt 扩展合约的配置
     * @dev 用于存储 ERC20 代币的名称和符号（使用 bytes32 节省 gas）
     */
    struct ExtConfiguration {
        bytes32 name32;    // ERC20 代币名称，最多 32 字节
        bytes32 symbol32;  // ERC20 代币符号，最多 32 字节
    }

    /**
     * @dev Comet 主合约的完整配置
     * @dev 这些参数在合约部署时设置，部分参数可通过治理更新
     */
    struct Configuration {
        // === 治理与权限 ===
        address governor;           // 治理地址，拥有最高权限，可以修改协议参数
        address pauseGuardian;      // 暂停守护者，可以暂停协议功能（但不能恢复）
        
        // === 基础资产配置 ===
        address baseToken;          // 基础借贷资产地址（如 USDC、USDT），不可更改
        address baseTokenPriceFeed; // 基础资产的价格预言机地址
        address extensionDelegate;  // 扩展合约地址，通过 delegatecall 处理额外功能

        // === 供应利率模型（使用双斜率 Kink 模型）===
        uint64 supplyKink;                        // 供应利率拐点（utilization 阈值），单位：FACTOR_SCALE
        uint64 supplyPerYearInterestRateSlopeLow; // 低于拐点时的利率斜率（年化）
        uint64 supplyPerYearInterestRateSlopeHigh;// 高于拐点时的利率斜率（年化）
        uint64 supplyPerYearInterestRateBase;     // 基础供应利率（年化）
        
        // === 借贷利率模型 ===
        uint64 borrowKink;                        // 借贷利率拐点（utilization 阈值）
        uint64 borrowPerYearInterestRateSlopeLow; // 低于拐点时的利率斜率（年化）
        uint64 borrowPerYearInterestRateSlopeHigh;// 高于拐点时的利率斜率（年化）
        uint64 borrowPerYearInterestRateBase;     // 基础借贷利率（年化）
        
        // === 清算与奖励参数 ===
        uint64 storeFrontPriceFactor;  // 清算折扣因子，购买抵押品时的价格折扣
        uint64 trackingIndexScale;     // 奖励追踪索引的缩放因子，不可更改
        uint64 baseTrackingSupplySpeed;// 供应奖励速度（单位时间内的奖励增长）
        uint64 baseTrackingBorrowSpeed;// 借贷奖励速度（单位时间内的奖励增长）
        uint104 baseMinForRewards;     // 获得奖励的最小本金要求
        
        // === 协议参数 ===
        uint104 baseBorrowMin;    // 最小借贷金额，防止过小的借贷位置
        uint104 targetReserves;   // 目标储备金，超过此值才能购买抵押品

        // === 抵押资产配置 ===
        AssetConfig[] assetConfigs; // 支持的抵押资产列表（最多 15 个）
    }

    /**
     * @dev 单个抵押资产的配置
     * @dev 每个 Comet 市场可以有多种抵押资产，但只有一种基础借贷资产
     */
    struct AssetConfig {
        address asset;                      // 抵押资产的合约地址
        address priceFeed;                  // 该资产的价格预言机地址
        uint8 decimals;                     // 资产的小数位数（用于精度计算）
        uint64 borrowCollateralFactor;     // 借贷抵押率（如 0.8e18 表示 80%）
                                            // 表示 $1 的抵押品最多可以借 $0.80
        uint64 liquidateCollateralFactor;  // 清算阈值（如 0.85e18 表示 85%）
                                            // 当抵押率低于此值时可被清算
        uint64 liquidationFactor;           // 清算惩罚因子
        uint128 supplyCap;                  // 该资产的供应上限（防止单一资产风险过大）
    }
}
