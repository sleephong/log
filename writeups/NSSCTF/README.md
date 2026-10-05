# NSSCTF

> **NSSCTF** —— 国内公开 CTF 练习平台（动态靶机，每次开题给一个临时域名 + 端口）。
> 本目录只放**从 NSSCTF 上打的题**，按题一篇。

---

## 题目清单

| # | 题目 | 时间 | 考点 | flag | 状态 | WP |
|---|---|---|---|---|---|---|
| 1 | `Rc3_function` | 10-02 | **PHP `create_function` 代码注入** | 待补 | ✅ 已通关 | [Rc3_function.md](./Rc3_function.md) |

> **flag 待补**：这两道题当时只记了 payload，没把 flag 抄下来。下次重打时补上。

---

## 考点分布

| 考点 | 出现题目 | 对应笔记 |
|---|---|---|
| **代码执行类函数**（`create_function` = `eval`） | Rc3_function | [10 · 信息收集与代码审计 §2.1](../../notes/10-信息收集与代码审计.md) |
| 「用户输入拼进代码模板再 eval」的通用套路 | Rc3_function | 见本篇 §五 |

---

## 复盘

**这题教会的一件事**：

> **看危险函数，不能只看"它叫什么"，要看"它内部拼出了什么字符串"。**

`create_function` 名字上像「定义一个函数」，但实现是 `eval` 一个模板 ——
一旦想清楚**模板长什么样**，payload 就是**在哪里闭合**的纯语法问题。

**留下的习惯**：
1. 遇到代码执行类 sink，先**手工把拼接结果写出来**
2. 改 payload 时，**先确认整段能编译通过**，再谈执行 —— 否则"没反应"会被误判成"没执行"
3. 用 `//` 吃掉模板残留的 `) { }`

---

## 相关

- 同一天的另外三题（0xGame）→ [../0xGame/README.md](../0xGame/README.md)
- 同一天的 un9 / un10 / un3（unserialize-lab）→ [../靶场/unserialize-lab-un9.md](../靶场/unserialize-lab-un9.md)
