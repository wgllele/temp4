// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @notice 单方向：兑出 token1（原 skimOut0）。
/// @dev calldata: `pair(20) || amountOut(8 uint64) || r1(12 uint96)`，共 40 字节。
///      amountOut 业务上限 10 ether；r 业务上限约 1e7 WBNB / 1e9 USDT(18dec)，编码 uint96。
contract SkimUtil0 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            if iszero(eq(calldatasize(), 40)) { revert(0, 0) }

            let pairAddr := shr(96, calldataload(0))
            let amountOut := shr(192, calldataload(20))
            let r1 := shr(160, calldataload(28))

            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            if xor(r1, mload(0xe0)) { revert(0, 0) }

            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x24, amountOut)
            mstore(0x44, 0x9f8c767a407b74dd35F2916C21114186d5CC8AB2)
            mstore(0x64, 0x80)
            if iszero(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0)) { revert(0, 0) }
        }
    }
}

/// @notice 单方向：兑出 token0（原 skimOut1）。
/// @dev calldata: `pair(20) || amountOut(8 uint64) || r0(12 uint96)`，共 40 字节。
contract SkimUtil1 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            if iszero(eq(calldatasize(), 40)) { revert(0, 0) }

            let pairAddr := shr(96, calldataload(0))
            let amountOut := shr(192, calldataload(20))
            let r0 := shr(160, calldataload(28))

            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            if xor(r0, mload(0xc0)) { revert(0, 0) }

            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, amountOut)
            mstore(0x24, 0)
            mstore(0x44, 0x9f8c767a407b74dd35F2916C21114186d5CC8AB2)
            mstore(0x64, 0x80)
            if iszero(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0)) { revert(0, 0) }
        }
    }
}
