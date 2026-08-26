// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @notice 单方向：兑出 token1（原 skimOut0）。
/// @dev calldata: `pair(20) || amountOut(8 uint64) || r1(12 uint96)`，共 40 字节。
///      amountOut 业务上限 10 ether；r 业务上限约 1e7 WBNB / 1e9 USDT(18dec)，编码 uint96。
///      成功路径烤机最优：`if xor { revert }` + `pop(call)`（无 calldatasize 检查）。
contract SkimUtil0 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            let pairAddr := shr(96, calldataload(0))
            let amountOut := shr(192, calldataload(20))
            let r1 := shr(160, calldataload(28))

            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            if xor(r1, mload(0xe0)) { revert(0, 0) }

            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, 0)
            mstore(0x24, amountOut)
            mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
            mstore(0x64, 0x80)
            pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
        }
    }
}

/// @notice 单方向：兑出 token0（原 skimOut1）。
/// @dev calldata: `pair(20) || amountOut(8 uint64) || r0(12 uint96)`，共 40 字节。
///      成功路径烤机最优：`if xor { revert }` + `pop(call)`。
contract SkimUtil1 {
    receive() external payable {}

    fallback() external payable {
        assembly {
            let pairAddr := shr(96, calldataload(0))
            let amountOut := shr(192, calldataload(20))
            let r0 := shr(160, calldataload(28))

            mstore(0x00, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            pop(staticcall(gas(), pairAddr, 0x00, 0x04, 0xc0, 0x40))
            if xor(r0, mload(0xc0)) { revert(0, 0) }

            mstore(0x00, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            mstore(0x04, amountOut)
            mstore(0x24, 0)
            mstore(0x44, 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859)
            mstore(0x64, 0x80)
            pop(call(gas(), pairAddr, 0, 0x00, 0xa4, 0, 0))
        }
    }
}

/// @notice 预估/强校验：转调链上 SkimUtil0/1，确认收款地址到账 `amountOut`，否则 revert。
/// @dev calldata: `dir(1) || pair(20) || amountOut(8 uint64) || r(12 uint96)`，共 41 字节。
///      dir=0 → SkimUtil0（兑 token1）；dir=1 → SkimUtil1（兑 token0）。
///      后 40 字节原样转发给 util；用 `balanceOf(0xe22D…)` 差值校验到账。
///      供 eth_call 预估，或实发时避免 util 吞掉 swap 失败仍显示成功。
contract SkimUtilProbe {
    address private constant SKIM_UTIL0 = 0xb800006A0000572188F30045cf008656c976398A;
    address private constant SKIM_UTIL1 = 0x9900006600AaEeC900e5e8d96881c111c3000058;
    address private constant RECEIVER = 0xe22DD309bc8B3220a35FFf9959aFA57C6e188859;

    receive() external payable {}

    fallback() external payable {
        assembly {
            // dir(1) || pair(20) || amountOut(8) || r(12)
            let dir := byte(0, calldataload(0))
            let pairAddr := shr(96, calldataload(1))
            let amountOut := shr(192, calldataload(21))

            // token = dir==0 ? token1() : token0()
            switch dir
            case 0 {
                mstore(0x00, 0xd21220a700000000000000000000000000000000000000000000000000000000)
            }
            default {
                mstore(0x00, 0x0dfe168100000000000000000000000000000000000000000000000000000000)
            }
            if iszero(staticcall(gas(), pairAddr, 0x00, 0x04, 0x00, 0x20)) { revert(0, 0) }
            let token := mload(0x00)

            // balBefore = balanceOf(RECEIVER)
            mstore(0x00, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(0x04, RECEIVER)
            if iszero(staticcall(gas(), token, 0x00, 0x24, 0x00, 0x20)) { revert(0, 0) }
            let balBefore := mload(0x00)

            // forward payload[1:41] → SkimUtil0/1
            calldatacopy(0x00, 1, 40)
            let util := SKIM_UTIL0
            if dir { util := SKIM_UTIL1 }
            pop(call(gas(), util, 0, 0x00, 40, 0, 0))

            // balAfter；不到账 amountOut 则 revert
            mstore(0x00, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(0x04, RECEIVER)
            if iszero(staticcall(gas(), token, 0x00, 0x24, 0x00, 0x20)) { revert(0, 0) }
            let balAfter := mload(0x00)
            if iszero(eq(balAfter, add(balBefore, amountOut))) { revert(0, 0) }
        }
    }
}
