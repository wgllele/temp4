// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title SkimUtil0 — 单方向 skim：兑出 token1（原 skimOut0）
/// @notice 调用方先向 pair 转入 token0（制造不平衡），再对本合约发一笔 calldata；
///         本合约校验 pair 当前 `reserve1` 与预期一致后，调用 `swap(0, amountOut, to, "")`
///         将多余 token1 兑出到固定收款地址。
/// @dev calldata 定长 40 字节（无 selector，走 fallback）：
///      ```
///      pair(20) || amountOut(8 uint64) || r1(12 uint96)
///      ```
///      - `pair`：UniswapV2 风格 pair 地址
///      - `amountOut`：兑出的 token1 数量；业务上限 10 ether
///      - `r1`：调用前预期的 `reserve1`；业务上限约 1e7 WBNB / 1e9 USDT(18dec)，编码 uint96
///
///      流程（成功路径烤机最优）：
///      1. `getReserves()` → 用 `xor` 比对 `r1` 与链上 `reserve1`，不等则 `revert(0,0)`
///      2. `swap(0, amountOut, SKIM_RECEIVER, "")`；`pop(call)` 忽略返回值（无 calldatasize 检查）
///
///      相关 selector / 常量：
///      - `getReserves()` = `0x0902f1ac`
///      - `swap(uint256,uint256,address,bytes)` = `0x022c0d9f`
///      - 收款地址硬编码：`0xe22DD309bc8B3220a35FFf9959aFA57C6e188859`
contract SkimUtil0 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            // --- 解析 calldata（共 40B，左对齐读入后右移去零）---
            // [0,20):  pair 地址
            let pairAddr := shr(96, calldataload(0))
            // [20,28): amountOut (uint64)
            let amountOut := shr(192, calldataload(20))
            // [28,40): r1 预期 reserve1 (uint96)
            let r1 := shr(160, calldataload(28))

            // --- getReserves()：selector 写 scratch，返回值落到 0xc0 / 0xe0 ---
            // staticcall 写 0x40 字节 → 0xc0=reserve0, 0xe0=reserve1（其后还有 blockTimestampLast，此处不读）
            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            // 预期 r1 与链上 reserve1 必须相等；xor≠0 则 revert（无 error data，省 gas）
            if xor(r1, mload(0xe0)) { revert(0, 0) }

            // --- swap(0, amountOut, to, "") ---
            // calldata 布局（共 0xa4 = 4 + 4*32 字节；data 为空 bytes，仅写 offset=0x80，不跟 length）
            //   0x00: selector 0x022c0d9f
            //   0x04: amount0Out = 0
            //   0x24: amount1Out = amountOut
            //   0x44: to         = SKIM_RECEIVER
            //   0x64: data offset = 0x80（相对 arguments 起始）
            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, 0)
            mstore(0x24, amountOut)
            mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
            mstore(0x64, 0x80)
            // 成功路径不检查 call 返回值；失败则 pair 内 revert 冒泡或状态回滚由调用方处理
            pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
        }
    }
}

/// @title SkimUtil1 — 单方向 skim：兑出 token0（原 skimOut1）
/// @notice 与 `SkimUtil0` 对称：调用方先向 pair 转入 token1，本合约校验 `reserve0` 后
///         调用 `swap(amountOut, 0, to, "")` 兑出 token0。
/// @dev calldata 定长 40 字节（无 selector，走 fallback）：
///      ```
///      pair(20) || amountOut(8 uint64) || r0(12 uint96)
///      ```
///      - `pair`：UniswapV2 风格 pair 地址
///      - `amountOut`：兑出的 token0 数量；业务上限 10 ether
///      - `r0`：调用前预期的 `reserve0`；业务上限约 1e7 WBNB / 1e9 USDT(18dec)，编码 uint96
///
///      流程（成功路径烤机最优）：`if xor { revert }` + `pop(call)`（无 calldatasize 检查）。
///
///      selector / 收款地址同 `SkimUtil0`。
contract SkimUtil1 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            // --- 解析 calldata（共 40B）---
            // [0,20):  pair 地址
            let pairAddr := shr(96, calldataload(0))
            // [20,28): amountOut (uint64)
            let amountOut := shr(192, calldataload(20))
            // [28,40): r0 预期 reserve0 (uint96)
            let r0 := shr(160, calldataload(28))

            // --- getReserves()：返回值 0xc0=reserve0, 0xe0=reserve1 ---
            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            // 预期 r0 与链上 reserve0 必须相等
            if xor(r0, mload(0xc0)) { revert(0, 0) }

            // --- swap(amountOut, 0, to, "") ---
            //   0x04: amount0Out = amountOut
            //   0x24: amount1Out = 0
            //   0x44: to         = SKIM_RECEIVER
            //   0x64: data offset = 0x80
            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, amountOut)
            mstore(0x24, 0)
            mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
            mstore(0x64, 0x80)
            pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
        }
    }
}
