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

import org.apache.http.client.config.RequestConfig;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

import java.nio.charset.StandardCharsets;

public class OkLinkStableDemo {

    public static String postHoldersToken(String holder, int offset, int limit, String apiKey) throws Exception {
        long t = System.currentTimeMillis();
        String url = "https://www.oklink.com/api/explorer/v2/bsc/addresses/" + holder
                + "/holders/token?t=" + t;

        String jsonBody = "{\"offset\":" + offset + ",\"limit\":" + limit + ",\"valuable\":false}";

        RequestConfig config = RequestConfig.custom()
                .setConnectTimeout(10_000)
                .setConnectionRequestTimeout(10_000)
                .setSocketTimeout(10_000)
                .build();

        // 关键：关闭连接复用，减少 reset（代价是慢一点）
        try (CloseableHttpClient client = HttpClients.custom()
                .disableConnectionState()
                .disableCookieManagement()
                .build()) {

            for (int attempt = 1; attempt <= 2; attempt++) {
                HttpPost post = new HttpPost(url);
                post.setConfig(config);

                post.setHeader("accept", "application/json");
                post.setHeader("content-type", "application/json");
                post.setHeader("origin", "https://www.oklink.com");
                post.setHeader("referer", "https://www.oklink.com/");
                post.setHeader("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36");
                post.setHeader("x-apikey", apiKey);

                // 不要声明 br/zstd
                // post.setHeader("accept-encoding", "gzip, deflate");

                // 避免长连接
                post.setHeader("connection", "close");

                post.setEntity(new StringEntity(jsonBody, ContentType.APPLICATION_JSON));

                try (CloseableHttpResponse resp = client.execute(post)) {
                    int status = resp.getStatusLine().getStatusCode();
                    String body = resp.getEntity() == null ? "" : EntityUtils.toString(resp.getEntity(), StandardCharsets.UTF_8);
                    if (status / 100 == 2) return body;
                    throw new RuntimeException("HTTP " + status + ": " + body);
                } catch (java.net.SocketException se) {
                    if (attempt == 2) throw se;
                    Thread.sleep(300); // 简单退避
                }
            }
            throw new RuntimeException("unreachable");
        }
    }
}
```
