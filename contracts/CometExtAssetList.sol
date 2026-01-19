// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometExt.sol";

/**
 * @title CometExtAssetList
 * @notice Comet 扩展合约的资产列表变体
 * @dev 中文：用于在扩展合约侧增加可支持资产数量
 */
contract CometExtAssetList is CometExt {

    /// @notice The address of the asset list factory
    address immutable public assetListFactory;

    /**
     * @notice Construct a new protocol instance
     * @param config The mapping of initial/constant parameters
     * @param assetListFactoryAddress The address of the asset list factory
     **/
    constructor(ExtConfiguration memory config, address assetListFactoryAddress) CometExt(config) {
        assetListFactory = assetListFactoryAddress;
    }
    
    uint8 internal constant MAX_ASSETS_FOR_ASSET_LIST = 24;

    function maxAssets() override external pure returns (uint8) { return MAX_ASSETS_FOR_ASSET_LIST; }
}