# SkimUtil / UtilTest — Java（Web3j）对接文档

面向 `new/evm` 下三个合约的 Java 调用说明：

| 合约 | 路径 | 调用方式 |
| --- | --- | --- |
| `SkimUtil0` / `SkimUtil1` | `new/evm/SkimUtil01.sol` | **无 selector**，整段 raw calldata |
| `SkimUtilBatch` | `new/evm/SkimUtilBatch.sol` | **无 selector**，定长多项拼接 |
| `UtilTest` | `new/evm/UtilTest.sol` | 标准 ABI（可用 FunctionEncoder） |

依赖（与现有工程一致即可）：

```xml
<dependency>
  <groupId>org.web3j</groupId>
  <artifactId>core</artifactId>
  <version>4.9.8</version><!-- 按项目实际版本 -->
</dependency>
```

常用类：`org.web3j.protocol.Web3j`、`org.web3j.utils.Numeric`、`org.web3j.abi.FunctionEncoder`、`org.web3j.crypto.RawTransaction` / `TransactionEncoder`。

### 部署地址

```text
CreateContractFactoryAddr 0xD902947686503e1150A07A146700415a4bcA0548
"skimUtil0":"0x0000000054d45c2aA439D8bd4DEb002C8200e1eb",
"skimUtil1":"0x9F00d458B0d6002A60e000004120493bB500F000",
"skimUtilBatch":"0xe800D2776847CB110f00b38814A6000000760075",
"utilTest":"0x2500874bcFA5006d1f9e70000000684300bA6f93",
```

| 名称 | 地址 |
| --- | --- |
| `CreateContractFactory` | `0xD902947686503e1150A07A146700415a4bcA0548` |
| `skimUtil0` | `0x0000000054d45c2aA439D8bd4DEb002C8200e1eb` |
| `skimUtil1` | `0x9F00d458B0d6002A60e000004120493bB500F000` |
| `skimUtilBatch` | `0xe800D2776847CB110f00b38814A6000000760075` |
| `utilTest` | `0x2500874bcFA5006d1f9e70000000684300bA6f93` |

---

## 1. 公共约定

### 1.1 收款地址（硬编码）

`SkimUtil0` / `SkimUtil1` / `SkimUtilBatch` 兑出代币固定转到：

```text
0x9f8c767a407b74dd35F2916C21114186d5CC8AB2
```

链下无需、也无法通过 calldata 改收款地址。

### 1.2 方向语义

| 方向 | 含义 | 比对 reserve | swap |
| --- | --- | --- | --- |
| dir0（`SkimUtil0`） | 兑出 **token1** | `reserve1` | `swap(0, amountOut, to, "")` |
| dir1（`SkimUtil1`） | 兑出 **token0** | `reserve0` | `swap(amountOut, 0, to, "")` |

### 1.3 数值编码（定长）

| 字段 | 编码 | 业务上限 |
| --- | --- | --- |
| `pair` | 20 字节 | UniswapV2 pair 地址 |
| `amountOut` | **8 字节 `uint64`** | **10 BNB**（`10 ether`）；`uint64` 物理上限约 18.44 ether |
| `r0` / `r1` | **12 字节 `uint96`** | 约 **1e7 WBNB** 或 **1e9 USDT（18 位）**；`uint96` 物理上限约 `7.92e28` |

说明：`1e9 * 1e18`（10 亿 USDT）约需 90 bit → 定长至少 12 字节；仅 WBNB `1e7 * 1e18` 约 84 bit，USDT 约束更紧。

链下打包时请校验 `amountOut <= 10 ether` 且 `reserve <= uint96.max`。

### 1.4 发送交易（通用）

Skim 类合约没有 ABI 方法名，用 **data = 打包后的 hex**，`to = 合约地址`，`value = 0`：

```java
import org.web3j.crypto.Credentials;
import org.web3j.crypto.RawTransaction;
import org.web3j.crypto.TransactionEncoder;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.methods.response.EthSendTransaction;
import org.web3j.utils.Numeric;

public static String sendRawCalldata(
        Web3j web3j,
        Credentials credentials,
        String contract,
        String dataHex,          // 带或不带 0x 均可
        long chainId,
        BigInteger nonce,
        BigInteger gasPrice,
        BigInteger gasLimit
) throws Exception {
    RawTransaction raw = RawTransaction.createTransaction(
            nonce,
            gasPrice,
            gasLimit,
            contract,
            BigInteger.ZERO,
            dataHex
    );
    byte[] signed = TransactionEncoder.signMessage(raw, chainId, credentials);
    EthSendTransaction resp = web3j.ethSendRawTransaction(Numeric.toHexString(signed)).send();
    if (resp.hasError()) {
        throw new IllegalStateException(resp.getError().getMessage());
    }
    return resp.getTransactionHash();
}
```

