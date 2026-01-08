// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometInterface.sol";
import "./ERC20.sol";

/**
 * @title Compound's CometRewards Contract
 * @title Compound Comet 奖励分发合约
 * @notice Hold and claim token rewards
 * @notice 持有并分发代币奖励（通常是 COMP 代币）
 * @dev 独立于 Comet 主合约，负责管理和分发协议激励奖励
 * @dev 每个 Comet 市场可以配置不同的奖励代币和参数
 * @author Compound
 */
contract CometRewards {
    /**
     * @dev 单个 Comet 市场的奖励配置
     * @dev 处理不同精度代币的缩放和倍数调整
     */
    struct RewardConfig {
        address token;              // 奖励代币地址（如 COMP）
        uint64 rescaleFactor;       // 重新缩放因子，用于精度转换
        bool shouldUpscale;         // 是否需要放大（true）或缩小（false）
        // 注意：新变量定义在现有变量之后以保持向后兼容性
        uint256 multiplier;         // 奖励倍数（FACTOR_SCALE 单位），用于调整奖励强度
    }

    /**
     * @dev 用户应得奖励的结构体
     */
    struct RewardOwed {
        address token;              // 奖励代币地址
        uint owed;                  // 应得数量
    }

    // ============ 状态变量 ============

    /// @notice 治理地址，控制合约配置
    address public governor;

    /// @notice 每个 Comet 实例的奖励配置
    /// @dev 映射：Comet 地址 => 奖励配置
    mapping(address => RewardConfig) public rewardConfig;

    /// @notice 每个用户在每个 Comet 实例上已领取的奖励
    /// @dev 映射：Comet 地址 => 用户地址 => 已领取数量
    /// @dev 用于计算：应得奖励 = 累积奖励 - 已领取奖励
    mapping(address => mapping(address => uint)) public rewardsClaimed;

    /// @dev 因子缩放常量（1e18 = 100%）
    uint256 internal constant FACTOR_SCALE = 1e18;

    // ============ 事件 ============

    /// @notice 治理权转移事件
    event GovernorTransferred(address indexed oldGovernor, address indexed newGovernor);

    /// @notice 用户已领取奖励记录设置事件（用于迁移或初始化）
    event RewardsClaimedSet(address indexed user, address indexed comet, uint256 amount);

    /// @notice 奖励领取事件
    event RewardClaimed(address indexed src, address indexed recipient, address indexed token, uint256 amount);

    // ============ 错误 ============

    /// @dev Comet 实例已配置过奖励，不能重复配置
    error AlreadyConfigured(address);
    /// @dev 输入数据无效（如数组长度不匹配）
    error BadData();
    /// @dev 数值超过 uint64 最大值
    error InvalidUInt64(uint);
    /// @dev 调用者无权限
    error NotPermitted(address);
    /// @dev Comet 实例未配置奖励
    error NotSupported(address);
    /// @dev 代币转出失败
    error TransferOutFailed(address, uint);

    // ============ 构造函数 ============

    /**
     * @notice 构造一个新的奖励池
     * @param governor_ 控制合约的治理地址
     */
    constructor(address governor_) {
        governor = governor_;
    }

    // ============ 配置函数（仅治理可调用）============

    /**
     * @notice 为 Comet 实例设置奖励代币（带倍数参数）
     * @dev 只能调用一次，配置后不可更改
     * @dev 自动处理 Comet 累积精度和奖励代币精度之间的转换
     * 
     * @param comet 协议实例地址
     * @param token 奖励代币地址（如 COMP）
     * @param multiplier 奖励倍数（FACTOR_SCALE 单位）
     * 
     * @dev 精度转换逻辑：
     * @dev - 如果 accrualScale (1e6) > tokenScale (如 1e6 的 USDC)
     * @dev   则需要缩小：rescaleFactor = accrualScale / tokenScale
     * @dev - 如果 accrualScale (1e6) < tokenScale (如 1e18 的 COMP)
     * @dev   则需要放大：rescaleFactor = tokenScale / accrualScale
     */
    function setRewardConfigWithMultiplier(address comet, address token, uint256 multiplier) public {
        // 权限检查
        if (msg.sender != governor) revert NotPermitted(msg.sender);
        // 防止重复配置
        if (rewardConfig[comet].token != address(0)) revert AlreadyConfigured(comet);

        // 获取 Comet 的累积缩放因子（通常是 1e6）
        uint64 accrualScale = CometInterface(comet).baseAccrualScale();
        // 获取奖励代币的小数位数
        uint8 tokenDecimals = ERC20(token).decimals();
        // 计算奖励代币的缩放因子
        uint64 tokenScale = safe64(10 ** tokenDecimals);
        
        if (accrualScale > tokenScale) {
            // 累积精度高于代币精度，需要缩小
            // 例如：accrualScale=1e6, tokenScale=1e6 => rescaleFactor=1
            rewardConfig[comet] = RewardConfig({
                token: token,
                rescaleFactor: accrualScale / tokenScale,
                shouldUpscale: false,        // 不放大，而是缩小
                multiplier: multiplier
            });
        } else {
            // 累积精度低于或等于代币精度，需要放大
            // 例如：accrualScale=1e6, tokenScale=1e18 => rescaleFactor=1e12
            rewardConfig[comet] = RewardConfig({
                token: token,
                rescaleFactor: tokenScale / accrualScale,
                shouldUpscale: true,         // 需要放大
                multiplier: multiplier
            });
        }
    }

    /**
     * @notice 为 Comet 实例设置奖励代币（使用默认倍数 1.0）
     * @param comet 协议实例地址
     * @param token 奖励代币地址
     */
    function setRewardConfig(address comet, address token) external {
        // 使用 1.0 (FACTOR_SCALE) 作为默认倍数
        setRewardConfigWithMultiplier(comet, token, FACTOR_SCALE);
    }

    /**
     * @notice 批量设置用户已领取的奖励记录
     * @dev 用于迁移或初始化数据
     * @dev 仅治理地址可调用
     * 
     * @param comet 协议实例地址
     * @param users 用户地址列表
     * @param claimedAmounts 对应的已领取金额列表
     */
    function setRewardsClaimed(address comet, address[] calldata users, uint[] calldata claimedAmounts) external {
        // 权限检查
        if (msg.sender != governor) revert NotPermitted(msg.sender);
        // 数据验证：两个数组长度必须相同
        if (users.length != claimedAmounts.length) revert BadData();

        // 批量设置
        for (uint i = 0; i < users.length; ) {
            rewardsClaimed[comet][users[i]] = claimedAmounts[i];
            emit RewardsClaimedSet(users[i], comet, claimedAmounts[i]);
            unchecked { i++; }
        }
    }

    /**
     * @notice 从合约中提取代币
     * @dev 仅治理地址可调用
     * @dev 用于：
     * @dev - 补充奖励代币
     * @dev - 提取多余的代币
     * @dev - 应急情况下的资金转移
     * 
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    function withdrawToken(address token, address to, uint amount) external {
        if (msg.sender != governor) revert NotPermitted(msg.sender);

        doTransferOut(token, to, amount);
    }

    /**
     * @notice 将治理权转移给新地址
     * @dev 仅当前治理地址可调用
     * @param newGovernor 新治理地址
     */
    function transferGovernor(address newGovernor) external {
        if (msg.sender != governor) revert NotPermitted(msg.sender);

        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorTransferred(oldGovernor, newGovernor);
    }

    // ============ 奖励查询和领取 ============

    /**
     * @notice 计算账户应得的奖励数量
     * @dev 会触发账户的利息和奖励累积
     * @dev 公式：应得 = 累积奖励 - 已领取奖励
     * 
     * @param comet 协议实例地址
     * @param account 要查询的账户地址
     * @return RewardOwed 结构体（包含代币地址和应得数量）
     */
    function getRewardOwed(address comet, address account) external returns (RewardOwed memory) {
        RewardConfig memory config = rewardConfig[comet];
        // 检查 Comet 是否已配置奖励
        if (config.token == address(0)) revert NotSupported(comet);

        // 触发累积，更新最新的奖励数据
        CometInterface(comet).accrueAccount(account);

        // 获取已领取和累积的奖励
        uint claimed = rewardsClaimed[comet][account];
        uint accrued = getRewardAccrued(comet, account, config);

        // 计算应得奖励（防止下溢）
        uint owed = accrued > claimed ? accrued - claimed : 0;
        return RewardOwed(config.token, owed);
    }

    /**
     * @notice 领取奖励到自己的地址
     * @dev 任何人都可以为自己领取奖励
     * 
     * @param comet 协议实例地址
     * @param src 奖励所有者地址
     * @param shouldAccrue 是否先触发累积（建议为 true）
     */
    function claim(address comet, address src, bool shouldAccrue) external {
        claimInternal(comet, src, src, shouldAccrue);
    }

    /**
     * @notice 领取奖励到指定地址
     * @dev 需要 src 地址的授权
     * @dev 用途：
     * @dev - 第三方代领奖励
     * @dev - 智能合约自动化领取
     * @dev - 奖励直接转给其他地址
     * 
     * @param comet 协议实例地址
     * @param src 奖励所有者地址
     * @param to 接收奖励的地址
     * @param shouldAccrue 是否先触发累积（建议为 true）
     */
    function claimTo(address comet, address src, address to, bool shouldAccrue) external {
        // 权限检查：调用者必须得到 src 的授权
        if (!CometInterface(comet).hasPermission(src, msg.sender)) revert NotPermitted(msg.sender);

        claimInternal(comet, src, to, shouldAccrue);
    }

    /**
     * @dev 内部领取函数（假设已通过权限检查）
     * @dev 领取流程：
     * @dev 1. 可选地触发累积
     * @dev 2. 计算应得奖励
     * @dev 3. 如果有奖励，更新已领取记录并转账
     * 
     * @param comet 协议实例地址
     * @param src 奖励所有者地址
     * @param to 接收奖励的地址
     * @param shouldAccrue 是否先触发累积
     */
    function claimInternal(address comet, address src, address to, bool shouldAccrue) internal {
        RewardConfig memory config = rewardConfig[comet];
        // 检查 Comet 是否已配置奖励
        if (config.token == address(0)) revert NotSupported(comet);

        // 可选地触发累积，获取最新奖励
        if (shouldAccrue) {
            CometInterface(comet).accrueAccount(src);
        }

        // 获取已领取和累积的奖励
        uint claimed = rewardsClaimed[comet][src];
        uint accrued = getRewardAccrued(comet, src, config);

        // 如果有未领取的奖励
        if (accrued > claimed) {
            uint owed = accrued - claimed;
            // 更新已领取记录
            rewardsClaimed[comet][src] = accrued;
            // 转账奖励代币
            doTransferOut(config.token, to, owed);

            emit RewardClaimed(src, to, config.token, owed);
        }
    }

    // ============ 内部辅助函数 ============

    /**
     * @dev 计算账户在 Comet 部署上累积的奖励
     * @dev 奖励计算公式（分三步）：
     * @dev 1. 从 Comet 获取原始累积值（BASE_ACCRUAL_SCALE 单位）
     * @dev 2. 根据精度差异进行缩放：
     * @dev    - 如果需要放大：accrued × rescaleFactor
     * @dev    - 如果需要缩小：accrued ÷ rescaleFactor
     * @dev 3. 应用倍数：result × multiplier / FACTOR_SCALE
     * 
     * @param comet 协议实例地址
     * @param account 账户地址
     * @param config 奖励配置
     * @return 最终计算的奖励数量（奖励代币单位）
     * 
     * @dev 示例计算：
     * @dev 假设 accrued = 1000000 (1e6 单位)
     * @dev 如果奖励是 COMP (18 decimals)：
     * @dev   rescaleFactor = 1e18 / 1e6 = 1e12
     * @dev   shouldUpscale = true
     * @dev   result = 1000000 × 1e12 × 1e18 / 1e18 = 1e18 (1 COMP)
     */
    function getRewardAccrued(address comet, address account, RewardConfig memory config) internal view returns (uint) {
        // 1. 获取原始累积值（BASE_ACCRUAL_SCALE 单位）
        uint accrued = CometInterface(comet).baseTrackingAccrued(account);

        // 2. 精度转换
        if (config.shouldUpscale) {
            // 放大：累积精度 < 代币精度
            accrued *= config.rescaleFactor;
        } else {
            // 缩小：累积精度 > 代币精度
            accrued /= config.rescaleFactor;
        }
        
        // 3. 应用奖励倍数
        // multiplier = 1e18 表示 100% (1.0)
        // multiplier = 0.5e18 表示 50% (0.5)
        return accrued * config.multiplier / FACTOR_SCALE;
    }

    /**
     * @dev 安全的 ERC20 代币转出
     * @dev 检查转账是否成功，失败则回滚
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 转账数量
     */
    function doTransferOut(address token, address to, uint amount) internal {
        bool success = ERC20(token).transfer(to, amount);
        if (!success) revert TransferOutFailed(to, amount);
    }

    /**
     * @dev 安全地将 uint256 转换为 uint64
     * @dev 如果数值超过 uint64 最大值则回滚
     * @param n 要转换的数值
     * @return uint64 类型的值
     */
    function safe64(uint n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64(n);
        return uint64(n);
    }
}