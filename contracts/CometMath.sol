// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

/**
 * @title Compound's Comet Math Contract
 * @title Compound Comet 数学运算合约
 * @dev Pure math functions
 * @dev 纯数学函数，用于安全的类型转换和数值操作
 * @author Compound
 */
contract CometMath {
    /** Custom errors 自定义错误 **/

    /// @dev 当数值超过 uint64 最大值时抛出
    error InvalidUInt64();
    /// @dev 当数值超过 uint104 最大值时抛出
    error InvalidUInt104();
    /// @dev 当数值超过 uint128 最大值时抛出
    error InvalidUInt128();
    /// @dev 当数值超过 int104 最大值时抛出
    error InvalidInt104();
    /// @dev 当数值超过 int256 最大值时抛出
    error InvalidInt256();
    /// @dev 当尝试将负数转换为无符号整数时抛出
    error NegativeNumber();

    /**
     * @notice 安全地将 uint256 转换为 uint64
     * @dev 如果数值超过 uint64 的最大值则回滚
     * @param n 要转换的无符号整数
     * @return 转换后的 uint64 值
     */
    function safe64(uint n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64();
        return uint64(n);
    }

    /**
     * @notice 安全地将 uint256 转换为 uint104
     * @dev 如果数值超过 uint104 的最大值则回滚
     * @dev uint104 用于存储用户本金和总供应/借贷量，可以表示约 20 万亿（对于 18 位小数的代币）
     * @param n 要转换的无符号整数
     * @return 转换后的 uint104 值
     */
    function safe104(uint n) internal pure returns (uint104) {
        if (n > type(uint104).max) revert InvalidUInt104();
        return uint104(n);
    }

    /**
     * @notice 安全地将 uint256 转换为 uint128
     * @dev 如果数值超过 uint128 的最大值则回滚
     * @dev uint128 用于存储抵押品余额和供应上限
     * @param n 要转换的无符号整数
     * @return 转换后的 uint128 值
     */
    function safe128(uint n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert InvalidUInt128();
        return uint128(n);
    }

    /**
     * @notice 安全地将 uint104 转换为 int104
     * @dev 如果数值超过 int104 的最大值则回滚
     * @dev int104 用于表示用户的本金（正值为供应，负值为借贷）
     * @param n 要转换的无符号整数
     * @return 转换后的 int104 值
     */
    function signed104(uint104 n) internal pure returns (int104) {
        if (n > uint104(type(int104).max)) revert InvalidInt104();
        return int104(n);
    }

    /**
     * @notice 安全地将 uint256 转换为 int256
     * @dev 如果数值超过 int256 的最大值则回滚
     * @param n 要转换的无符号整数
     * @return 转换后的 int256 值
     */
    function signed256(uint256 n) internal pure returns (int256) {
        if (n > uint256(type(int256).max)) revert InvalidInt256();
        return int256(n);
    }

    /**
     * @notice 安全地将 int104 转换为 uint104
     * @dev 如果数值为负数则回滚
     * @param n 要转换的有符号整数
     * @return 转换后的 uint104 值
     */
    function unsigned104(int104 n) internal pure returns (uint104) {
        if (n < 0) revert NegativeNumber();
        return uint104(n);
    }

    /**
     * @notice 安全地将 int256 转换为 uint256
     * @dev 如果数值为负数则回滚
     * @param n 要转换的有符号整数
     * @return 转换后的 uint256 值
     */
    function unsigned256(int256 n) internal pure returns (uint256) {
        if (n < 0) revert NegativeNumber();
        return uint256(n);
    }

    /**
     * @notice 将布尔值转换为 uint8 (1 或 0)
     * @dev 用于位标志操作
     * @param x 布尔值
     * @return 1 如果为 true，0 如果为 false
     */
    function toUInt8(bool x) internal pure returns (uint8) {
        return x ? 1 : 0;
    }

    /**
     * @notice 将 uint8 转换为布尔值
     * @dev 用于位标志操作，任何非零值都返回 true
     * @param x 整数值
     * @return 如果 x 不为 0 则返回 true，否则返回 false
     */
    function toBool(uint8 x) internal pure returns (bool) {
        return x != 0;
    }
}
