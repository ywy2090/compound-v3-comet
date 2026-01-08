# Compound Comet 可配置参数完整指南

## 目录
1. [参数分类概览](#一参数分类概览)
2. [不可更改参数](#二不可更改参数)
3. [治理可更改参数](#三治理可更改参数)
4. [资产配置参数](#四资产配置参数)
5. [实际配置示例](#五实际配置示例)
6. [配置修改流程](#六配置修改流程)
7. [安全限制与最佳实践](#七安全限制与最佳实践)

---

## 一、参数分类概览

### 1.1 参数可变性分类

```
┌─────────────────────────────────────────────────────────┐
│              Comet 配置参数全景图                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  🔒 不可更改参数（Immutable）                             │
│     └─ baseToken                基础资产地址             │
│     └─ trackingIndexScale       奖励索引缩放             │
│     └─ baseScale                基础资产精度             │
│     └─ decimals                 小数位数                │
│                                                         │
│  ⚙️ 治理可更改参数（Governor Only）                       │
│     ├─ 权限管理                                          │
│     │  ├─ governor              治理地址                │
│     │  └─ pauseGuardian         暂停守护者              │
│     ├─ 预言机                                            │
│     │  ├─ baseTokenPriceFeed    基础资产价格源          │
│     │  └─ extensionDelegate     扩展合约地址            │
│     ├─ 清算参数                                          │
│     │  ├─ storeFrontPriceFactor 清算折扣因子            │
│     │  ├─ baseMinForRewards     奖励最小值              │
│     │  └─ targetReserves        目标储备金              │
│     └─ 资产管理                                          │
│        ├─ addAsset              添加新抵押品             │
│        ├─ updateAsset           更新抵押品配置           │
│        └─ updateAssetPriceFeed  更新价格源              │
│                                                         │
│  🔧 治理或市场管理员可更改（Governor or Market Admin）      │
│     ├─ 利率模型                                          │
│     │  ├─ supplyKink            供应拐点                │
│     │  ├─ supplyPerYear*        供应利率参数 (4个)      │
│     │  ├─ borrowKink            借贷拐点                │
│     │  └─ borrowPerYear*        借贷利率参数 (4个)      │
│     ├─ 奖励速度                                          │
│     │  ├─ baseTrackingSupplySpeed 供应奖励速度          │
│     │  └─ baseTrackingBorrowSpeed 借贷奖励速度          │
│     ├─ 借贷限制                                          │
│     │  └─ baseBorrowMin         最小借贷金额            │
│     └─ 资产风控参数                                      │
│        ├─ borrowCollateralFactor    借贷抵押率          │
│        ├─ liquidateCollateralFactor 清算阈值            │
│        ├─ liquidationFactor         清算惩罚            │
│        └─ supplyCap                 供应上限            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 1.2 权限级别说明

| 权限级别 | 角色 | 可修改参数 | 说明 |
|---------|------|-----------|------|
| **Level 1** | Governor（治理） | 全部参数 | 最高权限，通过治理投票修改 |
| **Level 2** | Market Admin（市场管理员） | 利率、奖励、风控参数 | 快速响应市场变化 |
| **Level 3** | Pause Guardian（守护者） | 仅暂停功能 | 应急暂停，无法修改参数 |

---

## 二、不可更改参数

### 2.1 基础资产参数

这些参数在合约部署时设置，**之后永远无法修改**。

#### `baseToken` - 基础资产地址

```solidity
// 合约地址：不可更改
address public immutable baseToken;
```

**说明**：
- 协议的核心借贷资产（如 USDC、USDT、DAI）
- 用户借出和偿还的资产
- 一旦设置永不改变

**实际值示例**：
```
Mainnet USDC Market: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
Mainnet WETH Market: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 (WETH)
```

**为什么不可更改？**
- 整个协议的会计系统依赖此资产
- 更改会导致所有用户余额错乱
- 如需新资产，必须部署新市场

---

#### `trackingIndexScale` - 奖励索引缩放因子

```solidity
uint64 public immutable trackingIndexScale;
```

**说明**：
- 奖励追踪的精度单位
- 影响奖励计算的数值范围
- 通常设为 `1e15`

**作用**：
```solidity
// 奖励累积计算
trackingSupplyIndex += safe64(divBaseWei(
    baseTrackingSupplySpeed * timeElapsed,
    totalSupplyBase
));

// 用户奖励计算
uint indexDelta = trackingSupplyIndex - user.baseTrackingIndex;
uint rewardAccrued = principal * indexDelta / trackingIndexScale;
```

**为什么不可更改？**
- 更改会导致所有历史奖励计算错误
- 影响所有用户的奖励余额

---

#### `decimals` 和 `baseScale` - 资产精度

```solidity
uint8 public immutable decimals;        // 例如：6 (USDC)
uint64 public immutable baseScale;      // 10^decimals = 1e6 (USDC)
```

**说明**：
- 从 `baseToken` 合约自动读取
- 用于所有金额计算的精度转换
- 不同资产有不同精度：
  - USDC/USDT: 6 decimals
  - WETH/DAI: 18 decimals

---

### 2.2 派生的不可变参数

#### `accrualDescaleFactor` - 累积降尺度因子

```solidity
uint internal immutable accrualDescaleFactor;

// 计算：baseScale / BASE_ACCRUAL_SCALE
// 如果 USDC (1e6 / 1e6 = 1)
// 如果 WETH (1e18 / 1e6 = 1e12)
```

**作用**：
- 统一不同精度资产的累积计算
- 内部使用 `BASE_ACCRUAL_SCALE = 1e6` 作为标准单位

---

## 三、治理可更改参数

### 3.1 权限管理参数

#### `governor` - 治理地址

```solidity
address public immutable governor;
```

**修改方法**：
```solidity
// Configurator.sol
function setGovernor(address cometProxy, address newGovernor) external;
```

**权限**：只有当前 governor

**说明**：
- 拥有最高权限的地址
- 通常是治理合约（Timelock）
- 可以修改所有可配置参数

**实际值**：
```
Mainnet: 0x6d903f6003cca6255D85CcA4D3B5E5146dC33925 (Compound Timelock)
```

**修改示例**：
```javascript
// 通过治理提案修改
const proposal = {
    targets: [configuratorAddress],
    values: [0],
    signatures: ["setGovernor(address,address)"],
    calldatas: [
        ethers.utils.defaultAbiCoder.encode(
            ['address', 'address'],
            [cometProxyAddress, newGovernorAddress]
        )
    ]
};
```

---

#### `pauseGuardian` - 暂停守护者

```solidity
address public immutable pauseGuardian;
```

**修改方法**：
```solidity
function setPauseGuardian(address cometProxy, address newPauseGuardian) external;
```

**权限**：只有 governor

**说明**：
- 可以快速暂停协议功能
- **只能暂停，不能恢复**（防止滥用）
- 通常是多签钱包或 EOA

**实际值**：
```
Mainnet: 0xbbf3f1421D886E9b2c5D716B5192aC998af2012c
```

---

### 3.2 预言机参数

#### `baseTokenPriceFeed` - 基础资产价格源

```solidity
address public immutable baseTokenPriceFeed;
```

**修改方法**：
```solidity
function setBaseTokenPriceFeed(address cometProxy, address newPriceFeed) external;
```

**权限**：只有 governor

**说明**：
- 提供基础资产的 USD 价格
- 必须实现 `IPriceFeed` 接口
- 返回 8 位小数的价格

**价格源类型**：
1. **Chainlink 聚合器**
   ```
   USDC: 通常是常量 $1.00
   ETH: Chainlink ETH/USD
   ```

2. **自定义价格源**
   ```
   ConstantPriceFeed: 返回固定值（稳定币）
   WstETHPriceFeed: wstETH 特殊计算
   ```

**实际值示例**：
```
USDC Market: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6 (Chainlink USDC/USD)
WETH Market: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Chainlink ETH/USD)
```

---

#### `extensionDelegate` - 扩展合约地址

```solidity
address public immutable extensionDelegate;
```

**修改方法**：
```solidity
function setExtensionDelegate(address cometProxy, address newExtensionDelegate) external;
```

**权限**：只有 governor

**说明**：
- 指向 `CometExt.sol` 实现合约
- 通过 `delegatecall` 调用扩展功能
- 包含 ERC20 接口、签名授权等

**为什么可以更改？**
- 可以升级扩展功能
- 不影响核心存储
- 共享存储空间

---

### 3.3 清算与奖励参数

#### `storeFrontPriceFactor` - 清算折扣因子

```solidity
uint64 public immutable storeFrontPriceFactor;
```

**修改方法**：
```solidity
function setStoreFrontPriceFactor(address cometProxy, uint64 newFactor) external;
```

**权限**：只有 governor

**说明**：
- 清算人购买抵押品时的价格折扣
- 单位：`FACTOR_SCALE = 1e18`
- 典型值：`0.93e18` (7% 折扣)

**折扣计算**：
```solidity
// 最终折扣 = storeFrontPriceFactor × (1 - liquidationFactor)
uint256 discountFactor = mulFactor(
    storeFrontPriceFactor,           // 0.93
    FACTOR_SCALE - liquidationFactor // 1.0 - 0.95 = 0.05
);
// discountFactor = 0.93 × 0.05 = 0.0465 (4.65%)

uint256 discountedPrice = price * (1 - discountFactor);
// 如果 ETH = $2000
// discountedPrice = $2000 × 0.9535 = $1907
```

**实际值**：
```
大多数市场: 0.93e18 (93%, 即 7% 前端折扣)
```

---

#### `baseMinForRewards` - 奖励最小余额

```solidity
uint104 public immutable baseMinForRewards;
```

**修改方法**：
```solidity
function setBaseMinForRewards(address cometProxy, uint104 newMin) external;
```

**权限**：只有 governor

**说明**：
- 账户必须达到此余额才能获得奖励
- 防止小额账户消耗奖励预算
- 单位：基础资产的本金单位

**实际值示例**：
```
USDC Market: 100e6 (100 USDC，因为 USDC 是 6 decimals)
WETH Market: 0.01e18 (0.01 ETH)
```

**影响**：
```solidity
if (totalSupplyBase >= baseMinForRewards) {
    trackingSupplyIndex += calculateRewardIndex();
}
// 低于此值，奖励索引不更新
```

---

#### `targetReserves` - 目标储备金

```solidity
uint104 public immutable targetReserves;
```

**修改方法**：
```solidity
function setTargetReserves(address cometProxy, uint104 newTarget) external;
```

**权限**：只有 governor

**说明**：
- 协议希望保留的最低储备金
- 超过此值才允许购买清算的抵押品
- 保证协议偿付能力

**实际值示例**：
```
USDC Market: 5,000,000e6 (500万 USDC)
WETH Market: 1,000e18 (1000 ETH)
```

**作用**：
```solidity
function buyCollateral() external {
    int reserves = getReserves();
    if (reserves < targetReserves) {
        // 储备金不足，限制购买
    }
}
```

---

### 3.4 利率模型参数（治理或市场管理员）

Comet 使用**双斜率 Kink 利率模型**。

#### 供应利率参数

##### `supplyKink` - 供应利率拐点

```solidity
uint64 public immutable supplyKink;
```

**修改方法**：
```solidity
function setSupplyKink(address cometProxy, uint64 newKink) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 利率曲线的转折点（utilization 阈值）
- 单位：`FACTOR_SCALE = 1e18`
- 典型值：`0.80e18` (80% 利用率)

**利率模型图示**：
```
供应利率 APR (%)
    │
 6% │                    ╱
    │                  ╱
 4% │                ╱
    │              ╱
 2% │            ╱
    │          ╱
 1% │────────╱  ← Kink (80%)
    │      ╱
    │    ╱
    │  ╱
    └─────────────────────────→ 利用率 (%)
      0%   40%   80%   100%
           
    ↑ 低斜率区    ↑ 高斜率区
```

**计算公式**：
```solidity
function getSupplyRate(uint utilization) public view returns (uint64) {
    if (utilization <= supplyKink) {
        // 低于拐点：线性增长
        return supplyPerSecondInterestRateBase + 
               mulFactor(supplyPerSecondInterestRateSlopeLow, utilization);
    } else {
        // 高于拐点：陡峭增长
        return supplyPerSecondInterestRateBase + 
               mulFactor(supplyPerSecondInterestRateSlopeLow, supplyKink) +
               mulFactor(supplyPerSecondInterestRateSlopeHigh, utilization - supplyKink);
    }
}
```

---

##### `supplyPerYearInterestRateBase` - 基础供应利率

```solidity
uint64 public immutable supplyPerYearInterestRateBase;
```

**修改方法**：
```solidity
function setSupplyPerYearInterestRateBase(address cometProxy, uint64 newBase) external governorOrMarketAdmin;
```

**说明**：
- Y轴截距（0% 利用率时的利率）
- 年化利率，内部转换为每秒利率
- 单位：`FACTOR_SCALE = 1e18`
- 典型值：`0.01e18` (1% APR)

**转换**：
```solidity
// 构造函数中转换为每秒利率
supplyPerSecondInterestRateBase = supplyPerYearInterestRateBase / SECONDS_PER_YEAR;
// 0.01e18 / 31,536,000 = 317,097,919 (每秒)
```

---

##### `supplyPerYearInterestRateSlopeLow` - 低斜率

```solidity
uint64 public immutable supplyPerYearInterestRateSlopeLow;
```

**修改方法**：
```solidity
function setSupplyPerYearInterestRateSlopeLow(address cometProxy, uint64 newSlope) external governorOrMarketAdmin;
```

**说明**：
- 拐点之前的利率增长速度
- 单位：`FACTOR_SCALE = 1e18`
- 典型值：`0.03e18` (3% 年化)

**实际效果**：
```
在 80% kink 之前：
- 0% 利用率：1% APR (base)
- 40% 利用率：1% + (3% × 40% / 80%) = 2.5% APR
- 80% 利用率：1% + (3% × 80% / 80%) = 4% APR
```

---

##### `supplyPerYearInterestRateSlopeHigh` - 高斜率

```solidity
uint64 public immutable supplyPerYearInterestRateSlopeHigh;
```

**修改方法**：
```solidity
function setSupplyPerYearInterestRateSlopeHigh(address cometProxy, uint64 newSlope) external governorOrMarketAdmin;
```

**说明**：
- 拐点之后的利率增长速度
- 通常**远大于**低斜率
- 典型值：`0.40e18` (40% 年化)

**实际效果**：
```
在 80% kink 之后：
- 80% 利用率：4% APR
- 90% 利用率：4% + (40% × 10% / 20%) = 24% APR
- 100% 利用率：4% + (40% × 20% / 20%) = 44% APR
```

**为什么需要高斜率？**
- 激励用户在高利用率时供应更多资产
- 惩罚高利用率，保持流动性
- 防止协议资金耗尽

---

#### 借贷利率参数

借贷利率参数与供应利率类似，但数值更高：

- `borrowKink` - 借贷拐点（典型：0.80e18）
- `borrowPerYearInterestRateBase` - 基础借贷利率（典型：0.02e18 = 2%）
- `borrowPerYearInterestRateSlopeLow` - 低斜率（典型：0.05e18 = 5%）
- `borrowPerYearInterestRateSlopeHigh` - 高斜率（典型：0.90e18 = 90%）

**修改方法**：
```solidity
function setBorrowKink(address cometProxy, uint64 newKink) external governorOrMarketAdmin;
function setBorrowPerYearInterestRateBase(address cometProxy, uint64 newBase) external governorOrMarketAdmin;
function setBorrowPerYearInterestRateSlopeLow(address cometProxy, uint64 newSlope) external governorOrMarketAdmin;
function setBorrowPerYearInterestRateSlopeHigh(address cometProxy, uint64 newSlope) external governorOrMarketAdmin;
```

**借贷利率必须 > 供应利率**：
```
协议利差 = 借贷利率 - 供应利率

示例（50% 利用率）：
  借贷利率：5% APR
  供应利率：2.5% APR
  协议收入：50% × (5% - 2.5%) = 1.25% of total supply
```

---

### 3.5 奖励速度参数

#### `baseTrackingSupplySpeed` - 供应奖励速度

```solidity
uint64 public immutable baseTrackingSupplySpeed;
```

**修改方法**：
```solidity
function setBaseTrackingSupplySpeed(address cometProxy, uint64 newSpeed) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 每秒分配给供应者的奖励量
- 单位：奖励代币的内部单位（通常是基础资产单位）
- 会在 `CometRewards` 中转换为实际代币数量

**计算示例**：
```solidity
// 假设设置为每秒 100 单位（内部）
baseTrackingSupplySpeed = 100e6;  // 100 USDC 等价单位/秒

// 奖励索引更新
if (totalSupplyBase >= baseMinForRewards) {
    uint indexDelta = baseTrackingSupplySpeed * timeElapsed / totalSupplyBase;
    trackingSupplyIndex += indexDelta;
}

// 用户奖励累积
uint userIndexDelta = trackingSupplyIndex - user.baseTrackingIndex;
uint rewardAccrued = user.principal * userIndexDelta / trackingIndexScale;
```

**实际值示例**：
```
Mainnet USDC: ~15e6 (每秒约 15 USDC 等价的奖励)

每天奖励：15 × 86,400 = 1,296,000 (约 129.6万 单位/天)
每年奖励：15 × 31,536,000 = 473,040,000 (约 4.73亿 单位/年)
```

---

#### `baseTrackingBorrowSpeed` - 借贷奖励速度

```solidity
uint64 public immutable baseTrackingBorrowSpeed;
```

**修改方法**：
```solidity
function setBaseTrackingBorrowSpeed(address cometProxy, uint64 newSpeed) external governorOrMarketAdmin;
```

**说明**：
- 每秒分配给借款者的奖励量
- 通常**低于**供应奖励速度
- 激励借贷行为

**典型比例**：
```
supplySpeed : borrowSpeed ≈ 2:1 到 3:1

示例：
  baseTrackingSupplySpeed = 15e6 (15 单位/秒)
  baseTrackingBorrowSpeed = 8e6  (8 单位/秒)
  
  比例 = 15:8 ≈ 1.875:1
```

---

### 3.6 借贷限制参数

#### `baseBorrowMin` - 最小借贷金额

```solidity
uint104 public immutable baseBorrowMin;
```

**修改方法**：
```solidity
function setBaseBorrowMin(address cometProxy, uint104 newMin) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 用户的最小借贷金额
- 防止灰尘账户（dust accounts）
- 单位：基础资产单位

**实际值示例**：
```
USDC Market: 100e6 (100 USDC)
WETH Market: 0.05e18 (0.05 ETH)
```

**检查位置**：
```solidity
// Comet.sol
function withdrawBase(address src, address to, uint256 amount) internal {
    // ...
    if (srcBalance < 0) {
        if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
        // ...
    }
}
```

**为什么需要？**
1. **降低 gas 成本**：小额借贷不划算
2. **简化清算**：避免清算大量小额账户
3. **提高资本效率**：集中资源到大额借贷

---

## 四、资产配置参数

每个抵押资产都有独立的配置参数。

### 4.1 资产基本信息

#### `asset` - 资产地址

```solidity
address asset;
```

**说明**：
- 抵押品的 ERC20 合约地址
- 不可更改（添加后）

**实际值示例**：
```
WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
wstETH: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
cbETH: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
```

---

#### `priceFeed` - 价格预言机

```solidity
address priceFeed;
```

**修改方法**：
```solidity
function updateAssetPriceFeed(address cometProxy, address asset, address newPriceFeed) external;
```

**权限**：只有 governor

**说明**：
- 该资产的价格预言机地址
- 必须返回 8 位小数的 USD 价格

**实际值示例**：
```
WETH: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Chainlink ETH/USD)
wstETH: 自定义合约（wstETH 特殊计算逻辑）
```

---

#### `decimals` - 资产精度

```solidity
uint8 decimals;
```

**说明**：
- 资产的小数位数
- 必须与链上合约一致
- 不可更改

**常见值**：
```
WETH: 18
USDC: 6
WBTC: 8
```

---

### 4.2 风险控制参数

#### `borrowCollateralFactor` - 借贷抵押率

```solidity
uint64 borrowCollateralFactor;
```

**修改方法**：
```solidity
function updateAssetBorrowCollateralFactor(
    address cometProxy, 
    address asset, 
    uint64 newBorrowCF
) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 表示 $1 的抵押品可以借多少钱
- 单位：`FACTOR_SCALE = 1e18`
- 典型值：`0.70e18` - `0.85e18` (70% - 85%)

**实际值示例**：
```
WETH: 0.80e18 (80%)  - 相对稳定
wstETH: 0.78e18 (78%) - 考虑解绑风险
cbETH: 0.75e18 (75%)  - 新资产，较保守
LINK: 0.70e18 (70%)   - 波动较大
```

**借贷能力计算**：
```javascript
// 用户有 10 ETH @ $2000/ETH
const collateralValue = 10 * 2000; // $20,000
const borrowCF = 0.80;
const borrowingPower = collateralValue * borrowCF;
// = $20,000 × 0.80 = $16,000

console.log(`可借贷：$${borrowingPower}`);
```

**设定原则**：
- 波动性越高，因子越低
- 流动性越差，因子越低
- 新资产保守设置

---

#### `liquidateCollateralFactor` - 清算阈值

```solidity
uint64 liquidateCollateralFactor;
```

**修改方法**：
```solidity
function updateAssetLiquidateCollateralFactor(
    address cometProxy, 
    address asset, 
    uint64 newLiquidateCF
) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 触发清算的抵押率阈值
- **必须 > borrowCollateralFactor**（留有安全边际）
- 典型值：`0.75e18` - `0.90e18` (75% - 90%)

**实际值示例**：
```
WETH: 0.85e18 (85%)   borrowCF = 0.80, 差距 5%
wstETH: 0.83e18 (83%) borrowCF = 0.78, 差距 5%
cbETH: 0.80e18 (80%)  borrowCF = 0.75, 差距 5%
```

**清算判断**：
```solidity
function isLiquidatable(address account) public view returns (bool) {
    // 计算抵押品价值（应用 liquidateCollateralFactor）
    uint collateralValue = calculateCollateral(account, liquidateCollateralFactor);
    
    // 计算债务价值
    uint debtValue = calculateDebt(account);
    
    // 可清算条件
    return collateralValue < debtValue;
}
```

**实际场景**：
```
用户：
  抵押品：10 ETH @ $2000/ETH = $20,000
  债务：$15,000
  borrowCF：0.80
  liquidateCF：0.85

借贷能力：$20,000 × 0.80 = $16,000 ✓ (当前 $15,000 < $16,000)
清算阈值：$20,000 × 0.85 = $17,000 ✓ (当前 $15,000 < $17,000)

如果 ETH 跌到 $1,800：
  抵押品价值：10 × $1,800 = $18,000
  借贷能力：$18,000 × 0.80 = $14,400 ✗ (债务 $15,000 > $14,400，无法新借贷)
  清算阈值：$18,000 × 0.85 = $15,300 ✓ (债务 $15,000 < $15,300，尚未清算)
  
如果 ETH 跌到 $1,750：
  抵押品价值：10 × $1,750 = $17,500
  清算阈值：$17,500 × 0.85 = $14,875 ✗ (债务 $15,000 > $14,875，触发清算！)
```

**安全边际的重要性**：
```
borrowCF 到 liquidateCF 的缓冲区：
- 给用户时间补仓或还款
- 避免频繁的"边界"清算
- 保护协议免受闪电崩盘

典型差距：3% - 5%
```

---

#### `liquidationFactor` - 清算惩罚因子

```solidity
uint64 liquidationFactor;
```

**修改方法**：
```solidity
function updateAssetLiquidationFactor(
    address cometProxy, 
    address asset, 
    uint64 newLiquidationFactor
) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 清算时协议保留的抵押品价值比例
- 剩余部分用于偿还债务
- 典型值：`0.92e18` - `0.97e18` (92% - 97%)

**实际值示例**：
```
WETH: 0.95e18 (95%)    协议惩罚 5%
wstETH: 0.94e18 (94%)  协议惩罚 6%
cbETH: 0.93e18 (93%)   协议惩罚 7%（新资产更严格）
```

**清算价值计算**：
```solidity
// 被清算账户有 10 ETH @ $1,750/ETH
uint collateralValue = 10 * 1750; // $17,500

// 应用清算因子
uint valueForDebt = collateralValue * liquidationFactor / 1e18;
// = $17,500 × 0.95 = $16,625

// 协议惩罚
uint protocolPenalty = collateralValue - valueForDebt;
// = $17,500 - $16,625 = $875 (5%)
```

**惩罚分配**：
```
总抵押品价值：$17,500
├─ 协议惩罚：$875 (5%) → 协议储备金
└─ 偿债价值：$16,625 (95%)
   ├─ 偿还债务：$15,000
   └─ 剩余：$1,625 → 协议储备金（或再次出售）
```

**为什么需要惩罚？**
1. **激励借款人**：主动维护健康率
2. **协议收入**：补偿协议承担的风险
3. **清算激励**：配合 `storeFrontPriceFactor` 吸引清算人

---

#### `supplyCap` - 供应上限

```solidity
uint128 supplyCap;
```

**修改方法**：
```solidity
function updateAssetSupplyCap(
    address cometProxy, 
    address asset, 
    uint128 newSupplyCap
) external governorOrMarketAdmin;
```

**权限**：governor 或 market admin

**说明**：
- 该资产的最大供应量
- 防止单一资产风险过大
- 单位：资产的原生单位

**实际值示例**：
```
WETH: 200,000e18 (200,000 ETH)
wstETH: 50,000e18 (50,000 wstETH)
cbETH: 30,000e18 (30,000 cbETH)
LINK: 5,000,000e18 (500万 LINK)
```

**检查位置**：
```solidity
// Comet.sol
function supplyCollateral(address from, address dst, address asset, uint128 amount) internal {
    // ...
    uint128 totalSupplyAsset = totalsCollateral[asset].totalSupplyAsset;
    uint128 totalSupplyAssetNew = totalSupplyAsset + amount;
    
    if (totalSupplyAssetNew > assetInfo.supplyCap) {
        revert SupplyCapExceeded();
    }
    // ...
}
```

**为什么需要上限？**
1. **风险集中**：避免过度依赖单一资产
2. **预言机风险**：单一价格源失败影响有限
3. **流动性风险**：确保能够清算

**设定原则**：
```
考虑因素：
- 资产流动性（DEX 深度）
- 市场规模
- 协议风险偏好
- 资产稳定性

示例：
  主流资产（WETH）：较高上限
  新兴资产（cbETH）：较低上限
  长尾资产（LINK）：更低上限
```

---

## 五、实际配置示例

### 5.1 Mainnet USDC Market 完整配置

```javascript
const config = {
    // ========== 不可更改参数 ==========
    baseToken: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
    trackingIndexScale: 1e15,
    
    // ========== 权限管理 ==========
    governor: "0x6d903f6003cca6255D85CcA4D3B5E5146dC33925", // Timelock
    pauseGuardian: "0xbbf3f1421D886E9b2c5D716B5192aC998af2012c",
    
    // ========== 预言机 ==========
    baseTokenPriceFeed: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6", // Chainlink USDC/USD
    extensionDelegate: "0x285617313887d43256F852cAE0Ee4de4b68D45B0", // CometExt
    
    // ========== 供应利率模型 ==========
    supplyKink: 0.80e18,                           // 80%
    supplyPerYearInterestRateBase: 0.01e18,        // 1% APR
    supplyPerYearInterestRateSlopeLow: 0.03e18,    // 3% APR
    supplyPerYearInterestRateSlopeHigh: 0.40e18,   // 40% APR
    
    // ========== 借贷利率模型 ==========
    borrowKink: 0.80e18,                           // 80%
    borrowPerYearInterestRateBase: 0.02e18,        // 2% APR
    borrowPerYearInterestRateSlopeLow: 0.05e18,    // 5% APR
    borrowPerYearInterestRateSlopeHigh: 0.90e18,   // 90% APR
    
    // ========== 清算参数 ==========
    storeFrontPriceFactor: 0.93e18,                // 7% 前端折扣
    
    // ========== 奖励参数 ==========
    baseTrackingSupplySpeed: 15e6,                 // 15 USDC equiv/秒
    baseTrackingBorrowSpeed: 8e6,                  // 8 USDC equiv/秒
    baseMinForRewards: 1000e6,                     // 1000 USDC
    
    // ========== 借贷限制 ==========
    baseBorrowMin: 100e6,                          // 100 USDC
    targetReserves: 5_000_000e6,                   // 500万 USDC
    
    // ========== 抵押资产配置 ==========
    assetConfigs: [
        {
            // WETH
            asset: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            priceFeed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
            decimals: 18,
            borrowCollateralFactor: 0.80e18,       // 80%
            liquidateCollateralFactor: 0.85e18,    // 85%
            liquidationFactor: 0.95e18,            // 5% 惩罚
            supplyCap: 200_000e18,                 // 200,000 ETH
        },
        {
            // wstETH
            asset: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
            priceFeed: "0x...", // 自定义预言机
            decimals: 18,
            borrowCollateralFactor: 0.78e18,       // 78%
            liquidateCollateralFactor: 0.83e18,    // 83%
            liquidationFactor: 0.94e18,            // 6% 惩罚
            supplyCap: 50_000e18,                  // 50,000 wstETH
        },
        {
            // cbETH
            asset: "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
            priceFeed: "0x...",
            decimals: 18,
            borrowCollateralFactor: 0.75e18,       // 75%
            liquidateCollateralFactor: 0.80e18,    // 80%
            liquidationFactor: 0.93e18,            // 7% 惩罚
            supplyCap: 30_000e18,                  // 30,000 cbETH
        }
    ]
};
```

### 5.2 参数的典型值范围

| 参数 | 保守值 | 中等值 | 激进值 | 说明 |
|------|-------|-------|-------|------|
| **borrowCollateralFactor** | 0.65 | 0.75 | 0.85 | 越高风险越大 |
| **liquidateCollateralFactor** | 0.70 | 0.80 | 0.90 | 应 > borrowCF |
| **liquidationFactor** | 0.90 | 0.95 | 0.98 | 越高惩罚越小 |
| **supplyCap** | 小市值的10% | 中等流动性 | 大流动性 | 根据资产规模 |
| **supplyKink** | 0.70 | 0.80 | 0.90 | 影响利率曲线 |
| **borrowKink** | 0.70 | 0.80 | 0.90 | 通常与供应kink相同 |
| **storeFrontPriceFactor** | 0.90 | 0.93 | 0.96 | 影响清算激励 |

---

## 六、配置修改流程

### 6.1 治理提案流程

```
1. 提案创建
   ↓
2. 社区讨论（链下：论坛、Discord）
   ↓
3. 正式提案（链上：GovernorBravo）
   ↓
4. 投票期（通常 3 天）
   ↓
5. Timelock 延迟（通常 2 天）
   ↓
6. 执行修改
```

### 6.2 提案示例代码

#### 修改供应 Kink

```javascript
// 1. 编码调用数据
const configuratorABI = [...];
const configurator = new ethers.Contract(configuratorAddress, configuratorABI);

const calldata = configurator.interface.encodeFunctionData(
    "setSupplyKink",
    [
        cometProxyAddress,        // cometProxy
        ethers.utils.parseUnits("0.85", 18) // newSupplyKink = 85%
    ]
);

// 2. 创建提案
const proposal = {
    targets: [configuratorAddress],
    values: [0],
    signatures: ["setSupplyKink(address,uint64)"],
    calldatas: [calldata],
    description: "提案 #123: 将 USDC 市场供应 Kink 从 80% 提高到 85%\n\n背景：...\n影响分析：..."
};

// 3. 提交到 Governor
await governor.propose(
    proposal.targets,
    proposal.values,
    proposal.signatures,
    proposal.calldatas,
    proposal.description
);
```

#### 添加新抵押资产

```javascript
const newAssetConfig = {
    asset: "0x...",              // 新资产地址
    priceFeed: "0x...",          // 价格源
    decimals: 18,
    borrowCollateralFactor: ethers.utils.parseUnits("0.70", 18),
    liquidateCollateralFactor: ethers.utils.parseUnits("0.75", 18),
    liquidationFactor: ethers.utils.parseUnits("0.93", 18),
    supplyCap: ethers.utils.parseUnits("10000", 18)
};

const calldata = configurator.interface.encodeFunctionData(
    "addAsset",
    [cometProxyAddress, newAssetConfig]
);

// 提交提案...
```

### 6.3 市场管理员快速调整

对于频繁调整的参数（利率、奖励速度），可以授权市场管理员：

```javascript
// 市场管理员直接调用（无需治理投票）
await configurator.connect(marketAdmin).setSupplyPerYearInterestRateSlopeLow(
    cometProxy,
    ethers.utils.parseUnits("0.04", 18) // 调整为 4%
);

// 立即生效
```

**优点**：
- 快速响应市场变化
- 无需漫长的投票过程
- 灵活调整利率和风控参数

**限制**：
- 只能修改特定参数
- 不能修改核心安全参数

---

## 七、安全限制与最佳实践

### 7.1 不可违反的硬性约束

#### 约束1：抵押率顺序

```
borrowCollateralFactor < liquidateCollateralFactor < 1.0

正确示例：
  borrowCF = 0.80 (80%)
  liquidateCF = 0.85 (85%)
  差距 = 5%  ✓

错误示例：
  borrowCF = 0.85
  liquidateCF = 0.80
  差距 = -5%  ✗ (会导致新借贷立即被清算)
```

**代码检查**：
```solidity
// Comet.sol 构造函数
if (assetConfig.borrowCollateralFactor >= assetConfig.liquidateCollateralFactor) {
    revert BorrowCFTooLarge();
}
if (assetConfig.liquidateCollateralFactor > MAX_COLLATERAL_FACTOR) {
    revert LiquidateCFTooLarge();
}
```

---

#### 约束2：利率关系

```
借贷利率 ≥ 供应利率

原因：协议需要利差收入

建议差距：≥ 1% (在所有利用率水平)
```

---

#### 约束3：精度限制

```solidity
decimals ≤ MAX_BASE_DECIMALS (18)

// 价格源必须返回 8 位小数
priceFeed.decimals() == 8
```

---

### 7.2 最佳实践建议

#### 1. 新资产上线

```
阶段1：保守参数（第1个月）
  borrowCF = 0.65
  liquidateCF = 0.70
  supplyCap = 小额测试

阶段2：监控期（第2-3个月）
  观察：
    - 价格波动性
    - 链上流动性
    - 清算事件频率
    - 用户采用率

阶段3：调整（第4个月+）
  根据数据逐步提高：
    borrowCF → 0.75
    liquidateCF → 0.80
    supplyCap → 增加

阶段4：成熟期
  达到目标参数
```

---

#### 2. 利率调整策略

```javascript
// 监控指标
const utilization = totalBorrow / totalSupply;
const targetUtilization = 0.80; // 目标 80%

// 决策树
if (utilization < targetUtilization - 0.10) {
    // 利用率过低 (< 70%)
    // → 降低供应利率，提高借贷吸引力
    decreaseSupplyRates();
    decreaseBorrowRates();
    
} else if (utilization > targetUtilization + 0.10) {
    // 利用率过高 (> 90%)
    // → 提高供应利率，吸引更多供应
    increaseSupplyRates();
    increaseBorrowRates();
    
} else {
    // 利用率适中 (70% - 90%)
    // → 保持现状或微调
    maintainRates();
}
```

---

#### 3. 风险参数审查周期

```
每日监控：
  - 利用率
  - 清算事件
  - 储备金水平

每周审查：
  - 资产价格波动
  - 抵押品分布
  - 用户行为模式

每月评估：
  - 利率模型效果
  - 奖励分配效率
  - 风控参数适当性

每季度全面审计：
  - 所有参数合理性
  - 与竞品对比
  - 提出调整建议
```

---

#### 4. 应急响应流程

```
场景1：价格预言机异常
  ├─ pauseGuardian 立即暂停协议
  ├─ 诊断问题
  └─ governor 切换价格源或恢复

场景2：单一资产风险
  ├─ marketAdmin 降低该资产的 borrowCF
  ├─ 降低 supplyCap
  └─ 观察清算情况

场景3：流动性危机
  ├─ 提高高利用率区间的利率
  ├─ 增加供应奖励
  └─ 沟通策略（安抚用户）

场景4：智能合约漏洞
  ├─ pauseGuardian 全面暂停
  ├─ 安全团队评估
  ├─ 准备修复方案
  └─ governor 升级合约
```

---

### 7.3 常见错误与避免方法

#### 错误1：参数设置过于激进

```
案例：
  新资产刚上线就设置 borrowCF = 0.85

后果：
  价格波动 → 大量清算 → 用户损失 → 协议声誉受损

正确做法：
  新资产从 0.65 开始，逐步提高
```

---

#### 错误2：忽视利率曲线连续性

```
错误配置：
  supplyKink = 0.80
  slopeLow = 0.03
  slopeHigh = 0.40
  
  在 80% 利用率时：
    从左侧接近：1% + 3% = 4%
    从右侧接近：1% + 3% + 0 = 4%  ✓ 连续
    
  但如果 base 设置不当，会出现跳跃

正确做法：
  确保 kink 点两侧利率平滑过渡
```

---

#### 错误3：supplyCap 设置过小

```
案例：
  热门资产 supplyCap 过小 → 用户无法供应 → 流失到竞品

建议：
  初始 supplyCap = 预期需求的 150%
  根据实际使用率动态调整
```

---

## 八、参数查询工具

### 8.1 链上查询

```javascript
// 使用 ethers.js
const comet = new ethers.Contract(cometAddress, cometABI, provider);

// 查询所有参数
async function getAllParameters() {
    return {
        // 不可变参数
        baseToken: await comet.baseToken(),
        governor: await comet.governor(),
        pauseGuardian: await comet.pauseGuardian(),
        
        // 利率参数
        supplyKink: await comet.supplyKink(),
        borrowKink: await comet.borrowKink(),
        
        // 获取资产数量
        numAssets: await comet.numAssets(),
        
        // 遍历每个资产
        assets: await Promise.all(
            Array.from({length: numAssets}, (_, i) => 
                comet.getAssetInfo(i)
            )
        )
    };
}

// 查询特定资产配置
async function getAssetConfig(assetAddress) {
    const assetInfo = await comet.getAssetInfoByAddress(assetAddress);
    return {
        asset: assetInfo.asset,
        offset: assetInfo.offset,
        scale: assetInfo.scale,
        borrowCollateralFactor: assetInfo.borrowCollateralFactor,
        liquidateCollateralFactor: assetInfo.liquidateCollateralFactor,
        liquidationFactor: assetInfo.liquidationFactor,
        supplyCap: assetInfo.supplyCap,
        priceFeed: assetInfo.priceFeed
    };
}
```

### 8.2 Configurator 查询

```javascript
const configurator = new ethers.Contract(configuratorAddress, configuratorABI, provider);

// 获取完整配置
const config = await configurator.getConfiguration(cometProxyAddress);

console.log("Governor:", config.governor);
console.log("Supply Kink:", ethers.utils.formatUnits(config.supplyKink, 18));
console.log("Assets:", config.assetConfigs.length);
```

---

## 九、总结

### 参数分类速查

```
📦 配置参数总数：30+

├─ 🔒 不可更改 (4个)
│  ├─ baseToken
│  ├─ trackingIndexScale
│  ├─ decimals
│  └─ baseScale
│
├─ 🔑 Governor专属 (11个)
│  ├─ 权限 (2): governor, pauseGuardian
│  ├─ 预言机 (2): baseTokenPriceFeed, extensionDelegate
│  ├─ 清算 (3): storeFrontPriceFactor, baseMinForRewards, targetReserves
│  └─ 资产管理 (4): addAsset, updateAsset, updateAssetPriceFeed, (删除功能)
│
├─ ⚙️ Governor或MarketAdmin (12个)
│  ├─ 供应利率 (4): supplyKink, Base, SlopeLow, SlopeHigh
│  ├─ 借贷利率 (4): borrowKink, Base, SlopeLow, SlopeHigh
│  ├─ 奖励 (2): baseTrackingSupplySpeed, baseTrackingBorrowSpeed
│  ├─ 限制 (1): baseBorrowMin
│  └─ 资产风控 (4): borrowCF, liquidateCF, liquidationFactor, supplyCap
│
└─ 📊 每个资产 (7个参数)
   ├─ 基本 (3): asset, priceFeed, decimals
   └─ 风控 (4): borrowCF, liquidateCF, liquidationFactor, supplyCap
```

### 关键要点

1. **不可更改的慎重选择**
   - baseToken 和 trackingIndexScale 永久固定
   - 错误选择需要重新部署

2. **权限分级合理**
   - 核心参数需要治理投票
   - 运营参数可以快速调整

3. **风险参数保守起步**
   - 新资产低 CF 开始
   - 逐步提高到目标值

4. **持续监控调整**
   - 利率根据市场动态调整
   - 风控参数根据链上数据优化

5. **应急机制完善**
   - pauseGuardian 快速响应
   - 清晰的升级路径

---

**文档版本**：v1.0  
**最后更新**：2026年1月8日  
**相关文档**：
- [核心流程分析.md](核心流程分析.md)
- [补充核心流程分析.md](补充核心流程分析.md)
- [合约代码阅读指南.md](合约代码阅读指南.md)
- [真实交易案例分析.md](真实交易案例分析.md)

**参考资料**：
- [Compound V3 Documentation](https://docs.compound.finance)
- [GitHub Repository](https://github.com/compound-finance/comet)
