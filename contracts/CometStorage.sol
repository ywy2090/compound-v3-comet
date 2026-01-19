// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

/**
 * @title Compound's Comet Storage Interface
 * @title Compound Comet 存储接口
 * @dev Versions can enforce append-only storage slots via inheritance.
 * @dev 通过继承可以强制执行仅追加的存储槽，确保升级兼容性
 * @dev 所有存储变量都经过精心设计，使用紧凑打包以节省 gas
 * @dev 中文：集中定义核心存储布局，保持升级安全
 * @author Compound
 */
contract CometStorage {
    /**
     * @dev 市场全局基础统计数据
     * @dev 总计 512 bits = 2 个存储槽，精心打包以优化 gas 成本
     * @dev 每次市场操作都会读取这些数据，因此优化极其重要
     */
    struct TotalsBasic {
        // === 第一个存储槽 (256 bits) ===
        uint64 baseSupplyIndex;      // 供应累积指数，用于计算供应的利息
        uint64 baseBorrowIndex;      // 借贷累积指数，用于计算借贷的利息
        uint64 trackingSupplyIndex;  // 供应奖励追踪指数，用于计算供应者的奖励
        uint64 trackingBorrowIndex;  // 借贷奖励追踪指数，用于计算借款者的奖励
        
        // === 第二个存储槽 (256 bits) ===
        uint104 totalSupplyBase;     // 市场基础资产总供应量（本金）
        uint104 totalBorrowBase;     // 市场基础资产总借贷量（本金）
        uint40 lastAccrualTime;      // 上次利息累积的时间戳
        uint8 pauseFlags;            // 暂停标志位（5 位分别表示不同功能的暂停状态）
    }

    /**
     * @dev 单个抵押资产的全局统计
     * @dev 256 bits = 1 个存储槽
     */
    struct TotalsCollateral {
        uint128 totalSupplyAsset;    // 该抵押资产的总供应量
        uint128 _reserved;           // 预留字段，用于未来扩展
    }

    /**
     * @dev 用户的基础账户数据
     * @dev 256 bits = 1 个存储槽，包含用户在基础资产上的所有关键信息
     */
    struct UserBasic {
        int104 principal;            // 用户本金（正值=供应，负值=借贷）
                                     // 使用有符号整数巧妙地区分供应和借贷
        uint64 baseTrackingIndex;    // 用户的奖励追踪索引快照
        uint64 baseTrackingAccrued;  // 用户已累积的奖励（未领取）
        uint16 assetsIn;             // 位标志，记录用户持有哪些抵押资产（最多 16 种）
                                     // 例如：0b0000000000000101 表示持有资产 0 和资产 2
        uint8 _reserved;             // 预留字段，用于未来扩展
    }

    /**
     * @dev 用户的单个抵押资产数据
     * @dev 256 bits = 1 个存储槽
     */
    struct UserCollateral {
        uint128 balance;             // 用户在该抵押资产上的余额
        uint128 _reserved;           // 预留字段，用于未来扩展
    }

    /**
     * @dev 清算人的统计积分
     * @dev 256 bits = 1 个存储槽
     * @dev 用于追踪清算人的活动，可能用于激励或排名
     */
    struct LiquidatorPoints {
        uint32 numAbsorbs;           // 执行清算（absorb）的次数
        uint64 numAbsorbed;          // 被清算的账户总数
        uint128 approxSpend;         // 大约花费的金额
        uint32 _reserved;            // 预留字段
    }

    // ============ 全局状态变量 ============
    // 注意：这些变量与 TotalsBasic 结构体字段一一对应，但独立存储
    
    /// @dev 市场全局供应指数（随时间累积利息）
    uint64 internal baseSupplyIndex;
    /// @dev 市场全局借贷指数（随时间累积利息）
    uint64 internal baseBorrowIndex;
    /// @dev 市场全局供应奖励追踪索引
    uint64 internal trackingSupplyIndex;
    /// @dev 市场全局借贷奖励追踪索引
    uint64 internal trackingBorrowIndex;
    /// @dev 市场总供应量（基础资产本金）
    uint104 internal totalSupplyBase;
    /// @dev 市场总借贷量（基础资产本金）
    uint104 internal totalBorrowBase;
    /// @dev 上次利息累积时间
    uint40 internal lastAccrualTime;
    /// @dev 暂停标志位（供应、转账、提现、清算、购买）
    uint8 internal pauseFlags;

    // ============ 映射存储 ============

    /// @notice 每个抵押资产的全局统计数据
    /// @dev 映射：抵押资产地址 => 该资产的总供应量等信息
    mapping(address => TotalsCollateral) public totalsCollateral;

    /// @notice 用户授权映射
    /// @dev 映射：所有者地址 => 管理者地址 => 是否授权
    /// @dev 允许用户授权其他地址管理自己的账户（如智能合约钱包）
    mapping(address => mapping(address => bool)) public ;

    /// @notice 用户签名授权的 nonce
    /// @dev 映射：用户地址 => nonce
    /// @dev 用于 EIP-712 签名授权，防止重放攻击
    mapping(address => uint) public userNonce;

    /// @notice 用户的基础账户数据
    /// @dev 映射：用户地址 => 用户基础数据（本金、奖励等）
    mapping(address => UserBasic) public userBasic;

    /// @notice 用户的抵押资产余额
    /// @dev 二维映射：用户地址 => 抵押资产地址 => 该资产的余额
    mapping(address => mapping(address => UserCollateral)) public userCollateral;

    /// @notice 清算人的统计积分
    /// @dev 映射：清算人地址 => 清算统计数据
    /// @dev "magic" 指的是这些积分可能用于未来的激励机制
    mapping(address => LiquidatorPoints) public liquidatorPoints;
}
