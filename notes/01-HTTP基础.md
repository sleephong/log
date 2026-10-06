# 01 · HTTP 基础（task1）

## 一、请求结构

```
GET /path?id=1 HTTP/1.1          ← 请求行（方法 / 路径?参数 / 版本）
Host: example.com                ← 请求头
Referer: https://xxx.com
User-Agent: Mozilla/5.0
X-Forwarded-For: 127.0.0.1
Cookie: PHPSESSID=xxx
Content-Type: application/x-www-form-urlencoded
                                 ← 空行（必须有！）
id=1&name=abc                    ← 请求体（POST 才有）
```

| 部分 | 说明 |
|---|---|
| **URL** | `协议://主机:端口/路径?参数#锚点` |
| **GET 参数** | 在 URL 里（`?id=1&a=2`） |
| **POST 参数** | 在**请求体**里 |
| **`?id=1` 那段** | 叫**参数（query）**，不叫 payload |

## 二、重点请求头（改头的意图）

| 头 | 作用 | 绕过场景 |
|---|---|---|
| **Referer** | 来源页面 | 骗"来自某站"（如 `https://www.xidian.edu.cn/`） |
| **User-Agent** | 浏览器/客户端标识 | 骗"某浏览器"（如 `MoeDedicatedBrowser`） |
| **X-Forwarded-For (XFF)** | 记录的客户端 IP（**列表**，逗号分隔） | **只有代码读 `$_SERVER['HTTP_X_FORWARDED_FOR']` 时才有用**；校验 TCP 层 `REMOTE_ADDR` 时**完全无效** → [13](./13-代理IP头XFF与X-Real-IP.md) |
| **X-Real-IP** | 单值 IP 快照 | 同上。**实测 geekchallenge2024 只认这个头，写 XFF 被拒** → [13](./13-代理IP头XFF与X-Real-IP.md) |
| **Cookie** | 会话标识 | 伪造登录态 |
| **Content-Type** | 请求体格式 | `application/x-www-form-urlencoded` / `multipart/form-data` |

**易错：拼写**
```
Referer          （不是 refener / referrer）
User-Agent       （不是 user-agaent）
X-Forwarded-For  （不是 X-Forward-For）
```

**IP 头不是「改一个就够」，要枚举**（详见 [13](./13-代理IP头XFF与X-Real-IP.md)）：
`X-Forwarded-For` / `X-Real-IP` / `Client-IP` / `X-Client-IP` / `Remote-Addr` / `X-Remote-Addr` / `X-Originating-IP` / `Forwarded` / `True-Client-IP`
全部无效 → 校验的是 **TCP 层 `REMOTE_ADDR`**，只能靠 [SSRF](./08-SSRF.md)。

### 2.1 请求头 → PHP 的 `$_SERVER` 键（**看到源码就能反推该发什么头**）

| 步骤 | 变换 |
|---|---|
| ① 头名统一**转大写** | `Starven` → `STARVEN` |
| ② `-` 换成 `_` | `X-Real-IP` → `X_REAL_IP` |
| ③ 前面加 `HTTP_` | → **`HTTP_X_REAL_IP`** |

| 你发的头 | PHP 里的键 |
|---|---|
| `Starven: I_Want_Flag` | `$_SERVER['HTTP_STARVEN']` |
| `X-Real-IP: 127.0.0.1` | `$_SERVER['HTTP_X_REAL_IP']` |
| `Referer: https://...` | `$_SERVER['HTTP_REFERER']` |
| `User-Agent: curl` | `$_SERVER['HTTP_USER_AGENT']` |
| `Cookie: a=1` | `$_SERVER['HTTP_COOKIE']` |
| `Content-Type: ...` | `$_SERVER['CONTENT_TYPE']` **无 `HTTP_` 前缀** |
| `Content-Length: ...` | `$_SERVER['CONTENT_LENGTH']` **无 `HTTP_` 前缀** |

> **唯二的例外是 `Content-Type` 和 `Content-Length`**，其余自定义头一律 `HTTP_` + 大写 + 下划线。

### 2.2 大小写：**头名不敏感，参数名/值敏感**

| 层 | 区分大小写？ | 实测证据 |
|---|---|---|
| **HTTP 头名** | **不敏感**（RFC 7230） | `Starven` / `starven` / `STARVEN` / `sTaRvEn` 全 PASS；`content-type` / `CoNtEnT-TyPe` 都认 |
| **媒体类型值** | 不敏感（RFC 2045） | `APPLICATION/X-WWW-FORM-URLENCODED` 也认 |
| 头**值** | **敏感** | `I_Want_Flag` 精确；`i_want_flag` / `I_WANT_FLAG` 全挂 |
| **Cookie 名** | 敏感 | `token` PASS；`Token` / `TOKEN` 全挂 |
| **GET / POST 参数名** | 敏感 | `welcome` PASS；`Welcome` 卡第一关 |
| **JWT / JSON 字段名** | 敏感 | `hasFlag` PASS；`HasFlag` / `hasflag` 全挂 |

**根因**：头名不敏感是 **HTTP 协议规定**的（Apache 规范化后再映射成 `$_SERVER` 键）；
参数名敏感是因为 **PHP 数组键 / JSON 对象键本身区分大小写**。

**冒号前后的空白（un9 靶机实测，见 [un9 WP 附录 A7](../writeups/靶场/unserialize-lab-un9.md)）**：

