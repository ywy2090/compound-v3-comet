// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometMainInterface.sol";
import "./CometExtInterface.sol";

/**
 * @title Compound's Comet Interface
 * @notice An efficient monolithic money market protocol
 * @dev 中文：聚合主合约与扩展合约接口，便于统一类型引用
 * @author Compound
 */
abstract contract CometInterface is CometMainInterface, CometExtInterface {}
