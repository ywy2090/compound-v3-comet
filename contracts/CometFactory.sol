// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./Comet.sol";
import "./CometConfiguration.sol";

/**
 * @title CometFactory
 * @notice 创建 Comet 主合约实例的简单工厂
 * @dev 中文：封装部署逻辑，便于通过配置快速创建新市场
 */
contract CometFactory is CometConfiguration {
    function clone(Configuration calldata config) external returns (address) {
        return address(new Comet(config));
    }
}