# Writeups · 赛事索引

> **按赛事归档的题目分析** —— 一个赛事一个文件夹，**一题一篇**。
> 每日流水在 [`../logs/`](../logs/)，知识点在 [`../notes/`](../notes/)。

---

## 🏆 赛事一览

| 赛事 | 题目 | 通关 | 核心考点 | 目录 |
|---|---|---|---|---|
| **极客大挑战（SYC）** | 3 | 2 ✅ / 1 🔄 | PHP 反序列化 POP 链（3/6 跳）、JWT HS256、IP 头枚举 | [极客大挑战SYC/](./极客大挑战SYC/README.md) |
| **0xGame** | 3（+2 待补） | 3 ✅ | 字符白名单命令执行、编码链还原、客户端保护绕过 | [0xGame/](./0xGame/README.md) |
| **PolarCTF** | 2 | 2 ✅ | PCRE 回溯上限绕过 `preg_match`、三段式信息收集、Cookie 越权 | [PolarCTF/](./PolarCTF/README.md) |
| **NSSCTF** | 1 | 1 ✅ | `create_function` 代码注入（= `eval`） | [NSSCTF/](./NSSCTF/README.md) |
| **靶场**（非赛事） | 4 个平台 | — | un9 那篇是最完整的（含附录 A1~A6） | [靶场/](./靶场/README.md) |

---

## 📋 全部题目

| 赛事 | 题目 | 日期 | 考点 | flag | 状态 |
|---|---|---|---|---|---|
| 极客大挑战 2025 | [popself](./极客大挑战SYC/2025-popself.md) | 10-04 | 6 跳 POP 链 + 双 md5 魔术哈希 + `?24[SYC.zip=` 参数名绕过 | `SYC{Round_And_r0und_LMAO}` | ✅ |
| 极客大挑战 2024 | [ez_http](./极客大挑战SYC/2024-ez_http.md) | 10-04 | 六级链 + JWT HS256 伪造（改 hasFlag + 重签） | `SYC{...}`（每实例随机） | ✅ |
| 极客大挑战 2023 | [unsign](./极客大挑战SYC/2023-unsign.md) | 10-04 | 3 跳 POP 链（`syc`/`lover`/`web`）+ `echo` 断点调试 | 未记录 | 🔄 |
| 0xGame | [字符白名单命令执行](./0xGame/字符白名单命令执行.md) | 10-02 →10-03 | 字符白名单 + glob 通配符「钓」命令与文件名 | `0xGame{72119ccb-…}` | ✅ |
| 0xGame | [奶蛙的博客](./0xGame/奶蛙的博客.md) | 10-02 | gzip → base64 → 分片拼装（+ HTML 实体 + 诱饵链） | `0xGame{n41w4_l4ugh5…}` | ✅ |
| 0xGame | [ATP 在线实验平台](./0xGame/ATP在线实验平台.md) | 10-02 | 客户端保护绕过（前端 JS 就是接口文档） | `0xGame{26970c47-…}` | ✅ |
| PolarCTF | [swp](./PolarCTF/swp.md) | 10-03 | Vim 交换文件泄露 + `preg_match` 三态 + PCRE 回溯上限绕过 | `flag{4560b3bfea…}` | ✅ |
| PolarCTF | [seek flag](./PolarCTF/seek-flag.md) | 10-03 | 三段式信息收集 + Cookie 越权 | `flag{7ac5b3ca87…}` | ✅ |
| NSSCTF | [Rc3_function](./NSSCTF/Rc3_function.md) | 10-02 | `create_function` 代码注入 | 未记录 | ✅ |
| unserialize-lab | [un9](./靶场/unserialize-lab-un9.md) | 09-30 →10-01 | `SoapClient::__call` SSRF + CRLF 抢 `Content-Type` | — | ✅ |

## 📌 两条记录约定

1. **flag 不强制记录。** 本仓库以「**过程**」为主 —— 考点、payload、踩坑比 flag 重要。
   表里写 `未记录` 的地方是**有意留白**，不是待办，别去补。
2. **题目细节只在这里。** 日志（`logs/`）只留「当天做了什么 + 链接」，不要重复搬一遍。

---

> 跨零点的题目（如 0xGame 字符白名单命令执行 22:59 → 次日 01:47）**归到开始那天** —— 规则见 [根 README](../README.md#-日志日期归属规则跨零点必看)。

---

## ⏳ 还没整理成 WP 的

| 赛事 / 来源 | 现状 | 素材在哪 |
|---|---|---|
| **WelCTF** | 只有知识点，没整理成题解 —— XXE 那套打法已进 [notes/09](../notes/09-XXE.md) | 待找 |
| **0xGame · picture / signin** | 10-03 上午做的，**没有任何分析内容** | 桌面 `0xgame临时文件\` |
| **PKWCTF** | 桌面上有 `PKWCTF` / `PKWCTFprobe方法链` / `PKWCTF隐藏留言` 三个文件夹，WP 未整理 | 桌面 |
| **moectf2026** | 桌面有 `moectf2026临时文件`，WP 未整理 | 桌面 |
| **unserialize-lab un10 / un11** | un10 未通关，un11 搁置 | 桌面 `un10.py` |

---

## ⭐ 为什么按赛事分

**一道题只存在于一个地方。**

以前题目分析散在 `logs/` 里，同一道题会被不同天的会话从不同角度重复记录 ——
比如极客大挑战 2024 的六级链，一度同时存在于日志、知识点笔记和 WP 三处。

改成赛事目录后：

| 层 | 职责 | 组织方式 |
|---|---|---|
| `logs/` | **当天干了什么**（流水 + 结论一句话） | 按**日期** |
| `notes/` | **这个知识点是什么**（跨题复用） | 按**知识点** |
| `writeups/` | **这道题怎么做出来的**（完整分析） | 按**赛事** |

三层各管一件事，题目细节只有一份 —— 从结构上消灭重复。

> **判断标准**：知识点提炼进 `notes/` 就够；只有**过程本身值得复述**的题才单独写 WP。
> 所以 upload-labs 21 关不写 WP（绕过手法高度重复，已进 `notes/05`），而 un9 写（协议层原理值得展开）。
