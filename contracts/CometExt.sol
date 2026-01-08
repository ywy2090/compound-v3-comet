// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometExtInterface.sol";

/**
 * @title CometExt
 * @notice Comet 扩展合约
 * @dev 实现了主合约中放不下的额外功能
 * @dev 通过 delegatecall 从主合约调用，共享存储空间
 * @dev 主要功能：
 * @dev 1. ERC20 标准接口（approve, allowance）
 * @dev 2. 名称和符号查询
 * @dev 3. EIP-712 签名授权
 * @dev 4. 各种查询接口
 */
contract CometExt is CometExtInterface {
    // ============ 公共常量 ============

    /// @notice 合约的主版本号
    string public override constant version = "0";

    // ============ 内部常量 ============

    /// @dev EIP-712 域分隔符的类型哈希
    /// @dev 用于结构化数据签名，防止跨合约重放攻击
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 授权消息的类型哈希
    /// @dev 用于 allowBySig 函数的签名验证
    bytes32 internal constant AUTHORIZATION_TYPEHASH = keccak256("Authorization(address owner,address manager,bool isAllowed,uint256 nonce,uint256 expiry)");

    /// @dev ECDSA 签名中 s 值的最大有效值
    /// @dev s 必须满足：0 < s < secp256k1n ÷ 2 + 1
    /// @dev 这是为了防止签名延展性攻击（signature malleability）
    /// @dev 参考：https://ethereum.github.io/yellowpaper/paper.pdf #307
    uint internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // ============ 不可变变量 ============

    /// @dev ERC20 代币名称（bytes32 格式，节省 gas）
    /// @dev 例如："Compound USDC" 存储为固定 32 字节
    bytes32 internal immutable name32;

    /// @dev ERC20 代币符号（bytes32 格式，节省 gas）
    /// @dev 例如："cUSDCv3" 存储为固定 32 字节
    bytes32 internal immutable symbol32;

    /**
     * @notice 构造函数 - 创建新的扩展合约实例
     * @param config 扩展配置参数（包含名称和符号）
     */
    constructor(ExtConfiguration memory config) {
        name32 = config.name32;
        symbol32 = config.symbol32;
    }

    // ============ 常量获取函数 ============
    // 提供外部访问内部常量的接口

    /// @notice 获取基础累积缩放因子（1e6）
    /// @return 基础累积缩放值
    function baseAccrualScale() override external pure returns (uint64) { return BASE_ACCRUAL_SCALE; }

    /// @notice 获取基础指数缩放因子（1e15）
    /// @return 基础指数缩放值
    function baseIndexScale() override external pure returns (uint64) { return BASE_INDEX_SCALE; }

    /// @notice 获取因子缩放常量（1e18）
    /// @return 因子缩放值
    function factorScale() override external pure returns (uint64) { return FACTOR_SCALE; }

    /// @notice 获取价格缩放常量（1e8）
    /// @return 价格缩放值
    function priceScale() override external pure returns (uint64) { return PRICE_SCALE; }

    /// @notice 获取最大支持资产数（15）
    /// @return 最大资产数
    function maxAssets() override virtual external pure returns (uint8) { return MAX_ASSETS; }

    /**
     * @notice 获取市场全局基础统计数据
     * @dev 返回所有关键市场指标的快照
     * @return TotalsBasic 结构体，包含指数、总量、时间戳等
     */
    function totalsBasic() public override view returns (TotalsBasic memory) {
        return TotalsBasic({
            baseSupplyIndex: baseSupplyIndex,          // 供应指数
            baseBorrowIndex: baseBorrowIndex,          // 借贷指数
            trackingSupplyIndex: trackingSupplyIndex,  // 供应奖励追踪指数
            trackingBorrowIndex: trackingBorrowIndex,  // 借贷奖励追踪指数
            totalSupplyBase: totalSupplyBase,          // 总供应量（本金）
            totalBorrowBase: totalBorrowBase,          // 总借贷量（本金）
            lastAccrualTime: lastAccrualTime,          // 上次累积时间
            pauseFlags: pauseFlags                     // 暂停标志位
        });
    }

    // ============ ERC20 功能和查询接口 ============

    /**
     * @notice 获取 ERC20 代币名称
     * @dev 将 bytes32 格式的名称转换为 string 类型
     * @dev 遍历 bytes32 找到第一个 null 字符，截断后返回
     * @return 代币名称字符串（如 "Compound USDC"）
     */
    function name() override public view returns (string memory) {
        uint8 i;
        // 找到名称的实际长度（遇到 null 字符停止）
        for (i = 0; i < 32; ) {
            if (name32[i] == 0) {
                break;
            }
            unchecked { i++; }
        }
        // 创建正确长度的 bytes 数组
        bytes memory name_ = new bytes(i);
        // 复制字符
        for (uint8 j = 0; j < i; ) {
            name_[j] = name32[j];
            unchecked { j++; }
        }
        return string(name_);
    }

    /**
     * @notice 获取 ERC20 代币符号
     * @dev 将 bytes32 格式的符号转换为 string 类型
     * @dev 转换逻辑与 name() 相同
     * @return 代币符号字符串（如 "cUSDCv3"）
     */
    function symbol() override external view returns (string memory) {
        uint8 i;
        // 找到符号的实际长度
        for (i = 0; i < 32; ) {
            if (symbol32[i] == 0) {
                break;
            }
            unchecked { i++; }
        }
        // 创建正确长度的 bytes 数组
        bytes memory symbol_ = new bytes(i);
        // 复制字符
        for (uint8 j = 0; j < i; ) {
            symbol_[j] = symbol32[j];
            unchecked { j++; }
        }
        return string(symbol_);
    }

    /**
     * @notice 查询账户的抵押品余额
     * @dev 直接读取 userCollateral 映射
     * @param account 要查询的账户地址
     * @param asset 抵押品资产地址
     * @return 该账户在该抵押品上的余额
     */
    function collateralBalanceOf(address account, address asset) override external view returns (uint128) {
        return userCollateral[account][asset].balance;
    }

    /**
     * @notice 查询账户累积的基础奖励
     * @dev 返回已累积但未领取的奖励
     * @dev 奖励以 BASE_ACCRUAL_SCALE 为单位缩放
     * @param account 要查询的账户地址
     * @return 累积的奖励量（uint64，BASE_ACCRUAL_SCALE 单位）
     */
    function baseTrackingAccrued(address account) override external view returns (uint64) {
        return userBasic[account].baseTrackingAccrued;
    }

    // ============ 授权功能（ERC20 兼容） ============

    /**
     * @notice 授权或取消授权 spender 代表发送者转账（ERC20 标准）
     * @dev 注意：这是二元授权，与大多数 ERC20 代币不同
     * @dev 注意：授权后 spender 可以管理所有者的*所有*资产（不是特定金额）
     * @dev 只接受两种值：
     * @dev - type(uint256).max (授权)
     * @dev - 0 (取消授权)
     * @param spender 可能转账的账户地址
     * @param amount 必须是 uint256.max（授权）或 0（取消授权）
     * @return 授权是否成功（总是返回 true，失败会 revert）
     */
    function approve(address spender, uint256 amount) override external returns (bool) {
        if (amount == type(uint256).max) {
            // 授权：允许 spender 管理所有资产
            allowInternal(msg.sender, spender, true);
        } else if (amount == 0) {
            // 取消授权
            allowInternal(msg.sender, spender, false);
        } else {
            // 不接受其他金额
            revert BadAmount();
        }
        return true;
    }

    /**
     * @notice 查询 owner 对 spender 的授权额度（ERC20 标准）
     * @dev 注意：这是二元授权，与大多数 ERC20 代币不同
     * @dev 注意：授权允许 spender 管理所有者的*所有*资产
     * @param owner 拥有代币的账户地址
     * @param spender 可能转账的账户地址
     * @return 如果已授权返回 uint256.max，否则返回 0
     */
    function allowance(address owner, address spender) override external view returns (uint256) {
        return hasPermission(owner, spender) ? type(uint256).max : 0;
    }

    /**
     * @notice 授权或取消授权另一个地址提现或转账
     * @dev 这是 Comet 特有的授权接口（非 ERC20 标准）
     * @dev 授权后 manager 可以调用 *From 系列函数
     * @param manager 将被授权或取消授权的账户
     * @param isAllowed_ true 表示授权，false 表示取消授权
     */
    function allow(address manager, bool isAllowed_) override external {
        allowInternal(msg.sender, manager, isAllowed_);
    }

    /**
     * @dev 内部函数：存储管理者是否被授权代表所有者操作
     * @dev 同时发出 Approval 事件（ERC20 兼容）
     * @param owner 所有者地址
     * @param manager 管理者地址
     * @param isAllowed_ 是否授权
     */
    function allowInternal(address owner, address manager, bool isAllowed_) internal {
        isAllowed[owner][manager] = isAllowed_;
        // 发出 ERC20 标准的 Approval 事件
        // amount 为 uint256.max 表示授权，0 表示取消授权
        emit Approval(owner, manager, isAllowed_ ? type(uint256).max : 0);
    }

    // ============ 签名授权（EIP-712） ============

    /**
     * @notice 通过签名授权管理者（无需链上交互）
     * @dev 实现 EIP-712 标准的签名授权
     * @dev 允许用户通过签名消息授权，无需发送交易
     * @dev 常用场景：
     * @dev - 用户在链下签名，第三方代付 gas 费用提交
     * @dev - 批量授权操作
     * @dev - 改善用户体验（无需等待交易确认）
     * 
     * @param owner 签名者的地址（将被授权出去的账户）
     * @param manager 要授权（或取消授权）的地址
     * @param isAllowed_ true 表示授权，false 表示取消授权
     * @param nonce 签名者的当前 nonce（防止重放攻击）
     * @param expiry 签名的过期时间（Unix 时间戳）
     * @param v 签名的恢复字节（27 或 28）
     * @param r ECDSA 签名对的前半部分
     * @param s ECDSA 签名对的后半部分
     */
    function allowBySig(
        address owner,
        address manager,
        bool isAllowed_,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) override external {
        // 1. 验证签名的 s 值（防止签名延展性攻击）
        // s 必须在有效范围内：0 < s < secp256k1n ÷ 2 + 1
        if (uint256(s) > MAX_VALID_ECDSA_S) revert InvalidValueS();
        
        // 2. 验证签名的 v 值
        // v 必须是 27 或 28（参考：Ethereum Yellow Paper #308）
        if (v != 27 && v != 28) revert InvalidValueV();
        
        // 3. 构造 EIP-712 域分隔符
        // 包含：合约名称、版本、链 ID、合约地址
        // 确保签名只在特定链和合约上有效
        bytes32 domainSeparator = keccak256(abi.encode(
            DOMAIN_TYPEHASH, 
            keccak256(bytes(name())),      // 合约名称哈希
            keccak256(bytes(version)),     // 版本号哈希
            block.chainid,                 // 当前链 ID
            address(this)                  // 当前合约地址
        ));
        
        // 4. 构造结构化数据哈希
        // 包含授权的所有参数
        bytes32 structHash = keccak256(abi.encode(
            AUTHORIZATION_TYPEHASH,
            owner,
            manager,
            isAllowed_,
            nonce,
            expiry
        ));
        
        // 5. 计算最终的消息摘要
        // 使用 EIP-712 标准格式："\x19\x01" + domainSeparator + structHash
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        // 6. 从签名恢复签名者地址
        address signatory = ecrecover(digest, v, r, s);
        
        // 7. 验证签名有效性
        if (signatory == address(0)) revert BadSignatory();     // ecrecover 失败
        if (owner != signatory) revert BadSignatory();          // 签名者不匹配
        if (nonce != userNonce[signatory]++) revert BadNonce(); // nonce 不匹配（防止重放）
        if (block.timestamp >= expiry) revert SignatureExpired(); // 签名已过期
        
        // 8. 执行授权
        allowInternal(signatory, manager, isAllowed_);
    }
}