---

## 2. SkimUtil0 / SkimUtil1

### 2.1 Calldata 布局

```text
| pair(20) | amountOut(8 uint64) | r(12 uint96) |   共 40 字节
0         20                   28             40
```

- `SkimUtil0`：`r` = `reserve1`；不一致整笔 revert
- `SkimUtil1`：`r` = `reserve0`；不一致整笔 revert
- `amountOut` ≤ `10 ether`；`r` ≤ `uint96.max`（覆盖约 1e7 WBNB / 1e9 USDT-18dec）

### 2.2 Java 打包

`SkimUtil0` 与 `SkimUtil1` 的 **calldata 字节布局完全相同**，因此共用一个 `packSkim01`。  
**方向不由 calldata 编码，而由交易的 `to` 决定：**

| 发往合约 | 传入的 `reserve` | 行为 |
| --- | --- | --- |
| `SkimUtil0` 地址 | **`reserve1`** | 兑 token1 |
| `SkimUtil1` 地址 | **`reserve0`** | 兑 token0 |

```java
private static final BigInteger AMOUNT_OUT_MAX = new BigInteger("10000000000000000000"); // 10 ether
private static final BigInteger RESERVE_MAX = new BigInteger("79228162514264337593543950335"); // uint96.max

static byte[] toFixed(byte[] src, int len) {
    byte[] dst = new byte[len];
    if (src.length == 0) return dst;
    int start = (src[0] == 0 && src.length > 1) ? 1 : 0;
    int copy = Math.min(len, src.length - start);
    System.arraycopy(src, src.length - copy, dst, len - copy, copy);
    return dst;
}

/** pair(20) + amountOut(8) + r(12) = 40；0/1 共用，靠 to 地址区分方向 */
public static byte[] packSkim01(String pair, BigInteger amountOut, BigInteger reserve) {
    if (amountOut.signum() < 0 || amountOut.compareTo(AMOUNT_OUT_MAX) > 0) {
        throw new IllegalArgumentException("amountOut");
    }
    if (reserve.signum() < 0 || reserve.compareTo(RESERVE_MAX) > 0) {
        throw new IllegalArgumentException("reserve");
    }
    byte[] out = new byte[40];
    System.arraycopy(toFixed(Numeric.hexStringToByteArray(pair), 20), 0, out, 0, 20);
    System.arraycopy(toFixed(amountOut.toByteArray(), 8), 0, out, 20, 8);
    System.arraycopy(toFixed(reserve.toByteArray(), 12), 0, out, 28, 12);
    return out;
}

public static String packSkim01Hex(String pair, BigInteger amountOut, BigInteger reserve) {
    return Numeric.toHexString(packSkim01(pair, amountOut, reserve));
}
```

### 2.3 调用示例

```java
// 1) 读 pair.getReserves() → (r0, r1)
BigInteger amountOut = ...;

// --- skim0：兑 token1，发往 SkimUtil0，打包 r1 ---
String data0 = SkimPacker.packSkim01Hex(pair, amountOut, r1);
sendRawCalldata(web3j, credentials, skimUtil0Address, data0, chainId, nonce, gasPrice, gasLimit);

// --- skim1：兑 token0，发往 SkimUtil1，打包 r0 ---
String data1 = SkimPacker.packSkim01Hex(pair, amountOut, r0);
sendRawCalldata(web3j, credentials, skimUtil1Address, data1, chainId, nonce + 1, gasPrice, gasLimit);
```

> Batch 才在 calldata 里带 `dir` 字节；单笔 `SkimUtil0`/`SkimUtil1` 用两个合约拆开，省掉方向字段。

### 2.4 行为要点

- `calldatasize != 40` → 空 revert。
- reserve 变化（抢跑等）→ 空 revert（单笔合约**不会**静默成功）。
- 合约为 `payable`，建议 `value=0`。

---

## 3. SkimUtilBatch

### 3.1 Calldata 布局

顺序拼接定长项，每项 **41 字节**：

```text
| dir(1) | pair(20) | amountOut(8 uint64) | r(12 uint96) |
```

