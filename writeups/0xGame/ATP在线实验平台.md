# 0xGame · ATP 在线实验平台 Writeup

| 项 | 内容 |
|---|---|
| 赛事 | 0xGame |
| 题目 | **ATP 在线实验平台** |
| 考点 | **客户端保护绕过**（前端 JS 只防君子）+ **直接调后端接口**（前端 JS 就是接口文档） |
| flag | `0xGame{26970c47-bda0-472c-80da-1e7d2e473ce8}` |
| 状态 | ✅ 已通关（10-02 22:50） |
| 原始记录 | [logs/2026-10-02.md](../../logs/2026-10-02.md) |

> 相关笔记：[10 · 信息收集与代码审计](../../notes/10-信息收集与代码审计.md)（§1.6 前端 JS —— **找接口必看**）

---

## 一句话

> 页面用 `protect.js` 禁了**粘贴 / 右键 / F12**，还挂了 **`debugger` 计时**和**窗口尺寸检测**来"抓 DevTools" —— 但这些**全是客户端的事**，**一行都不影响按钮背后的那个 HTTP 请求**。照着 `submit.js` 里的 `fetch('/submit', {JSON})`，用脚本直接 POST，保护就整层消失了。

---

## 一、三层结构：哪一层是真校验

| 层 | 性质 |
|---|---|
| `protect.js`（禁粘贴/右键/F12 + `debugger` 计时 + 尺寸检测 DevTools） | **纯客户端**，`_0xdevOpen()` 只给横幅加 class，**不拦提交** |
| `submit.js`（`fetch('/submit', {JSON})`） | **前端 JS 就是最好的接口文档** |
| 服务端逐字比对 | **真判定** |

**关键认知**：`_0xdevOpen()` 只给横幅**加了个 class**（视觉上"检测到 DevTools"），**它没有任何一行代码去阻止表单提交** —— 也就是说，这个"保护"连"防君子"都算不上，只是**演给人看的**。

> **推论**（一般化的判断方法，不是日志原文）：判断客户端保护真假，问一句 **「如果把 JS 全禁掉，这个功能还能用吗？」** 能用 → 保护是装饰；不能用 → 才需要认真绕。这题属于**把 JS 全忽略**的那一类。

---

## 二、解法：忽略 `protect.js`，照 `submit.js` 打接口

```
① 正常 GET 题目页            → 页面里 <pre id="ref-code"> 里有参考代码（带 HTML 实体）
② 从 submit.js 抄接口        → POST /submit，body 是 JSON：{"code": "..."}
③ html.unescape 解实体       → 提交前先把 &lt; &gt; &amp; 还原
④ 直接 POST JSON             → 200 + 真正的判题结果/flag
```

**可以直接抄的代码**：

```python
import html, json, re, urllib.request

page = urllib.request.urlopen(TARGET).read().decode()

# ★ 参考代码在 <pre id="ref-code"> 里，拿到的带 HTML 实体，必须先 unescape
code = html.unescape(re.search(r'<pre id="ref-code">(.*?)</pre>', page, re.S).group(1))

req = urllib.request.Request(BASE + "submit",              # BASE 末尾带 "/"
        data=json.dumps({"code": code}).encode(),
        headers={"Content-Type": "application/json"})      # ★ 不是表单编码
# → 0xGame{26970c47-bda0-472c-80da-1e7d2e473ce8}
```

**两个必须照抄的细节**：

| 细节 | 为什么 |
|---|---|
| `Content-Type: application/json` | 服务端**只认 JSON**（见踩坑 3.1） |
| `html.unescape(...)` | `<pre>` 里的代码是**转义过的**，原样提交比对不上 |

**推论**：flag 是**服务端判定通过之后返回**的（真判定在服务端逐字比对那一层）；落在页面上的那两个 `protect.js` / `submit.js` 只是**任务说明和入口**，绕过它们本身不产生 flag。

---

## 三、踩坑点

| 问题 | 原因 | 解决 |
|---|---|---|
| **ATP 表单编码提交** | 服务端只认 JSON | 200 但返回 **5611 字节 HTML**（不是评测结果）；改成 `{"code": ...}` + JSON 头 |

**「200 但返回 5611 字节 HTML」这个信号很典型**：状态码是对的、响应体是页面而不是结果 —— 说明**请求打对了地址，但格式不对，被打回了页面**。判据不是状态码，而是**响应体的形状**。

---

## 四、判据速记

| 现象 | 结论 |
|---|---|
| 200 + 一坨 HTML（如 5611 字节） | **格式不对被打回页面**，不是评测结果 |
| 200 + 结构化结果 | 接口命中 |
| JS 里有 `fetch('/submit', ...)` | **接口文档免费送**：路径、方法、`Content-Type`、字段名全在里面 |
| 禁粘贴/右键/F12、`debugger`、尺寸检测 | 客户端保护 → **只影响手，不影响脚本** |

---

> **一句话收尾**：**客户端校验不是校验**；**前端 JS 是最好的接口文档** —— 拿到题先看 JS 里的请求长什么样，然后**用脚本按它的格式发一遍**，所有"保护"都不存在。
