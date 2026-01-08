// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometCore.sol";

/**
 * @title Compound's Comet Main Interface (without Ext)
 * @title Compound Comet 主接口（不包含扩展功能）
 * @notice An efficient monolithic money market protocol
 * @notice 一个高效的单体化货币市场协议
 * @dev 定义了 Comet 主合约的所有错误、事件和函数接口
 * @dev 实际实现在 Comet.sol 中
 * @author Compound
 */
abstract contract CometMainInterface is CometCore {
    // ============ 自定义错误 ============
    // 使用自定义错误比 require 字符串更节省 gas
    
    /// @dev 参数值不合理或超出预期范围
    error Absurd();
    /// @dev 合约存储已经初始化，不能重复初始化
    error AlreadyInitialized();
    /// @dev 资产地址无效或不支持
    error BadAsset();
    /// @dev 代币小数位数不符合要求
    error BadDecimals();
    /// @dev 折扣因子（storeFrontPriceFactor）配置不当
    error BadDiscount();
    /// @dev 最小值参数（如 baseMinForRewards）配置不当
    error BadMinimum();
    /// @dev 价格预言机返回的价格无效（如负数或零）
    error BadPrice();
    /// @dev 借贷金额小于最小借贷要求（baseBorrowMin）
    error BorrowTooSmall();
    /// @dev 借贷抵押因子过大（≥ 清算抵押因子）
    error BorrowCFTooLarge();
    /// @dev 协议储备金不足，无法完成操作
    error InsufficientReserves();
    /// @dev 清算抵押因子过大（> 100%）
    error LiquidateCFTooLarge();
    /// @dev 不允许向自己转账
    error NoSelfTransfer();
    /// @dev 账户抵押品不足，无法借贷
    error NotCollateralized();
    /// @dev 抵押品暂不出售（储备金未达到目标）
    error NotForSale();
    /// @dev 账户不满足清算条件（抵押率充足）
    error NotLiquidatable();
    /// @dev 该操作已被暂停
    error Paused();
    /// @dev 检测到重入攻击，阻止执行
    error ReentrantCallBlocked();
    /// @dev 供应量超过该资产的供应上限
    error SupplyCapExceeded();
    /// @dev 时间戳值过大，无法转换为 uint40
    error TimestampTooLarge();
    /// @dev 资产数量超过最大支持数（15）
    error TooManyAssets();
    /// @dev 滑点过大，实际获得的抵押品少于最小要求
    error TooMuchSlippage();
    /// @dev 代币转入失败
    error TransferInFailed();
    /// @dev 代币转出失败
    error TransferOutFailed();
    /// @dev 未授权操作，调用者无权限
    error Unauthorized();

    // ============ 事件 ============

    /// @notice 供应基础资产事件
    /// @param from 资产来源地址
    /// @param dst 接收供应余额的目标地址
    /// @param amount 供应数量
    event Supply(address indexed from, address indexed dst, uint amount);

    /// @notice 转账基础资产事件（ERC20 兼容）
    /// @param from 转出地址
    /// @param to 接收地址
    /// @param amount 转账数量
    event Transfer(address indexed from, address indexed to, uint amount);

    /// @notice 提现基础资产事件
    /// @param src 提现的账户地址
    /// @param to 接收资产的地址
    /// @param amount 提现数量
    event Withdraw(address indexed src, address indexed to, uint amount);

    /// @notice 供应抵押品事件
    /// @param from 抵押品来源地址
    /// @param dst 接收抵押品余额的目标地址
    /// @param asset 抵押品资产地址
    /// @param amount 供应数量
    event SupplyCollateral(address indexed from, address indexed dst, address indexed asset, uint amount);

    /// @notice 转移抵押品事件
    /// @param from 转出地址
    /// @param to 接收地址
    /// @param asset 抵押品资产地址
    /// @param amount 转移数量
    event TransferCollateral(address indexed from, address indexed to, address indexed asset, uint amount);

    /// @notice 提现抵押品事件
    /// @param src 提现的账户地址
    /// @param to 接收抵押品的地址
    /// @param asset 抵押品资产地址
    /// @param amount 提现数量
    event WithdrawCollateral(address indexed src, address indexed to, address indexed asset, uint amount);

    /// @notice 清算债务事件 - 当借款人的债务被协议吸收时触发
    /// @param absorber 执行清算的地址
    /// @param borrower 被清算的借款人地址
    /// @param basePaidOut 协议支付的基础资产数量（吸收的债务）
    /// @param usdValue 债务的 USD 价值
    event AbsorbDebt(address indexed absorber, address indexed borrower, uint basePaidOut, uint usdValue);

    /// @notice 清算抵押品事件 - 当借款人的抵押品被协议吸收时触发
    /// @param absorber 执行清算的地址
    /// @param borrower 被清算的借款人地址
    /// @param asset 被吸收的抵押品资产地址
    /// @param collateralAbsorbed 被吸收的抵押品数量
    /// @param usdValue 抵押品的 USD 价值
    event AbsorbCollateral(address indexed absorber, address indexed borrower, address indexed asset, uint collateralAbsorbed, uint usdValue);

    /// @notice 购买抵押品事件 - 当有人从协议购买清算后的抵押品时触发
    /// @param buyer 购买者地址
    /// @param asset 购买的抵押品资产地址
    /// @param baseAmount 支付的基础资产数量
    /// @param collateralAmount 获得的抵押品数量
    event BuyCollateral(address indexed buyer, address indexed asset, uint baseAmount, uint collateralAmount);

    /// @notice 暂停/恢复操作事件 - 当协议功能被暂停或恢复时触发
    /// @param supplyPaused 供应是否被暂停
    /// @param transferPaused 转账是否被暂停
    /// @param withdrawPaused 提现是否被暂停
    /// @param absorbPaused 清算是否被暂停
    /// @param buyPaused 购买抵押品是否被暂停
    event PauseAction(bool supplyPaused, bool transferPaused, bool withdrawPaused, bool absorbPaused, bool buyPaused);

    /// @notice 提取储备金事件 - 当治理地址提取协议储备金时触发
    /// @param to 接收储备金的地址
    /// @param amount 提取的储备金数量
    event WithdrawReserves(address indexed to, uint amount);

    // ============ 核心功能函数 ============

    /// @notice 供应资产到自己的账户
    /// @param asset 资产地址（基础资产或抵押品）
    /// @param amount 供应数量
    function supply(address asset, uint amount) virtual external;

    /// @notice 供应资产到指定账户
    /// @param dst 接收供应余额的目标地址
    /// @param asset 资产地址（基础资产或抵押品）
    /// @param amount 供应数量
    function supplyTo(address dst, address asset, uint amount) virtual external;

    /// @notice 从指定账户供应资产到另一个账户
    /// @dev 需要 from 地址的授权
    /// @param from 资产来源地址
    /// @param dst 接收供应余额的目标地址
    /// @param asset 资产地址（基础资产或抵押品）
    /// @param amount 供应数量
    function supplyFrom(address from, address dst, address asset, uint amount) virtual external;

    /// @notice 转账基础资产（ERC20 标准）
    /// @param dst 接收地址
    /// @param amount 转账数量
    /// @return 操作是否成功
    function transfer(address dst, uint amount) virtual external returns (bool);

    /// @notice 从指定账户转账基础资产（ERC20 标准）
    /// @dev 需要 src 地址的授权
    /// @param src 转出地址
    /// @param dst 接收地址
    /// @param amount 转账数量
    /// @return 操作是否成功
    function transferFrom(address src, address dst, uint amount) virtual external returns (bool);

    /// @notice 转移资产（基础资产或抵押品）
    /// @param dst 接收地址
    /// @param asset 资产地址
    /// @param amount 转移数量
    function transferAsset(address dst, address asset, uint amount) virtual external;

    /// @notice 从指定账户转移资产到另一个账户
    /// @dev 需要 src 地址的授权
    /// @param src 转出地址
    /// @param dst 接收地址
    /// @param asset 资产地址
    /// @param amount 转移数量
    function transferAssetFrom(address src, address dst, address asset, uint amount) virtual external;

    /// @notice 从自己账户提现资产
    /// @dev 如果提现基础资产超过供应量，则进入借贷模式
    /// @param asset 资产地址（基础资产或抵押品）
    /// @param amount 提现数量
    function withdraw(address asset, uint amount) virtual external;

    /// @notice 从自己账户提现资产到指定地址
    /// @param to 接收资产的地址
    /// @param asset 资产地址
    /// @param amount 提现数量
    function withdrawTo(address to, address asset, uint amount) virtual external;

    /// @notice 从指定账户提现资产
    /// @dev 需要 src 地址的授权
    /// @param src 提现的账户地址
    /// @param to 接收资产的地址
    /// @param asset 资产地址
    /// @param amount 提现数量
    function withdrawFrom(address src, address to, address asset, uint amount) virtual external;

    /// @notice 授权管理者操作特定资产
    /// @dev 用于特殊授权场景
    /// @param manager 被授权的管理者地址
    /// @param asset 资产地址
    /// @param amount 授权金额
    function approveThis(address manager, address asset, uint amount) virtual external;

    /// @notice 提取协议储备金（仅治理地址可调用）
    /// @param to 接收储备金的地址
    /// @param amount 提取金额
    function withdrawReserves(address to, uint amount) virtual external;

    // ============ 清算功能 ============

    /// @notice 清算一个或多个账户
    /// @dev 协议会吸收账户的债务和抵押品
    /// @param absorber 执行清算的地址（记录在清算人积分中）
    /// @param accounts 要清算的账户地址数组
    function absorb(address absorber, address[] calldata accounts) virtual external;

    /// @notice 从协议购买清算后的抵押品
    /// @dev 使用基础资产购买，价格有折扣（storeFrontPriceFactor）
    /// @param asset 要购买的抵押品资产地址
    /// @param minAmount 最小接受的抵押品数量（滑点保护）
    /// @param baseAmount 支付的基础资产数量
    /// @param recipient 接收抵押品的地址
    function buyCollateral(address asset, uint minAmount, uint baseAmount, address recipient) virtual external;

    /// @notice 计算用指定数量的基础资产可以购买多少抵押品
    /// @param asset 抵押品资产地址
    /// @param baseAmount 基础资产数量
    /// @return 可购买的抵押品数量
    function quoteCollateral(address asset, uint baseAmount) virtual public view returns (uint);

    // ============ 查询函数 ============

    /// @notice 通过索引获取资产信息
    /// @param i 资产索引（0 到 numAssets-1）
    /// @return 资产信息结构体
    function getAssetInfo(uint8 i) virtual public view returns (AssetInfo memory);

    /// @notice 通过地址获取资产信息
    /// @param asset 资产地址
    /// @return 资产信息结构体
    function getAssetInfoByAddress(address asset) virtual public view returns (AssetInfo memory);

    /// @notice 获取协议持有的抵押品储备量
    /// @param asset 抵押品资产地址
    /// @return 储备量
    function getCollateralReserves(address asset) virtual public view returns (uint);

    /// @notice 获取协议的基础资产储备金
    /// @dev 正值表示盈余，负值表示赤字
    /// @return 储备金（有符号整数）
    function getReserves() virtual public view returns (int);

    /// @notice 从价格预言机获取资产价格
    /// @param priceFeed 价格预言机地址
    /// @return 价格（8 位小数）
    function getPrice(address priceFeed) virtual public view returns (uint);

    /// @notice 检查账户的借贷是否有足够抵押
    /// @dev 使用 borrowCollateralFactor 计算
    /// @param account 账户地址
    /// @return 如果抵押充足返回 true
    function isBorrowCollateralized(address account) virtual public view returns (bool);

    /// @notice 检查账户是否可被清算
    /// @dev 使用 liquidateCollateralFactor 计算
    /// @param account 账户地址
    /// @return 如果可清算返回 true
    function isLiquidatable(address account) virtual public view returns (bool);

    /// @notice 获取市场总供应量（ERC20 标准）
    /// @dev 基础资产的总供应量（当前价值）
    /// @return 总供应量
    function totalSupply() virtual external view returns (uint256);

    /// @notice 获取市场总借贷量
    /// @dev 基础资产的总借贷量（当前价值）
    /// @return 总借贷量
    function totalBorrow() virtual external view returns (uint256);

    /// @notice 获取账户的供应余额（ERC20 标准）
    /// @dev 基础资产的供应余额（当前价值）
    /// @param owner 账户地址
    /// @return 供应余额
    function balanceOf(address owner) virtual public view returns (uint256);

    /// @notice 获取账户的借贷余额
    /// @dev 基础资产的借贷余额（当前价值）
    /// @param account 账户地址
    /// @return 借贷余额
    function borrowBalanceOf(address account) virtual public view returns (uint256);

    // ============ 暂停控制 ============

    /// @notice 暂停或恢复协议功能（仅 pauseGuardian 或 governor 可调用）
    /// @param supplyPaused 是否暂停供应
    /// @param transferPaused 是否暂停转账
    /// @param withdrawPaused 是否暂停提现
    /// @param absorbPaused 是否暂停清算
    /// @param buyPaused 是否暂停购买抵押品
    function pause(bool supplyPaused, bool transferPaused, bool withdrawPaused, bool absorbPaused, bool buyPaused) virtual external;

    /// @notice 检查供应是否被暂停
    function isSupplyPaused() virtual public view returns (bool);

    /// @notice 检查转账是否被暂停
    function isTransferPaused() virtual public view returns (bool);

    /// @notice 检查提现是否被暂停
    function isWithdrawPaused() virtual public view returns (bool);

    /// @notice 检查清算是否被暂停
    function isAbsorbPaused() virtual public view returns (bool);

    /// @notice 检查购买抵押品是否被暂停
    function isBuyPaused() virtual public view returns (bool);

    // ============ 利率和累积 ============

    /// @notice 手动触发账户的利息和奖励累积
    /// @param account 账户地址
    function accrueAccount(address account) virtual external;

    /// @notice 根据资金利用率计算供应利率
    /// @param utilization 资金利用率（FACTOR_SCALE 单位）
    /// @return 每秒供应利率（uint64）
    function getSupplyRate(uint utilization) virtual public view returns (uint64);

    /// @notice 根据资金利用率计算借贷利率
    /// @param utilization 资金利用率（FACTOR_SCALE 单位）
    /// @return 每秒借贷利率（uint64）
    function getBorrowRate(uint utilization) virtual public view returns (uint64);

    /// @notice 获取当前市场的资金利用率
    /// @dev 利用率 = 总借贷量 / 总供应量
    /// @return 资金利用率（FACTOR_SCALE 单位）
    function getUtilization() virtual public view returns (uint);

    // ============ 配置获取函数 ============

    /// @notice 获取治理地址
    /// @return 治理地址
    function governor() virtual external view returns (address);

    /// @notice 获取暂停守护者地址
    /// @return 暂停守护者地址
    function pauseGuardian() virtual external view returns (address);

    /// @notice 获取基础借贷资产地址
    /// @return 基础资产地址
    function baseToken() virtual external view returns (address);

    /// @notice 获取基础资产的价格预言机地址
    /// @return 价格预言机地址
    function baseTokenPriceFeed() virtual external view returns (address);

    /// @notice 获取扩展合约代理地址
    /// @return 扩展合约地址
    function extensionDelegate() virtual external view returns (address);

    // === 供应利率模型参数 ===

    /// @notice 获取供应利率拐点
    /// @dev 实际类型为 uint64，返回 uint 以保持接口简洁
    /// @return 拐点值（FACTOR_SCALE 单位）
    function supplyKink() virtual external view returns (uint);

    /// @notice 获取供应利率低斜率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 低斜率值
    function supplyPerSecondInterestRateSlopeLow() virtual external view returns (uint);

    /// @notice 获取供应利率高斜率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 高斜率值
    function supplyPerSecondInterestRateSlopeHigh() virtual external view returns (uint);

    /// @notice 获取供应基础利率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 基础利率值
    function supplyPerSecondInterestRateBase() virtual external view returns (uint);

    // === 借贷利率模型参数 ===

    /// @notice 获取借贷利率拐点
    /// @dev 实际类型为 uint64
    /// @return 拐点值（FACTOR_SCALE 单位）
    function borrowKink() virtual external view returns (uint);

    /// @notice 获取借贷利率低斜率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 低斜率值
    function borrowPerSecondInterestRateSlopeLow() virtual external view returns (uint);

    /// @notice 获取借贷利率高斜率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 高斜率值
    function borrowPerSecondInterestRateSlopeHigh() virtual external view returns (uint);

    /// @notice 获取借贷基础利率（每秒）
    /// @dev 实际类型为 uint64
    /// @return 基础利率值
    function borrowPerSecondInterestRateBase() virtual external view returns (uint);

    /// @notice 获取清算折扣因子
    /// @dev 实际类型为 uint64，购买抵押品时的价格折扣
    /// @return 折扣因子（FACTOR_SCALE 单位）
    function storeFrontPriceFactor() virtual external view returns (uint);

    // === 精度和缩放参数 ===

    /// @notice 获取基础资产的缩放因子
    /// @dev 实际类型为 uint64，等于 10^decimals
    /// @return 缩放因子
    function baseScale() virtual external view returns (uint);

    /// @notice 获取奖励追踪索引的缩放因子
    /// @dev 实际类型为 uint64，不可更改
    /// @return 追踪索引缩放因子
    function trackingIndexScale() virtual external view returns (uint);

    // === 奖励参数 ===

    /// @notice 获取供应奖励速度（每秒）
    /// @dev 实际类型为 uint64
    /// @return 供应奖励速度
    function baseTrackingSupplySpeed() virtual external view returns (uint);

    /// @notice 获取借贷奖励速度（每秒）
    /// @dev 实际类型为 uint64
    /// @return 借贷奖励速度
    function baseTrackingBorrowSpeed() virtual external view returns (uint);

    /// @notice 获取获得奖励的最小本金要求
    /// @dev 实际类型为 uint104
    /// @return 最小本金
    function baseMinForRewards() virtual external view returns (uint);

    // === 协议参数 ===

    /// @notice 获取最小借贷金额要求
    /// @dev 实际类型为 uint104，防止过小的借贷位置
    /// @return 最小借贷金额
    function baseBorrowMin() virtual external view returns (uint);

    /// @notice 获取目标储备金
    /// @dev 实际类型为 uint104，超过此值才能购买抵押品
    /// @return 目标储备金
    function targetReserves() virtual external view returns (uint);

    /// @notice 获取支持的抵押资产数量
    /// @return 资产数量（最多 15）
    function numAssets() virtual external view returns (uint8);

    /// @notice 获取基础资产的小数位数
    /// @dev ERC20 标准
    /// @return 小数位数
    function decimals() virtual external view returns (uint8);

    // ============ 初始化 ============

    /// @notice 初始化合约存储
    /// @dev 只能调用一次，设置初始指数和时间戳
    function initializeStorage() virtual external;
}
}