- `dir=0` → 比 `reserve1`，兑 token1；`dir=1` → 比 `reserve0`，兑 token0
- `calldatasize` 必须为 41 的正整数倍
- `amountOut` ≤ `10 ether`；`r` ≤ `uint96.max`

### 3.2 失败策略（与单笔不同）

| 情况 | 行为 |
| --- | --- |
| 单项 reserve 不匹配 | **跳过该项**，继续后面 |
| 单项 `swap` 失败 | **跳过该项**，继续后面 |
| calldata 长度非法（非 41 倍数或为空） | **整笔 revert** |

适合一笔里混合多个机会：部分失败不影响已成功项（同一交易内已成功的 state 变更仍保留，因跳过用的是 `pop(call)` / 条件不进入，不会把整笔 tx revert 掉）。

> 注意：EVM 同一笔交易内，若后面逻辑也不 revert，前面成功的 `swap` 会提交。单项失败只是不再执行该次 swap。

### 3.3 Java 打包

```java
/** dir(1) + pair(20) + amountOut(8) + r(12) = 41 */
public static byte[] packBatchItem(int dir, String pair, BigInteger amountOut, BigInteger reserve) {
    if (dir != 0 && dir != 1) throw new IllegalArgumentException("dir");
    if (amountOut.signum() < 0 || amountOut.compareTo(AMOUNT_OUT_MAX) > 0) {
        throw new IllegalArgumentException("amountOut");
    }
    if (reserve.signum() < 0 || reserve.compareTo(RESERVE_MAX) > 0) {
        throw new IllegalArgumentException("reserve");
    }
    byte[] out = new byte[41];
    out[0] = (byte) dir;
    System.arraycopy(toFixed(Numeric.hexStringToByteArray(pair), 20), 0, out, 1, 20);
    System.arraycopy(toFixed(amountOut.toByteArray(), 8), 0, out, 21, 8);
    System.arraycopy(toFixed(reserve.toByteArray(), 12), 0, out, 29, 12);
    return out;
}

/** 拼接多项（每项固定 41 字节） */
public static byte[] packBatch(byte[]... items) {
    int total = 0;
    for (byte[] it : items) {
        if (it.length != 41) throw new IllegalArgumentException("item len");
        total += it.length;
    }
    byte[] out = new byte[total];
    int o = 0;
    for (byte[] it : items) {
        System.arraycopy(it, 0, out, o, it.length);
        o += it.length;
    }
    return out;
}

public static String packBatchHex(byte[]... items) {
    return Numeric.toHexString(packBatch(items));
}
```

### 3.4 混合调用示例

```java
byte[] a = packBatchItem(0, pair1, amount1Out, r1); // skim0
byte[] b = packBatchItem(1, pair2, amount0Out, r0); // skim1
String data = packBatchHex(a, b);

sendRawCalldata(web3j, credentials, skimUtilBatchAddress, data, chainId, nonce, gasPrice, gasLimit);
```

也可 `2 x dir0`、`2 x dir1`，只要每项 41 字节、reserve/amount 正确。

### 3.5 示例 calldata（结构示意）

单笔 `SkimUtil0`（40 bytes）：

```text
0x<pair20><amountOut8><r1_12>
```

Batch 两项（82 bytes）：

```text
0x
  <dir0_1><pairA20><amountOutA8><rA12>
  <dir1_1><pairB20><amountOutB8><rB12>
```

---

## 4. UtilTest（标准 ABI）

源码：`new/evm/UtilTest.sol`。

### 4.1 接口一览

| 方法 | 类型 | 说明 |
| --- | --- | --- |
| `constructor(address initialOwner)` | — | `initialOwner != 0` |
| `owner()` | `view` → `address` | 当前 owner |
| `sweepToken(address token, uint256 amount)` | `payable` | ERC20 `transfer` 到 owner |
| `refundETH()` | `payable` | 合约全部 ETH 转给 owner |
| `getContractFromAccountByNonce(bytes25 packed)` | `pure` → `address[]` | CREATE 地址推算 |
| `getContractsExist(bytes25 packed)` | `view` → `bool[]` | 推算后查 `extcodesize` |
| `receive` / `fallback` | `payable` | 空实现，可收 ETH |

### 4.2 `bytes25 packed` 编码

```text
abi.encodePacked(address account, uint24 nonceBegin, uint16 num)
= account(20) || nonceBegin(3) || num(2)   // 共 25 字节
```

