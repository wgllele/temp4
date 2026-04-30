```bash
npm install @near-one/omni-bridge-sdk ethers@^6.0.0
```
```shell
import { OmniBridge, ChainKind, TransactionStatus } from '@near-one/omni-bridge-sdk';
import { ethers } from 'ethers';

async function main() {
// --- 1. 配置环境 ---
// 建议在实际环境中使用环境变量读取私钥
const PRIVATE_KEY = '你的以太坊钱包私钥';
const ETH_RPC_URL = 'https://mainnet.infura.io';

    const provider = new ethers.JsonRpcProvider(ETH_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    // --- 2. 初始化 Omni Bridge SDK ---
    const bridge = new OmniBridge({
        network: 'mainnet', // 对应 NEAR Mainnet
    });

    // --- 3. 定义跨链参数 ---
    const bridgeRequest = {
        sourceChain: ChainKind.Ethereum,
        destinationChain: ChainKind.Base,
        assetAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // 以太坊 USDC 合约地址
        amount: ethers.parseUnits('100', 6), // 跨链 100 USDC (USDC 为 6 位小数)
        recipient: wallet.address,            // 接收地址（通常与发送地址相同）
    };

    try {
        console.log(`🚀 准备跨链: ${ethers.formatUnits(bridgeRequest.amount, 6)} USDC 从 Ethereum 到 Base...`);

        // --- 4. 获取实时报价与手续费 ---
        // Omni Bridge 会计算跨链协议费及目标链 Gas 补偿
        const quote = await bridge.getQuote(bridgeRequest);
        console.log(`💰 预计手续费: ${ethers.formatUnits(quote.fee, 6)} USDC`);
        console.log(`🎁 预计到账金额: ${ethers.formatUnits(quote.expectedAmount, 6)} USDC`);

        // --- 5. 处理 ERC20 授权 (Approve) ---
        console.log("🔍 检查额度授权...");
        const isApproved = await bridge.checkAllowance(bridgeRequest, wallet.address);
        
        if (!isApproved) {
            console.log("✍️ 正在发起 USDC 授权交易...");
            const approveTx = await bridge.approve(bridgeRequest, wallet);
            await approveTx.wait();
            console.log("✅ 授权完成！");
        }

        // --- 6. 发起正式跨链交易 ---
        console.log("📡 正在发送跨链请求至以太坊网络...");
        const transferTx = await bridge.transfer(bridgeRequest, wallet);
        console.log(`🔗 交易已提交! Hash: ${transferTx.hash}`);

        const receipt = await transferTx.wait();
        console.log("✅ 以太坊端交易已确认，等待跨链节点处理...");

        // --- 7. 追踪跨链状态 ---
        // 由于涉及 NEAR 链签名验证，通常需要 1-3 分钟
        const checkStatus = setInterval(async () => {
            const status = await bridge.getTransactionStatus(transferTx.hash);
            console.log(`⏳ 当前状态: ${status.state}`);

            if (status.state === TransactionStatus.COMPLETED) {
                console.log("🎉 跨链成功！资产已到达 Base 链。");
                console.log(`目标链交易 Hash: ${status.destinationHash}`);
                clearInterval(checkStatus);
            } else if (status.state === TransactionStatus.FAILED) {
                console.error("❌ 跨链失败:", status.error);
                clearInterval(checkStatus);
            }
        }, 15000); // 每 15 秒轮询一次

    } catch (error) {
        console.error("🛠️ 发生错误:", error);
    }
}

main();
```

