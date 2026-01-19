// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometWithExtendedAssetList.sol";
import "./CometConfiguration.sol";

/**
 * @title CometFactoryWithExtendedAssetList
 * @notice 创建支持扩展资产列表的 Comet 实例
 * @dev 中文：用于部署 CometWithExtendedAssetList 版本
 */
contract CometFactoryWithExtendedAssetList is CometConfiguration {
    function clone(Configuration calldata config) external returns (address) {
        return address(new CometWithExtendedAssetList(config));
    }
}