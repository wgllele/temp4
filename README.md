```bash

 package tool.util;

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
    public static void main(String[] args) throws Exception {
        String holder = "0xe22dd309bc8b3220a35fff9959afa57c6e188859";
        int offset = 40;
        int limit = 20;
        String apiKey = "YOUR_X_APIKEY";
        System.out.println(postHoldersToken(holder, offset, limit, apiKey));
    }
}

```