```shell

public class OkLinkHoldersDemo {
    private static BasicClientCookie cookie(String name, String value, String domain, String path) {
        BasicClientCookie c = new BasicClientCookie(name, value);
        c.setDomain(domain);
        c.setPath(path);
        return c;
    }
    /**
     * OKLink holders/token
     *
     * @param holder contract address, example: 0xe22dd3...
     * @param offset paging offset, example: 40
     * @param limit  paging limit, example: 20
     * @param apiKey OKLink x-apikey header value
     */
    public static String postHoldersToken(String holder, int offset, int limit, String apiKey) throws Exception {
        if (holder == null || holder.trim().isEmpty()) {
            throw new IllegalArgumentException("holder is empty");
        }
        if (!holder.startsWith("0x") && !holder.startsWith("0X")) {
            holder = "0x" + holder.trim();
        }
        if (offset < 0) {
            throw new IllegalArgumentException("offset must be >= 0");
        }
        if (limit <= 0) {
            throw new IllegalArgumentException("limit must be > 0");
        }
        if (apiKey == null || apiKey.trim().isEmpty()) {
            throw new IllegalArgumentException("apiKey is empty");
        }
        long t = System.currentTimeMillis();
        String url = "https://www.oklink.com/api/explorer/v2/bsc/addresses/" + holder
                + "/holders/token?t=" + t;
        String jsonBody = "{\"offset\":" + offset + ",\"limit\":" + limit + ",\"valuable\":false}";
        // Cookies（可选：按你给的固定值；注意通常会过期）
        BasicCookieStore cookieStore = new BasicCookieStore();
        cookieStore.addCookie(cookie("devId", "7716c3a0-0bf1-4bee-b676-133678e7b199", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("locale", "zh_CN", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("okg.currentMedia", "xl", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("ok_site_info", "9FjOikHdpRnblJCLiskTJx0SPJiOiUGZvNmIsIyVUJiOi42bpdWZyJye", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("ok_global", "{%22okg_m%22:%22xl%22}", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("oklink.unaccept_cookie", "1", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("first_ref", "https%3A%2F%2Fwww.oklink.com%2Fzh-hans", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("fingerprint_id", "7716c3a0-0bf1-4bee-b676-133678e7b199", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("fp_s", "-1", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("traceId", "2040175143835110002", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("_monitor_extras", "{\"deviceId\":\"qITY-zKzrYXAbapOYxLw-w\",\"eventId\":193,\"sequenceNumber\":193}", "www.oklink.com", "/"));
        cookieStore.addCookie(cookie("__cf_bm", "lom3N9Aj3alrYXHC125HAS9YNtJmcMa9QgAHoqCdoIw-1777514415-1.0.1.1-Wf03A53A6i.VW9Mdj1HrNr3cJ38v7RYR.ojnCDu5V1mnRLag16YLEths.HWfenFiFP0lQRIpXmAvtVTXC2rU3Ij9YItDFKd12hPbqsgAURI", ".oklink.com", "/"));
        RequestConfig config = RequestConfig.custom()
                .setConnectTimeout(10_000)
                .setConnectionRequestTimeout(10_000)
                .setSocketTimeout(10_000)
                .build();
        try (CloseableHttpClient client = HttpClients.custom()
                .setDefaultCookieStore(cookieStore)
                .build()) {
            HttpPost post = new HttpPost(url);
            post.setConfig(config);
            post.setHeader("accept", "application/json");
            post.setHeader("accept-encoding", "gzip, deflate, br, zstd");
            post.setHeader("accept-language", "zh-CN,zh;q=0.9");
            post.setHeader("app-type", "web");
            post.setHeader("devid", "7716c3a0-0bf1-4bee-b676-133678e7b199");
            post.setHeader("origin", "https://www.oklink.com");
            post.setHeader("referer", "https://www.oklink.com/zh-hans/bsc/address/" + holder + "/assets");
            post.setHeader("sec-ch-ua", "\"Not:A-Brand\";v=\"99\", \"Google Chrome\";v=\"145\", \"Chromium\";v=\"145\"");
            post.setHeader("sec-ch-ua-mobile", "?0");
            post.setHeader("sec-ch-ua-platform", "\"macOS\"");
            post.setHeader("sec-fetch-dest", "empty");
            post.setHeader("sec-fetch-mode", "cors");
            post.setHeader("sec-fetch-site", "same-origin");
            post.setHeader("x-apikey", apiKey.trim());
            post.setHeader("x-cdn", "https://static.oklink.com");
            post.setHeader("x-id-group", "2040175143835110002-c-21");
            post.setHeader("x-locale", "zh_CN");
            post.setHeader("x-simulated-trading", "undefined");
            post.setHeader("x-site-info", "9FjOikHdpRnblJCLiskTJx0SPJiOiUGZvNmIsIyVUJiOi42bpdWZyJye");
            post.setHeader("x-utc", "8");
            post.setHeader("x-zkdex-env", "0");
            post.setHeader("user-agent",
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36");
            post.setEntity(new StringEntity(jsonBody, ContentType.APPLICATION_JSON));
            try (CloseableHttpResponse resp = client.execute(post)) {
                int status = resp.getStatusLine().getStatusCode();
                String body = resp.getEntity() == null ? "" : EntityUtils.toString(resp.getEntity(), StandardCharsets.UTF_8);
                if (status / 100 != 2) {
                    StringBuilder sb = new StringBuilder();
                    sb.append("HTTP ").append(status).append("\n");
                    for (Header h : resp.getAllHeaders()) {
                        sb.append(h.getName()).append(": ").append(h.getValue()).append("\n");
                    }
                    sb.append("\n").append(body);
                    throw new RuntimeException(sb.toString());
                }
                return body;
            }
        }
    }
    public static void main(String[] args) throws Exception {
        String holder = "0xe22dd309bc8b3220a35fff9959afa57c6e188859";
        int offset = 40;
        int limit = 20;
        String apiKey = "YOUR_X_APIKEY";
        System.out.println(postHoldersToken(holder, offset, limit, apiKey));
    }
}
```
