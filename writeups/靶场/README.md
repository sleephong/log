# 靶场（非赛事）

> 这里放**公开练习靶场**的 WP —— 它们不是比赛，是刷题平台。
> 赛事的 WP 放各自的赛事目录（见 [../README.md](../README.md)）。

## 靶场清单

| 靶场 | 内容 | 进度 | 对应笔记 | WP |
|---|---|---|---|---|
| **unserialize-lab** | PHP 反序列化 un1~un11 | un1~un9 <br>un10 未通关<br>un11 搁置 | [07 · PHP 反序列化](../../notes/07-PHP反序列化.md)<br>[08 · SSRF](../../notes/08-SSRF.md) | [un9](./unserialize-lab-un9.md) |
| **upload-labs** | 文件上传 Pass-01~21 | 全通 | [05 · 文件上传](../../notes/05-文件上传.md) | 待补 |
| **lfi-labs** | 文件包含 LFI-1~14 + 命令注入 CMD-1~6 | 全通 | [06 · 文件包含 LFI](../../notes/06-文件包含LFI.md) | 待补 |
| **sqli-labs** | SQL 注入 Less-1~21 | 全通 | [04 · SQL 注入](../../notes/04-SQL注入.md) | 待补 |

## 已归档的 WP

| 题目 | 考点 | 文件 |
|---|---|---|
| **unserialize-lab · un9** | **`SoapClient::__call` SSRF + `_user_agent` 属性做 CRLF 注入抢 `Content-Type`** | [unserialize-lab-un9.md](./unserialize-lab-un9.md) |

> un9 这篇是仓库里**最完整的一篇**（含附录 A1~A6：注入前后差异 / 首值优先 / Content-Type / 头的降级 / 二次编码 / 头大小写）。
> 它把「协议层原理」挖到了底 —— 后来 un10 逃逸、geekchallenge 的 JWT 都从这里的方法论受益。

## 未归档的靶场：为什么

| 靶场 | 原因 |
|---|---|
| upload-labs / lfi-labs / sqli-labs | 是**刷量**用的：21 关的绕过手法高度重复，**知识点已经提炼进 notes/04、05、06**，逐关写 WP 价值低 |
| unserialize-lab un1~un8 | 同理，套路已进 [notes/07](../../notes/07-PHP反序列化.md) |
| **un10 / un11** | **还没通关**，等打完再补 WP |

> **判断标准**：**知识点进了 notes 就够了；只有当一道题"过程本身值得复述"（un9 那种）才单独写 WP。**

## 相关

- [../README.md](../README.md) —— 全部赛事 / 靶场索引
- [../../notes/README.md](../../notes/README.md) —— 专题知识笔记
