```bash

 package tool.util;

import okhttp3.ConnectionPool;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.apache.http.client.config.RequestConfig;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

public class OkLinkStableDemo {

    private static final MediaType JSON_UTF8 = MediaType.parse("application/json; charset=utf-8");

    /**
     * OKLink 浏览器接口（非官方开放 API）：部分环境会对 Apache HttpClient 4.x 的 TLS ClientHello 做拦截，
     * 表现为握手阶段 {@link javax.net.ssl.SSLHandshakeException} / EOF。
     *
     * <p>PayTool 工程锁定 Java 8，因此这里优先使用已在 {@code pom.xml} 中引入的 OkHttp3（TLS/ALPN 行为通常更接近浏览器），
     * 若仍失败再回退到 Apache HttpClient。</p>
     */
    public static String postHoldersToken(String holder, int offset, int limit, String apiKey) throws Exception {
        long t = System.currentTimeMillis();
        String url = "https://www.oklink.com/api/explorer/v2/bsc/addresses/" + holder
                + "/holders/token?t=" + t;

        String jsonBody = "{\"offset\":" + offset + ",\"limit\":" + limit + ",\"valuable\":false}";

        try {
            return postHoldersTokenWithOkHttp(url, jsonBody, apiKey);
        } catch (javax.net.ssl.SSLHandshakeException e) {
            return postHoldersTokenWithApache(url, jsonBody, apiKey);
        }
    }

    private static String postHoldersTokenWithOkHttp(String url, String jsonBody, String apiKey) throws Exception {
        // 每次新建 client：避免连接池复用带来的偶发 reset（demo 场景可接受）
        OkHttpClient client = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(20, TimeUnit.SECONDS)
                .writeTimeout(20, TimeUnit.SECONDS)
                .callTimeout(30, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .connectionPool(new ConnectionPool(0, 1, TimeUnit.MILLISECONDS)) // effectively no pooling
                .followRedirects(true)
                .followSslRedirects(true)
                .build();

        Request req = new Request.Builder()
                .url(url)
                .header("accept", "application/json")
                .header("accept-language", "zh-CN,zh;q=0.9,en;q=0.8")
                .header("app-type", "web")
                .header("origin", "https://www.oklink.com")
                .header("referer", "https://www.oklink.com/")
                .header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36")
                .header("x-apikey", apiKey)
                // OkHttp 会自动加 gzip 等；不要强行声明 br/zstd
                .post(RequestBody.create(JSON_UTF8, jsonBody))
                .build();

        try (Response resp = client.newCall(req).execute()) {
            int status = resp.code();
            ResponseBody body = resp.body();
            String text = body == null ? "" : body.string();
            if (status / 100 == 2) {
                return text;
            }
            throw new RuntimeException("HTTP " + status + ": " + text);
        }
    }

    private static String postHoldersTokenWithApache(String url, String jsonBody, String apiKey) throws Exception {
        RequestConfig config = RequestConfig.custom()
                .setConnectTimeout(10_000)
                .setConnectionRequestTimeout(10_000)
                .setSocketTimeout(20_000)
                .build();

        // 关闭连接复用/ cookie，降低被中间设备复用连接影响的概率
        try (CloseableHttpClient client = HttpClients.custom()
                .disableConnectionState()
                .disableCookieManagement()
                .build()) {

            for (int attempt = 1; attempt <= 3; attempt++) {
                HttpPost post = new HttpPost(url);
                post.setConfig(config);

                post.setHeader("accept", "application/json");
                post.setHeader("content-type", "application/json; charset=utf-8");
                post.setHeader("accept-language", "zh-CN,zh;q=0.9,en;q=0.8");
                post.setHeader("app-type", "web");
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
                } catch (javax.net.ssl.SSLHandshakeException | java.net.SocketException se) {
                    if (attempt == 3) throw se;
                    Thread.sleep(250L * attempt);
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
