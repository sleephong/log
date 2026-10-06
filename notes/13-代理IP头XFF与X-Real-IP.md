# 13 · 代理 IP 头：X-Forwarded-For 与 X-Real-IP

geekchallenge2024 

## 一、本质区别（一句话）

|  | **X-Forwarded-For (XFF)** | **X-Real-IP** |
|---|---|---|
| 本质 | **历史记录**（IP 列表，逗号分隔） | **快照**（单个 IP） |
| 长度 | 多个 —— 逐跳**追加** | 通常 1 个 —— 只保留**最后一跳** |
| 顺序 | **最左 = 最初的真实客户端**，最右 = 最后一跳代理 | 只有最后一跳 |
| 标准性 | **事实标准（de-facto）**，几乎所有代理 / CDN 都发 | **非标**，主要是 Nginx 社区惯例 |
| 典型 Nginx 赋值 | `$proxy_add_x_forwarded_for`（追加） | `$remote_addr`（覆盖） |
| 部署覆盖率 | 高 | 主要 Nginx 生态 |

```
X-Forwarded-For: 203.0.113.7, 10.0.0.5, 10.0.0.9
                 ↑ 真实客户端   ↑ 代理1    ↑ 代理2（最后一跳）
X-Real-IP: 203.0.113.7
```

## 二、PHP 取值

```php
$_SERVER['HTTP_X_FORWARDED_FOR']   // "203.0.113.7, 10.0.0.5, 10.0.0.9"
$_SERVER['HTTP_X_REAL_IP']         // "203.0.113.7"
```

> 规律：头名转大写、`-` 换 `_`、前面加 `HTTP_`。
> 例外：`Content-Type` / `Content-Length` 等有独立键名。

## 三、安全：两者都能伪造，**绝不能裸信**

- 两个头**客户端都能随意伪造** → 直接拿它做鉴权 = 提权 / 白名单绕过。
- 只信**可信代理白名单**里的来源；且应由**边缘代理覆盖**，而不是把客户端带进来的值追加下去。
- 取 XFF 要取**最左边那一段**，并**跳过可信代理**；不能拿整串做比较（`"127.0.0.1, 1.2.3.4" == "127.0.0.1"` 必错）。

```nginx
# 边缘：覆盖，不让客户端自带值穿透进来
proxy_set_header X-Real-IP        $remote_addr;
proxy_set_header X-Forwarded-For  $remote_addr;

# 内层：只信自己前面的可信代理
set_real_ip_from 10.0.0.0/8;
real_ip_header   X-Forwarded-For;
real_ip_recursive on;
```

```php
// 取最左边那一段（逗号分隔）
$first = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '')[0]);
```

**常见坑**：`0.0.0.0`、`127.0.0.1` 与 `::1` 混用、带端口 `127.0.0.1:8080`、IPv4-mapped IPv6 `::ffff:127.0.0.1` —— 只做字符串比较的过滤都能被绕。

## 四、CTF 实证（geekchallenge2024）

> 完整题解 → [极客大挑战2024 · ez_http（六级链）](../writeups/极客大挑战SYC/2024-ez_http.md)（这一节是那道题第 4 关的另一个视角）

同一目标，构造「本地访问」：

| 尝试 | 结果 |
|---|---|
| `X-Forwarded-For: 127.0.0.1` | 返回 `nonono,you're not from local ip` |
| `X-Real-IP: 127.0.0.1` | **过关** |

**结论**：出题人代码**只读 `$_SERVER["HTTP_X_REAL_IP"]`**，写 XFF 完全没用。

### CTF 通用做法：把 IP 头全枚举一遍

```
X-Forwarded-For: 127.0.0.1
X-Real-IP: 127.0.0.1
Client-IP: 127.0.0.1
X-Client-IP: 127.0.0.1
Remote-Addr: 127.0.0.1
X-Remote-Addr: 127.0.0.1
X-Originating-IP: 127.0.0.1
Forwarded: for=127.0.0.1
True-Client-IP: 127.0.0.1
```

## 五、一句话

> **XFF = 逗号分隔的历史记录（最左是真实客户端），X-Real-IP = 单个快照（最后一跳）。**
> **两个都能伪造 → 必须可信代理白名单 + 边缘覆盖，取 XFF 要取最左并跳过可信代理。**
> **CTF 里别只试 XFF：`X-Forwarded-For` / `X-Real-IP` / `Client-IP` / `X-Client-IP` / `Remote-Addr` / `X-Remote-Addr` / `X-Originating-IP` / `Forwarded` / `True-Client-IP` 全枚举。**
