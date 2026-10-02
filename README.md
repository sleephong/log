# CTF 学习日志

> 记录 Web 安全学习历程

---

## 📁 目录说明

| 目录 | 内容 |
|---|---|
| **`logs/`** | **每日日志** —— 从 2026-09-28 开始，一天一篇，记录每天学的东西 |
| **`notes/`** | **日志之前的一次总笔记** —— 把此前学过的 task1~7 和实战题，一次性汇总整理的知识点 |
| **`writeups/`** | 靶场 WP（已开始填充） |

**⭐ 区分**：
- `notes/` = **旧知识的"存量总结"**（一次性的、系统的）
- `logs/` = **新知识的"每日增量"**（持续的、流水式的）

---

## 📅 每日日志

| 日期 | 主题 | 标签 |
|---|---|---|
| [2026-09-28](./logs/2026-09-28.md) | un8 POP链 + SoapClient SSRF | `反序列化` `SSRF` |
| [2026-09-30](./logs/2026-09-30.md) | un9 通关：内置类 SSRF + CRLF 抢 Content-Type | `反序列化` `SoapClient` `CRLF注入` |
| [2026-10-01](./logs/2026-10-01.md) | un9 自己复现 + 序列化格式 / PHP 版本差异 / 编码坑 | `反序列化` `序列化格式` `PHP版本` |
| [2026-10-02](./logs/2026-10-02.md) | 反序列化深挖（逃逸 / 引用 / create_function）+ 0xGame 三题（含白名单命令执行） | `反序列化` `引用` `RCE` `通配符` |

---

## 📚 总笔记（此前学习汇总）

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
| 11 | [速查卡](./notes/11-速查卡.md) | 综合 |

---

## 🎯 靶场进度

| 靶场 | 进度 |
|---|---|
| unserialize-lab | un1~un9 ✅ |
| upload-labs | Pass-01~21 ✅ |
| lfi-labs | LFI-1~14 + CMD-1~6 ✅ |
| sqli-labs | Less-1~21 ✅ |

### WP 文档

| 题目 | 考点 | 文件 |
|---|---|---|
| unserialize-lab · un9 | **SoapClient SSRF + CRLF 注入** | [unserialize-lab-un9.md](./writeups/unserialize-lab-un9.md) |

---

## 📊 学习路线

| 模块 | 状态 |
|---|---|
| HTTP 基础 | ✅ |
| Python requests | ✅ |
| PHP 弱类型 | ✅ |
| SQL 注入 | ✅ |
| 文件上传 | ✅ |
| 文件包含 LFI | ✅ |
| 命令注入 | ✅ |
| PHP 反序列化 | ✅ |
| 信息收集 / 代码审计 | ✅ |
| SSRF | ✅ |
| XXE | 🔄 |

---

## 链接

- GitHub: [@sleephong](https://github.com/sleephong)