| 位置 | 规范 | 实测 |
|---|---|---|
| 冒号**后**空格 | OWS，可有可无 | 0 个 / 1 个 / 3 个都行 |
| 冒号**前**空格 | 规范**禁止**，服务器**必须**回 400 | 靶机 Apache 2.4.10 **实测接受**（1/2 个空格、制表符、连 `Host` 都行），属 **CVE-2016-8743**（2.2.0~2.4.23，2.4.25 才修）→ **WAF 绕过的土壤** |
| 重复的同名头 | **首值优先** | 靠这个才能「抢在原本的头前面」（un9 的 CRLF 注入原理） |

> **位置比大小写更重要**：HackBar / Burp 里手写自定义头时，如果插件把它当普通键值处理（写进了 POST data 区），那它就**不是 HTTP 头了**，立刻失效。

### 2.3 PHP 参数名解析怪癖：点号 / 空格 / `[`（**实测规则表**）

**背景**：PHP 收到 `a.b=1` 会把键名变成 `a_b`。当源码里写的键名**本身带点号**时（如 `$_POST["__2024.geekchallenge.ctf"]`），**直接传是传不进去的** —— 必须借 PHP 解析器的怪癖把点号保住。

**本机 PHP 5.4.45 实测**（起 `php -S` 打印 `$_POST` 真实键名）：

| 发送的参数名 | PHP 解析出的键名 | 说明 |
|---|---|---|
| **`[a` / `[a]` / `[_x.y`** | **整个变量被丢弃** | **以 `[` 开头 → 变量没了** |
| `a[` | `a_` | 未闭合 `[` → 转成 `_` |
| `a[.b` | `a_.b` | `[`→`_`，**后面的点号保住** |
| `a.b[` | `a_b_` | `[` **之前**的点号照常变 `_` |
| `a.b` / `a b` | `a_b` | 无 `[` 时，点号和空格都变 `_` |
| `_[2024.geekchallenge.ctf` | `__2024.geekchallenge.ctf` | `[`→`_`，后面点号全保住 |
| `__[2024.geekchallenge.ctf` | `___2024.geekchallenge.ctf` | 多出一个 `_` |
| `a[]` / `a[b]` | `a`（数组） | 正常数组语法 |

**归纳成两条规则**：

```
规则① 参数名 **以 `[` 开头**        → 整个变量被丢弃（与点号无关）
规则② 存在 **未闭合的 `[`** 时：
        `[` 之前的点号/空格  →  照常转成 `_`
        `[` 本身             →  转成 `_`
        `[` 之后的点号       →  **不转换**，原样保留
```

**实战配方**（要拿到键名 `__2024.geekchallenge.ctf`）：

```
目标 = `_` + `_` + `2024.geekchallenge.ctf`
         ↓     ↓
      明写  让 `[` 来转
                    ↓
参数名 = _[2024.geekchallenge.ctf     ← `[` 必须恰好在第 2 位
```

- `[` 在第 1 位 → 触发规则①，整条丢弃
- `[` 再往后 → `[` 之前的点号会被转掉
- **所以只有 `_[2024...` 这一种写法成立**

**两种数据都受影响**：`$_GET` / `$_POST` / `$_COOKIE` 的参数名走同一套解析。

> **验证方式**：`?a.b=1&a[.b=2&[_x.y=3` 打到本机 `php -S`，`var_dump($_GET)` 看一眼键名，比读源码快。
>
> **相关题**：极客大挑战 2024 `rce_me`（源码里键名带点号，正解就是这个 `_[` 技巧）。

## 三、状态码

| 码 | 含义 |
|---|---|
| **200** | 成功 |
| **302** | 重定向 |
| **403** | **禁止访问**（有权限问题） |
| **404** | **找不到**（路径不存在） |
| **405** | 方法不允许（换 GET/POST/PUT 试） |
| **500** | 服务器错误 |

**易错：403 ≠ 404**
- `403` = 资源存在，但你没权限
- `404` = 资源不存在

## 四、HTTP 方法

| 方法 | 语义 | 幂等 |
|---|---|---|
| GET | 读 | 是 |
| POST | 提交 | 否 |
| **PUT** | 整体替换 | 是 |
| PATCH | 部分修改 | 否 |
| DELETE | 删除 | 是 |
| HEAD | 只要响应头 | 是 |
| OPTIONS | 查支持的方法 | 是 |

**题目出现"Try other methods"→ 换方法试。**

## 五、Browser 工具

| 操作 | 作用 |
|---|---|
| **F12 → Elements** | 看/改当前 DOM（**不是源码**） |
| **Ctrl+U** | 看**原始 HTML 源码**（注释 `<!-- -->` 常藏 flag/提示） |
| **F12 → Network** | 看所有请求/响应（找接口、看参数） |
| **F12 → Network → Preserve log** | 保留跳转前的请求 |

**关键**：**浏览器渲染≠源码**，注释和隐藏元素必须看 `Ctrl+U`。

## 六、requests 基础

```python
import requests

# GET（参数用 params）
res = requests.get(url, params={"a": "1"}, headers={...}, cookies={...})

# POST（参数用 data）
res = requests.post(url, data={"a": "1"}, headers={...}, cookies={...})

# 读取响应
res.text           # 正文（字符串）
res.headers        # 响应头（flag 常在这）  不是 .head
res.status_code    # 状态码
res.cookies        # 返回的 cookie
res.json()         # 解析 JSON
```

**易错**：
```
params → GET 的参数
data   → POST 的参数
res.text  / res.headers / res.status_code （没有 res.txt）
```

## 七、一句话

> **HTTP = 请求行 + 头 + 空行 + 体**。**GET 参数在 URL，POST 参数在 body**。**改头的三个重点：Referer（来源）、User-Agent（浏览器）、IP 头（`X-Forwarded-For` / `X-Real-IP` —— 要枚举，别只试一个）**。**头名不区分大小写，参数名区分大小写**。**403=禁止、404=找不到，别搞混**。
