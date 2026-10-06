# CTF 学习日志

> 记录 Web 安全学习历程

## 目录说明

| 目录 | 内容 |
|---|---|
| **`logs/`** | **每日日志** —— 从 2026-09-28 开始，一天一篇，记录每天学的东西 |
| **`notes/`** | **日志之前的一次总笔记** —— 把此前学过的 task1~7 和实战题，一次性汇总整理的知识点 |
| **`writeups/`** | **按赛事归档的 WP** —— 一个赛事一个文件夹（含赛事总览 README），一题一篇 |

**区分**：
- `notes/` = **旧知识的"存量总结"**（一次性的、系统的）—— 按**知识点**组织
- `logs/` = **新知识的"每日增量"**（持续的、流水式的）—— 按**日期**组织
- `writeups/` = **题目的最终分析** —— 按**赛事**组织。日志里的题目细节都会被抽到这里，日志只留当天流水 + 链接

```
writeups/
├── README.md              ← 赛事总索引
├── 极客大挑战SYC/          ← 一个赛事一个文件夹
│   ├── README.md          ←   赛事总览（各届对比 / 考点分布 / 复盘）
│   ├── 2023-unsign.md     ←   一题一篇
│   └── 2024-ez_http.md
├── PolarCTF/
├── 0xGame/
├── NSSCTF/
└── 靶场/                   ← 非赛事（公开练习平台）单独归一类
```

> **为什么按赛事分**：**一道题只存在于一个地方**。
> 以前题目分析散在 `logs/` 里，同一道题会被不同天的会话重复记录 —— 赛事目录从结构上消灭了这个问题。

### 日志日期归属规则（跨零点必看）

| 情况 | 记在哪天 |
|---|---|
| 事情发生在当天 00:00~23:59 之间 | **当天**，文件名 = 当天日期 |
| **一件事跨了零点**（如 22:59 开始 → 次日 01:47 结束） | **整段记在它开始的那一天**，不要拆成两半 |
| 第二天**重新开始**做的东西 | 记在**第二天** —— 不许回填到前一天 |

> **唯一判据是「哪天开始动手」，不是「现在几点」、也不是「什么时候做完」。**

跨零点的那篇，**开头要用一句 `>` 注明起止时间和归属**，例如
`> 说明：本日跨到凌晨（白名单命令执行 22:59 → 次日 01:47），**全部记在 10-02**。`

写文件名之前先跑 `Get-Date -Format 'yyyy-MM-dd'`，别凭记忆、别顺着上一篇往下写。
完整规则见 [`logs/_template.md`](./logs/_template.md) 顶部。

## 每日日志

| 日期 | 主题 | 标签 |
|---|---|---|
| [2026-09-28](./logs/2026-09-28.md) | un8 POP链 + SoapClient SSRF | `反序列化` `SSRF` |
| [2026-09-30](./logs/2026-09-30.md) | un9 通关：内置类 SSRF + CRLF 抢 Content-Type | `反序列化` `SoapClient` `CRLF注入` |
| [2026-10-01](./logs/2026-10-01.md) | un9 自己复现 + 序列化格式 / PHP 版本差异 / 编码坑 | `反序列化` `序列化格式` `PHP版本` |
| [2026-10-02](./logs/2026-10-02.md) | 反序列化深挖（逃逸 / 引用 / create_function）+ 0xGame 三题（含白名单命令执行） | `反序列化` `引用` `RCE` `通配符` |
| [2026-10-03](./logs/2026-10-03.md) | PolarCTF：swp（PCRE 回溯上限绕过 `preg_match`）+ seek flag（三段式信息收集 / Cookie 越权） | `正则绕过` `信息收集` `Cookie越权` |
| [2026-10-04](./logs/2026-10-04.md) | **极客大挑战三届连做**：2025 `popself`（6 跳链 + 双 md5 魔术哈希）<br>2023 `unsign`（3 跳链 + `echo` 断点法）<br>2024 `ez_http`（六级链 + JWT HS256 伪造） | `反序列化` `POP链` `JWT` `魔术哈希` |
| [2026-10-06](./logs/2026-10-06.md) | 极客大挑战三道新题：`circle`（内联脚本 `atob` + base64）<br>`perfect-waf`（文件上传双后缀绕 WAF）<br>`rce_me`（四层绕过 + PHP 参数名解析怪癖） | `前端源码` `base64` `文件上传` `WAF绕过` `代码审计` `魔术哈希` |

## 总笔记（此前学习汇总）

> 这是写日志之前的一次性总结，覆盖 task1~7 及实战知识点。

