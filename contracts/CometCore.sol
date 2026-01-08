// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometConfiguration.sol";
import "./CometStorage.sol";
import "./CometMath.sol";

/**
 * @title CometCore
 * @notice Comet 协议的核心抽象合约
 * @dev 继承配置、存储和数学工具，提供核心常量和辅助函数
 * @dev 这是 Comet 和 CometExt 的共同基类
 */
abstract contract CometCore is CometConfiguration, CometStorage, CometMath {
    /**
     * @dev 资产信息结构（运行时使用）
     * @dev 这是从紧凑存储格式解包后的完整资产信息
     */
    struct AssetInfo {
        uint8 offset;                       // 资产在数组中的索引位置
        address asset;                      // 资产合约地址
        address priceFeed;                  // 价格预言机地址
        uint64 scale;                       // 资产的缩放因子（10^decimals）
        uint64 borrowCollateralFactor;     // 借贷抵押率（FACTOR_SCALE 单位）
        uint64 liquidateCollateralFactor;  // 清算阈值（FACTOR_SCALE 单位）
        uint64 liquidationFactor;           // 清算惩罚因子
        uint128 supplyCap;                  // 供应上限（资产单位）
    }

    // ============ 内部常量 ============

    /// @dev 合约硬编码支持的最大资产数量
    /// @dev 注意：修改此值需要同时更新合约中的所有相关字段
    /// @dev 特别是 UserBasic.assetsIn 的大小（uint16 = 16 位）和对应的整数转换
    uint8 internal constant MAX_ASSETS = 15;

    /// @dev 基础代币可以拥有的最大小数位数
    /// @dev 注意：这个值不能随意增加，因为涉及到精度计算和溢出风险
    /// @dev uint104 最大值约为 2^104 / 1e18 ≈ 20 万亿（对于 18 位小数）
    uint8 internal constant MAX_BASE_DECIMALS = 18;

    /// @dev 抵押因子的最大值（1.0 = 100%）
    /// @dev 等于 FACTOR_SCALE，即 1e18
    uint64 internal constant MAX_COLLATERAL_FACTOR = FACTOR_SCALE;

    // ============ 暂停标志位偏移量 ============
    // 使用位标志存储多个暂停状态，节省 gas
    
    /// @dev 供应功能的暂停标志位偏移（第 0 位）
    uint8 internal constant PAUSE_SUPPLY_OFFSET = 0;
    /// @dev 转账功能的暂停标志位偏移（第 1 位）
    uint8 internal constant PAUSE_TRANSFER_OFFSET = 1;
    /// @dev 提现功能的暂停标志位偏移（第 2 位）
    uint8 internal constant PAUSE_WITHDRAW_OFFSET = 2;
    /// @dev 清算（absorb）功能的暂停标志位偏移（第 3 位）
    uint8 internal constant PAUSE_ABSORB_OFFSET = 3;
    /// @dev 购买抵押品功能的暂停标志位偏移（第 4 位）
    uint8 internal constant PAUSE_BUY_OFFSET = 4;

    // ============ 精度和缩放常量 ============

    /// @dev 价格预言机要求的小数位数
    /// @dev 所有价格必须标准化为 8 位小数
    uint8 internal constant PRICE_FEED_DECIMALS = 8;

    /// @dev 一年的秒数（用于年化利率转换为秒利率）
    /// @dev 365 天 × 24 小时 × 60 分钟 × 60 秒
    uint64 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @dev 基础追踪累积的缩放因子
    /// @dev 用于奖励计算，1e6 = 100 万
    uint64 internal constant BASE_ACCRUAL_SCALE = 1e6;

    /// @dev 基础指数的缩放因子
    /// @dev 用于利率指数计算，独立于基础代币的小数位数
    /// @dev 1e15 = 1,000,000,000,000,000
    uint64 internal constant BASE_INDEX_SCALE = 1e15;

    /// @dev 价格的缩放因子（以 USD 计价）
    /// @dev 10^8 = 100,000,000（对应 8 位小数）
    uint64 internal constant PRICE_SCALE = uint64(10 ** PRICE_FEED_DECIMALS);

    /// @dev 因子的缩放常量
    /// @dev 用于抵押因子、利率等百分比值
    /// @dev 1e18 表示 100%
    uint64 internal constant FACTOR_SCALE = 1e18;

    // ============ 重入保护 ============

    /// @dev 重入保护标志的存储槽
    /// @dev 使用 keccak256 哈希生成特定位置，避免与常规存储槽冲突
    bytes32 internal constant REENTRANCY_GUARD_FLAG_SLOT = bytes32(keccak256("comet.reentrancy.guard"));

    /// @dev 重入保护状态：未进入
    uint256 internal constant REENTRANCY_GUARD_NOT_ENTERED = 0;
    /// @dev 重入保护状态：已进入
    uint256 internal constant REENTRANCY_GUARD_ENTERED = 1;

    // ============ 权限管理 ============

    /**
     * @notice 检查管理者是否有权限代表所有者操作
     * @dev 所有者自己总是有权限，或者明确授权的管理者也有权限
     * @param owner 所有者账户地址
     * @param manager 管理者账户地址
     * @return 如果管理者有权限则返回 true
     */
    function hasPermission(address owner, address manager) public view returns (bool) {
        return owner == manager || isAllowed[owner][manager];
    }

    // ============ 价值计算函数（本金 ↔ 当前价值） ============
    // 这些函数是协议的核心，用于在本金和当前价值之间转换
    // 随着利息累积，相同的本金会增长为更大的当前价值

    /**
     * @notice 将有符号本金转换为当前价值
     * @dev 正值表示供应，负值表示借贷
     * @dev 供应的当前价值 = 本金 × 供应指数 / 指数缩放
     * @dev 借贷的当前价值 = 本金 × 借贷指数 / 指数缩放（返回负值）
     * @param principalValue_ 有符号本金（int104）
     * @return 当前价值（int256，正值或负值）
     */
    function presentValue(int104 principalValue_) internal view returns (int256) {
        if (principalValue_ >= 0) {
            // 正本金：供应情况
            return signed256(presentValueSupply(baseSupplyIndex, uint104(principalValue_)));
        } else {
            // 负本金：借贷情况
            return -signed256(presentValueBorrow(baseBorrowIndex, uint104(-principalValue_)));
        }
    }

    /**
     * @notice 将供应本金通过供应指数投影到当前价值
     * @dev 公式：当前价值 = 本金 × 供应指数 / BASE_INDEX_SCALE
     * @dev 随着时间推移和利息累积，供应指数持续增长
     * @param baseSupplyIndex_ 供应指数（通常使用全局的 baseSupplyIndex）
     * @param principalValue_ 本金金额
     * @return 投影后的当前价值
     */
    function presentValueSupply(uint64 baseSupplyIndex_, uint104 principalValue_) internal pure returns (uint256) {
        return uint256(principalValue_) * baseSupplyIndex_ / BASE_INDEX_SCALE;
    }

    /**
     * @notice 将借贷本金通过借贷指数投影到当前价值
     * @dev 公式：当前价值 = 本金 × 借贷指数 / BASE_INDEX_SCALE
     * @dev 随着时间推移和利息累积，借贷指数持续增长，债务也随之增长
     * @param baseBorrowIndex_ 借贷指数（通常使用全局的 baseBorrowIndex）
     * @param principalValue_ 本金金额
     * @return 投影后的当前价值（债务金额）
     */
    function presentValueBorrow(uint64 baseBorrowIndex_, uint104 principalValue_) internal pure returns (uint256) {
        return uint256(principalValue_) * baseBorrowIndex_ / BASE_INDEX_SCALE;
    }

    /**
     * @notice 将当前价值转换回本金
     * @dev 这是 presentValue 的逆运算
     * @dev 正值表示供应，负值表示借贷
     * @param presentValue_ 当前价值（int256）
     * @return 本金（int104）
     */
    function principalValue(int256 presentValue_) internal view returns (int104) {
        if (presentValue_ >= 0) {
            // 正当前价值：供应情况
            return signed104(principalValueSupply(baseSupplyIndex, uint256(presentValue_)));
        } else {
            // 负当前价值：借贷情况
            return -signed104(principalValueBorrow(baseBorrowIndex, uint256(-presentValue_)));
        }
    }

    /**
     * @notice 将供应的当前价值通过供应指数反向投影回本金（向下舍入）
     * @dev 公式：本金 = 当前价值 × BASE_INDEX_SCALE / 供应指数
     * @dev 向下舍入对协议有利（供应者获得稍少）
     * @dev 注意：当本金超过 2^104/1e18 ≈ 20 万亿时会溢出（对于 18 位小数的资产）
     * @param baseSupplyIndex_ 供应指数
     * @param presentValue_ 当前价值
     * @return 本金（uint104）
     */
    function principalValueSupply(uint64 baseSupplyIndex_, uint256 presentValue_) internal pure returns (uint104) {
        return safe104((presentValue_ * BASE_INDEX_SCALE) / baseSupplyIndex_);
    }

    /**
     * @notice 将借贷的当前价值通过借贷指数反向投影回本金（向上舍入）
     * @dev 公式：本金 = (当前价值 × BASE_INDEX_SCALE + 借贷指数 - 1) / 借贷指数
     * @dev 向上舍入对协议有利（借款人需要偿还稍多）
     * @dev 注意：当本金超过 2^104/1e18 ≈ 20 万亿时会溢出（对于 18 位小数的资产）
     * @param baseBorrowIndex_ 借贷指数
     * @param presentValue_ 当前价值（债务金额）
     * @return 本金（uint104）
     */
    function principalValueBorrow(uint64 baseBorrowIndex_, uint256 presentValue_) internal pure returns (uint104) {
        // +baseBorrowIndex_ - 1 实现向上舍入
        return safe104((presentValue_ * BASE_INDEX_SCALE + baseBorrowIndex_ - 1) / baseBorrowIndex_);
    }
}
