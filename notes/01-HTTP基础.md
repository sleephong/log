# 01 · HTTP 基础（task1）

> 状态：✅ 已掌握

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

---

## 二、重点请求头（改头的意图）

| 头 | 作用 | 绕过场景 |
|---|---|---|
| **Referer** | 来源页面 | 骗"来自某站"（如 `https://www.xidian.edu.cn/`） |
| **User-Agent** | 浏览器/客户端标识 | 骗"某浏览器"（如 `MoeDedicatedBrowser`） |
| **X-Forwarded-For (XFF)** | 记录的客户端 IP | 传 `127.0.0.1` 骗"本地访问" |
| **Cookie** | 会话标识 | 伪造登录态 |
| **Content-Type** | 请求体格式 | `application/x-www-form-urlencoded` / `multipart/form-data` |

**⭐ 易错：拼写**
```
Referer          （不是 refener / referrer）
User-Agent       （不是 user-agaent）
X-Forwarded-For  （不是 X-Forward-For）
```

---

## 三、状态码

| 码 | 含义 |
|---|---|
| **200** | 成功 |
| **302** | 重定向 |
| **403** | **禁止访问**（有权限问题） |
| **404** | **找不到**（路径不存在） |
| **405** | 方法不允许（换 GET/POST/PUT 试） |
| **500** | 服务器错误 |

**⭐ 易错：403 ≠ 404**
- `403` = 资源存在，但你没权限
- `404` = 资源不存在

---

## 四、HTTP 方法

| 方法 | 语义 | 幂等 |
|---|---|---|
| GET | 读 | ✅ |
| POST | 提交 | ❌ |
| **PUT** | 整体替换 | ✅ |
| PATCH | 部分修改 | ❌ |
| DELETE | 删除 | ✅ |
| HEAD | 只要响应头 | ✅ |
| OPTIONS | 查支持的方法 | ✅ |

**⭐ 题目出现"Try other methods"→ 换方法试。**

---

## 五、Browser 工具

| 操作 | 作用 |
|---|---|
| **F12 → Elements** | 看/改当前 DOM（**不是源码**） |
| **Ctrl+U** | ⭐ 看**原始 HTML 源码**（注释 `<!-- -->` 常藏 flag/提示） |
| **F12 → Network** | 看所有请求/响应（找接口、看参数） |
| **F12 → Network → Preserve log** | 保留跳转前的请求 |

**⭐ 关键**：**浏览器渲染≠源码**，注释和隐藏元素必须看 `Ctrl+U`。

---

## 六、requests 基础

```python
import requests

# GET（参数用 params）
res = requests.get(url, params={"a": "1"}, headers={...}, cookies={...})

# POST（参数用 data）
res = requests.post(url, data={"a": "1"}, headers={...}, cookies={...})

# 读取响应
res.text           # 正文（字符串）
res.headers        # 响应头（flag 常在这）  ⚠️ 不是 .head
res.status_code    # 状态码
res.cookies        # 返回的 cookie
res.json()         # 解析 JSON
```

**⭐ 易错**：
```
params → GET 的参数
data   → POST 的参数
res.text  / res.headers / res.status_code （没有 res.txt）
```

---

## 七、一句话

> **HTTP = 请求行 + 头 + 空行 + 体**。**GET 参数在 URL，POST 参数在 body**。**改头的三个重点：Referer（来源）、User-Agent（浏览器）、X-Forwarded-For（127.0.0.1）**。**403=禁止、404=找不到，别搞混**。
