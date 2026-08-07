// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {SkimUtil0, SkimUtil1} from "../new/evm/SkimUtil01.sol";
import {SkimUtilBatch} from "../new/evm/SkimUtilBatch.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @notice BSC fork：定长 SkimUtil0/1（40B）+ SkimUtilBatch（41B/项，单项失败跳过）。
///
/// 数据来源:
/// - dir0: tx 0x36b3816eeb01dd3f923306a5f700f73424e5eefadb7201b8e8970abdd445db26, block 114490869
/// - dir1: tx 0xb9972b856c32eddc8e74a77bc41bf533c475be232415364655b4747e3e55fd34, block 114445709
///
/// 运行:
///   forge test --match-contract UtilTestSkimBsc -vvv --fork-url $BSC_RPC_URL
contract UtilTestSkimBscTest is Test {
    address constant SKIM_RECEIVER = 0x9f8c767a407b74dd35F2916C21114186d5CC8AB2;
    uint256 constant PAIR_RESERVE_SLOT = 8;
    /// @dev amountOut 业务上限（编码为 uint64）
    uint256 constant AMOUNT_OUT_MAX = 10 ether;
    /// @dev r 业务上限：约 1e7 WBNB 或 1e9 USDT(18dec)，编码 uint96
    uint256 constant RESERVE_MAX = type(uint96).max;

    // --- tx1 / dir0（兑出 token1=WBNB）---
    bytes32 constant TX1 =
        0x36b3816eeb01dd3f923306a5f700f73424e5eefadb7201b8e8970abdd445db26;
    address constant PAIR1 = 0x3041b5fA21F107411F4b3CF4F07a316B847ac218;
    uint112 constant TX1_R0 = 130007195172241123972420; // 0x1b87b444a18327321544
    uint112 constant TX1_R1 = 335916336467782816219; // 0x1235c69041a4ca51db
    uint256 constant TX1_AMOUNT0_IN = 4350875362895403; // 0xf75191c77a62b
    uint256 constant TX1_AMOUNT1_OUT = 11213811946727; // 0xa32eb4714e7
    uint256 constant TX1_GAS_USED = 185719;

    // --- tx2 / dir1（兑出 token0=WBNB）；链上无 Swap 日志，calldata 重建 ---
    bytes32 constant TX2 =
        0xb9972b856c32eddc8e74a77bc41bf533c475be232415364655b4747e3e55fd34;
    address constant PAIR2 = 0x8D6a90c4e201AAaB556d3B6c47A095Ce80452184;
    uint112 constant TX2_R0 = 372854744682022513683; // 0x14366626d1b6eb2c13（calldata 中的 r）
    uint112 constant TX2_R1 = 1000000000000000000; // 测试用占位，保证 amountOut < r0
    uint256 constant TX2_AMOUNT1_IN = 1 ether;
    uint256 constant TX2_AMOUNT0_OUT = 18946249088042; // 0x113b44725c2a
    uint256 constant TX2_GAS_USED = 27970;

    SkimUtil0 internal util0;
    SkimUtil1 internal util1;
    SkimUtilBatch internal utilBatch;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.binance.org"));
        vm.createSelectFork(rpc);
        util0 = new SkimUtil0();
        util1 = new SkimUtil1();
        utilBatch = new SkimUtilBatch();
    }

    function test_skimUtil0_fromTx1() public {
        _prepDir0();
        address token1 = IUniswapV2Pair(PAIR1).token1();
        uint256 beforeOut = IERC20(token1).balanceOf(SKIM_RECEIVER);

        bytes memory cd = _packFixed(PAIR1, TX1_R1, TX1_AMOUNT1_OUT);
        (uint256 execGas, bool ok) = _measure(address(util0), cd);
        require(ok, "SkimUtil0");
        assertEq(IERC20(token1).balanceOf(SKIM_RECEIVER) - beforeOut, TX1_AMOUNT1_OUT);
        _logGasCompare("SkimUtil0", TX1, TX1_GAS_USED, execGas, cd);
    }

    function test_skimUtil1_fromTx2() public {
        _prepDir1();
        address token0 = IUniswapV2Pair(PAIR2).token0();
        uint256 beforeOut = IERC20(token0).balanceOf(SKIM_RECEIVER);

        bytes memory cd = _packFixed(PAIR2, TX2_R0, TX2_AMOUNT0_OUT);
        (uint256 execGas, bool ok) = _measure(address(util1), cd);
        require(ok, "SkimUtil1");
        assertEq(IERC20(token0).balanceOf(SKIM_RECEIVER) - beforeOut, TX2_AMOUNT0_OUT);
        _logGasCompare("SkimUtil1", TX2, TX2_GAS_USED, execGas, cd);
    }

    function test_skimUtil0_revertsOnReserveMismatch() public {
        _prepDir0();
        bytes memory cd = _packFixed(PAIR1, TX1_R1 + 1, TX1_AMOUNT1_OUT);
        (uint256 failGas, bool ok) = _measure(address(util0), cd);
        assertFalse(ok, "expected reserve mismatch");
        console2.log("--- mismatch fail exec gas", failGas);
    }

    function test_batch_single_dir0() public {
        _prepDir0();
        address token1 = IUniswapV2Pair(PAIR1).token1();
        uint256 beforeOut = IERC20(token1).balanceOf(SKIM_RECEIVER);

        bytes memory cd = _packBatchItem(0, PAIR1, TX1_R1, TX1_AMOUNT1_OUT);
        (uint256 execGas, bool ok) = _measure(address(utilBatch), cd);
        require(ok, "batch dir0");
        assertEq(IERC20(token1).balanceOf(SKIM_RECEIVER) - beforeOut, TX1_AMOUNT1_OUT);
        _logVariant("batch 1x dir0", execGas, cd);
    }

    function test_batch_single_dir1() public {
        _prepDir1();
        address token0 = IUniswapV2Pair(PAIR2).token0();
        uint256 beforeOut = IERC20(token0).balanceOf(SKIM_RECEIVER);

        bytes memory cd = _packBatchItem(1, PAIR2, TX2_R0, TX2_AMOUNT0_OUT);
        (uint256 execGas, bool ok) = _measure(address(utilBatch), cd);
        require(ok, "batch dir1");
        assertEq(IERC20(token0).balanceOf(SKIM_RECEIVER) - beforeOut, TX2_AMOUNT0_OUT);
        _logVariant("batch 1x dir1", execGas, cd);
    }

    function test_batch_mixed_dir0_dir1() public {
        _prepDir0();
        _prepDir1();
        address wbnb = IUniswapV2Pair(PAIR1).token1();
        assertEq(wbnb, IUniswapV2Pair(PAIR2).token0(), "wbnb");
        uint256 before = IERC20(wbnb).balanceOf(SKIM_RECEIVER);

        bytes memory cd = bytes.concat(
            _packBatchItem(0, PAIR1, TX1_R1, TX1_AMOUNT1_OUT),
            _packBatchItem(1, PAIR2, TX2_R0, TX2_AMOUNT0_OUT)
        );
        (uint256 execGas, bool ok) = _measure(address(utilBatch), cd);
        require(ok, "batch mixed");
        assertEq(
            IERC20(wbnb).balanceOf(SKIM_RECEIVER) - before,
            TX1_AMOUNT1_OUT + TX2_AMOUNT0_OUT,
            "wbnb out"
        );
        _logVariant("batch mixed dir0+dir1", execGas, cd);
    }

    /// @notice 第一项失败（r 错）不影响第二项成功执行。
    function test_batch_firstFail_secondOk() public {
        _prepDir0();
        _prepDir1();
        address wbnb = IUniswapV2Pair(PAIR2).token0();
        uint256 before = IERC20(wbnb).balanceOf(SKIM_RECEIVER);

        bytes memory cd = bytes.concat(
            _packBatchItem(0, PAIR1, TX1_R1 + 1, TX1_AMOUNT1_OUT), // mismatch → skip
            _packBatchItem(1, PAIR2, TX2_R0, TX2_AMOUNT0_OUT) // ok
        );
        (uint256 execGas, bool ok) = _measure(address(utilBatch), cd);
        require(ok, "batch continues");
        assertEq(IERC20(wbnb).balanceOf(SKIM_RECEIVER) - before, TX2_AMOUNT0_OUT, "only dir1");
        _logVariant("batch fail+ok", execGas, cd);
    }

    /// @notice 第二项失败不影响第一项已成功入账。
    function test_batch_firstOk_secondFail() public {
        _prepDir0();
        _prepDir1();
        address wbnb = IUniswapV2Pair(PAIR1).token1();
        uint256 before = IERC20(wbnb).balanceOf(SKIM_RECEIVER);

        bytes memory cd = bytes.concat(
            _packBatchItem(0, PAIR1, TX1_R1, TX1_AMOUNT1_OUT), // ok
            _packBatchItem(1, PAIR2, TX2_R0 + 1, TX2_AMOUNT0_OUT) // mismatch → skip
        );
        (uint256 execGas, bool ok) = _measure(address(utilBatch), cd);
        require(ok, "batch continues");
        assertEq(IERC20(wbnb).balanceOf(SKIM_RECEIVER) - before, TX1_AMOUNT1_OUT, "only dir0");
        _logVariant("batch ok+fail", execGas, cd);
    }

    function _prepDir0() internal {
        _setReserves(PAIR1, TX1_R0, TX1_R1);
        deal(IUniswapV2Pair(PAIR1).token1(), PAIR1, uint256(TX1_R1));
        _mockBalanceOf(IUniswapV2Pair(PAIR1).token0(), PAIR1, uint256(TX1_R0) + TX1_AMOUNT0_IN);
    }

    function _prepDir1() internal {
        _setReserves(PAIR2, TX2_R0, TX2_R1);
        deal(IUniswapV2Pair(PAIR2).token0(), PAIR2, uint256(TX2_R0));
        _mockBalanceOf(IUniswapV2Pair(PAIR2).token1(), PAIR2, uint256(TX2_R1) + TX2_AMOUNT1_IN);
    }

    function _measure(address target, bytes memory cd) internal returns (uint256 execGas, bool ok) {
        uint256 g0 = gasleft();
        (ok,) = target.call(cd);
        execGas = g0 - gasleft();
    }

    function _logVariant(string memory label, uint256 execGas, bytes memory cd) internal pure {
        uint256 cdGas = _calldataGas(cd);
        console2.log(label);
        console2.log("  exec", execGas);
        console2.log("  cdGas", cdGas);
        console2.log("  cdBytes", cd.length);
        console2.log("  estTx", 21000 + cdGas + execGas);
    }

    function _logGasCompare(
        string memory label,
        bytes32 txHash,
        uint256 txGasUsed,
        uint256 execGas,
        bytes memory calldataBytes
    ) internal pure {
        uint256 cdGas = _calldataGas(calldataBytes);
        uint256 estTxGas = 21000 + cdGas + execGas;
        int256 delta = int256(estTxGas) - int256(txGasUsed);

        console2.log("--- gas compare:", label);
        console2.logBytes32(txHash);
        console2.log("tx.gasUsed (on-chain)", txGasUsed);
        console2.log("test exec gas        ", execGas);
        console2.log("test calldata gas    ", cdGas);
        console2.log("test calldata bytes  ", calldataBytes.length);
        console2.log("est full tx gas      ", estTxGas);
        if (delta <= 0) {
            console2.log("est saved vs tx      ", uint256(-delta));
        } else {
            console2.log("est extra vs tx      ", uint256(delta));
        }
    }

    function _calldataGas(bytes memory data) internal pure returns (uint256 gasUsed) {
        unchecked {
            for (uint256 i; i < data.length; ++i) {
                gasUsed += data[i] == 0 ? 4 : 16;
            }
        }
    }

    /// @dev SkimUtil0/1: pair(20)||amountOut(8 uint64)||r(12 uint96)=40
    function _packFixed(
        address pairAddr,
        uint112 r,
        uint256 amountOut
    ) internal pure returns (bytes memory) {
        require(amountOut <= AMOUNT_OUT_MAX, "amountOut");
        require(uint256(r) <= RESERVE_MAX, "r");
        return abi.encodePacked(pairAddr, uint64(amountOut), uint96(r));
    }

    /// @dev 批量项 41B: dir(1)||pair(20)||amountOut(8)||r(12)
    function _packBatchItem(
        uint8 dir,
        address pairAddr,
        uint112 r,
        uint256 amountOut
    ) internal pure returns (bytes memory) {
        require(dir <= 1, "dir");
        require(amountOut <= AMOUNT_OUT_MAX, "amountOut");
        require(uint256(r) <= RESERVE_MAX, "r");
        return abi.encodePacked(dir, pairAddr, uint64(amountOut), uint96(r));
    }

    function _setReserves(address pair, uint112 r0, uint112 r1) internal {
        uint256 packed = uint256(r0) | (uint256(r1) << 112)
            | (uint256(uint32(block.timestamp)) << 224);
        vm.store(pair, bytes32(PAIR_RESERVE_SLOT), bytes32(packed));
    }

    function _mockBalanceOf(address token, address account, uint256 amount) internal {
        vm.mockCall(
            token,
            abi.encodeWithSelector(IERC20.balanceOf.selector, account),
            abi.encode(amount)
        );
    }
}