| # | 主题 | 来源 |
|---|---|---|
| 01 | [HTTP 基础](./notes/01-HTTP基础.md) | task1 |
| 02 | [Python / requests](./notes/02-Python-requests.md) | task2 |
| 03 | [PHP 基础与弱类型绕过](./notes/03-PHP弱类型绕过.md) | task3 |
| 04 | [SQL 注入](./notes/04-SQL注入.md) | task4 |
| 05 | [文件上传](./notes/05-文件上传.md) | task5 |
| 06 | [文件包含 LFI + 命令注入](./notes/06-文件包含LFI.md) | task6 |
| 07 | [PHP 反序列化与 POP 链](./notes/07-PHP反序列化.md) | task7 |
| 08 | [SSRF](./notes/08-SSRF.md) | 实战（un9） |
| 09 | [XXE](./notes/09-XXE.md) | 实战（WelCTF） |
| 10 | [信息收集与代码审计](./notes/10-信息收集与代码审计.md) | 进阶补丁 |
| 11 | [知识总结](./notes/11-知识总结.md) | 综合 |
| 12 | [注释当空格与命令绕过](./notes/12-注释当空格与命令绕过.md) | 实战（PHP 5.4 / bash 实测） |
| 13 | [代理 IP 头 XFF 与 X-Real-IP](./notes/13-代理IP头XFF与X-Real-IP.md) | 实战（geekchallenge2024） |
| 14 | [JWT 伪造](./notes/14-JWT伪造.md) | 实战（geekchallenge2024） |

## 赛事 / 靶场进度

### 赛事

| 赛事 | 进度 | 目录 |
|---|---|---|
| **极客大挑战（SYC）** | 2023 `unsign` / 2024 `ez_http`·`perfect-waf`·`circle`·`rce_me` / 2025 `popself` | [writeups/极客大挑战SYC/](./writeups/极客大挑战SYC/README.md) |
| **0xGame** | 字符白名单命令执行 / 奶蛙的博客 / ATP 平台 / `picture`·`signin` 待补 | [writeups/0xGame/](./writeups/0xGame/README.md) |
| **PolarCTF** | `swp` / `seek flag` | [writeups/PolarCTF/](./writeups/PolarCTF/README.md) |
| **NSSCTF** | `Rc3_function` | [writeups/NSSCTF/](./writeups/NSSCTF/README.md) |

### 靶场（非赛事）

| 靶场 | 进度 |
|---|---|
| unserialize-lab | un1~un9 / un10 / un11 搁置 |
| upload-labs | Pass-01~21 |
| lfi-labs | LFI-1~14 + CMD-1~6 |
| sqli-labs | Less-1~21 |

### WP 文档

> **全部赛事 / 题目的索引** → [`writeups/README.md`](./writeups/README.md)

| 赛事 | 题目 | 考点 | 文件 |
|---|---|---|---|
| 极客大挑战 2025 | popself | 6 跳 POP 链 + 双 md5 魔术哈希 | 无 WP（只有日志记录） |
| 极客大挑战 2024 | ez_http | **JWT HS256 伪造 + IP 头枚举 + 分层诊断法** | [2024-ez_http.md](./writeups/极客大挑战SYC/2024-ez_http.md) |
| 极客大挑战 2023 | unsign | 3 跳 POP 链 + `echo` 断点调试 | [2023-unsign.md](./writeups/极客大挑战SYC/2023-unsign.md) |
| 极客大挑战 2024 | perfect-waf | **文件上传：双后缀 `.jpg.php` 绕 WAF（判据不一致）** | [2024-perfect-waf.md](./writeups/极客大挑战SYC/2024-perfect-waf.md) |
| 极客大挑战 2024 | circle | 内联脚本 `atob` + base64（`js/` 目录是幌子） | [2024-circle.md](./writeups/极客大挑战SYC/2024-circle.md) |
| 极客大挑战 2024 | rce_me | **四层绕过 + PHP 参数名解析怪癖 + 魔术哈希** | [2024-rce_me.md](./writeups/极客大挑战SYC/2024-rce_me.md) |
| 0xGame | 字符白名单命令执行 | 白名单 + glob「钓」命令与文件名 | [字符白名单命令执行.md](./writeups/0xGame/字符白名单命令执行.md) |
| PolarCTF | swp | PCRE 回溯上限绕过 `preg_match` | 无 WP（知识点在 [10](./notes/10-信息收集与代码审计.md)、[11](./notes/11-知识总结.md)） |
| PolarCTF | seek flag | 三段式信息收集 + Cookie 越权 | [seek-flag.md](./writeups/PolarCTF/seek-flag.md) |
| NSSCTF | Rc3_function | `create_function` 代码注入 | [Rc3_function.md](./writeups/NSSCTF/Rc3_function.md) |
| unserialize-lab | un9 | **SoapClient SSRF + CRLF 注入** | [unserialize-lab-un9.md](./writeups/靶场/unserialize-lab-un9.md) |

## 学习路线

| 模块 | 状态 |
|---|---|
| HTTP 基础 | 已完成 |
| Python requests | 已完成 |
| PHP 弱类型 | 已完成 |
| SQL 注入 | 已完成 |
| 文件上传 | 已完成 |
| 文件包含 LFI | 已完成 |
| 命令注入 | 已完成 |
| PHP 反序列化 | 已完成 |
| 信息收集 / 代码审计 | 已完成 |
| SSRF | 已完成 |
| JWT | 已完成 |
| XXE |  |

## 链接

- GitHub: [@sleephong](https://github.com/sleephong)
