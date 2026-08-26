// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @notice 定长批量 skim：一笔 calldata 内顺序执行多笔，可混合 dir0/dir1。
/// @dev 每项 41 字节: `dir(1) || pair(20) || amountOut(8 uint64) || r(12 uint96)`。
///      dir: 0=兑 token1（比 r1）；1=兑 token0（比 r0）。
///      amountOut 上限 10 ether；r 上限约 1e7 WBNB / 1e9 USDT(18dec)。
///      调用方保证长度为 41 的整数倍。
///      reserve 用 `switch xor case 0`（烤机与 iszero 持平/更优，且单项可跳过）；swap 失败跳过。
contract SkimUtilBatch {
    receive() external payable {}

    fallback() external payable {
        assembly {
            let cdSize := calldatasize()

            for { let offset := 0 } lt(offset, cdSize) { offset := add(offset, 41) } {
                let dir := byte(0, calldataload(offset))
                let pairAddr := shr(96, calldataload(add(offset, 1)))
                let amountOut := shr(192, calldataload(add(offset, 21)))
                let r := shr(160, calldataload(add(offset, 29)))

                mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
                pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))

                switch dir
                case 0 {
                    switch xor(r, mload(0xe0))
                    case 0 {
                        mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
                        mstore(0x04, 0)
                        mstore(0x24, amountOut)
                        mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
                        mstore(0x64, 0x80)
                        pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
                    }
                }
                default {
                    switch xor(r, mload(0xc0))
                    case 0 {
                        mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
                        mstore(0x04, amountOut)
                        mstore(0x24, 0)
                        mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
                        mstore(0x64, 0x80)
                        pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
                    }
                }
            }
        }
    }
}