```java
public static byte[] packCreateQuery(String account, int nonceBegin, int num) {
    if ((nonceBegin & ~0xFFFFFF) != 0) throw new IllegalArgumentException("nonceBegin uint24");
    if ((num & ~0xFFFF) != 0) throw new IllegalArgumentException("num uint16");
    byte[] out = new byte[25];
    System.arraycopy(SkimPacker.toFixed(Numeric.hexStringToByteArray(account), 20), 0, out, 0, 20);
    out[20] = (byte) ((nonceBegin >>> 16) & 0xff);
    out[21] = (byte) ((nonceBegin >>> 8) & 0xff);
    out[22] = (byte) (nonceBegin & 0xff);
    out[23] = (byte) ((num >>> 8) & 0xff);
    out[24] = (byte) (num & 0xff);
    return out;
}
```

Web3j 对 `bytes25` 可用 `org.web3j.abi.datatypes.generated.Bytes25`：

```java
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.generated.Bytes25;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.DynamicArray;
import org.web3j.abi.datatypes.Bool;

byte[] packed25 = packCreateQuery(deployer, nonceBegin, num);
Bytes25 arg = new Bytes25(packed25);

// eth_call: getContractFromAccountByNonce
Function fn = new Function(
        "getContractFromAccountByNonce",
        Arrays.asList(arg),
        Arrays.asList(new TypeReference<DynamicArray<Address>>() {})
);
String data = FunctionEncoder.encode(fn);
// web3j.ethCall(Transaction.createEthCallTransaction(from, utilTest, data), latest)

// eth_call: getContractsExist
Function existFn = new Function(
        "getContractsExist",
        Arrays.asList(arg),
        Arrays.asList(new TypeReference<DynamicArray<Bool>>() {})
);
```

### 4.3 写方法编码示例

```java
import org.web3j.abi.datatypes.generated.Uint256;

// sweepToken(token, amount)
Function sweep = new Function(
        "sweepToken",
        Arrays.asList(new Address(token), new Uint256(amount)),
        Collections.emptyList()
);
String sweepData = FunctionEncoder.encode(sweep);

// refundETH()
Function refund = new Function("refundETH", Collections.emptyList(), Collections.emptyList());
String refundData = FunctionEncoder.encode(refund);
```

也可用 `web3j-codegen` 根据 ABI 生成 Wrapper；若暂时没有 artifact，用上述 `FunctionEncoder` 即可。

### 4.4 权限说明

- `sweepToken` / `refundETH`：**无 onlyOwner**，任意地址可调，但资金只转到构造时的 `_owner`。
- 部署时务必传入正确 `initialOwner`。

---

## 5. 链下准备流程（Skim）

推荐步骤：

1. 发现 pair 上有超额（`balanceOf(pair) > reserve`）。
2. `getReserves()` 取 `(r0, r1)`，按方向选定要比对的 `r` 与 `amountOut`。
3. **发交易前再次读 reserve**（或用 `eth_call` 模拟）；单笔合约 reserve 变了会 revert，Batch 会跳过该项。
4. 组 calldata → 签名发送；可对 `SkimUtil0` / `SkimUtil1` / `SkimUtilBatch` 分别 `eth_estimateGas`，选更低者。
5. 收款地址固定为 `0x9f8c767a…8AB2`，确认监控/归集该地址。

`eth_call` 模拟 raw calldata：

```java
Transaction.createEthCallTransaction(from, skimUtilAddress, dataHex);
web3j.ethCall(tx, DefaultBlockParameterName.LATEST).send();
```

---

## 6. Gas / 选型建议

| 场景 | 建议合约 |
| --- | --- |
| 仅兑 token1 | `SkimUtil0` |
| 仅兑 token0 | `SkimUtil1` |
| 多笔混合 / 允许部分失败 | `SkimUtilBatch` |
| CREATE 地址预测与是否已部署 | `UtilTest` |

单笔失败要**整笔失败**时用 `SkimUtil0/1`；希望一笔扫多个机会、失败跳过时用 `SkimUtilBatch`。

---

## 7. 维护

- 合约源码：`new/evm/SkimUtil01.sol`、`SkimUtilBatch.sol`、`UtilTest.sol`
- Foundry 回归：`test/UtilTestSkimBsc.t.sol`
- 收款地址或编码宽度变更后，必须同步改 Java 打包工具与本文档。
