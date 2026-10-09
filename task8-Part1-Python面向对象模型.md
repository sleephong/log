# task8 Part 1 讲义：Python 面向对象模型

> 严格对应 task8 清单第 1 部分：1 条引子 + 11 个条目，逐条作答；清单之外的内容不写在这里。
> 计划 2 天 ｜ 环境：本机 Python 3.14.2
> 配套实跑：`01_oop_chain.py`（逐环输出）、`02_exec_funcs.py`（执行函数清单实跑）

## 引子：SSTI 漏洞利用链的影响可以达到命令执行

模板注入的终点是**在服务器上执行命令**，而那条利用链整条都建立在 Python 的对象模型上：
从模板里能摸到的一个对象出发，顺着"类 → 父类 → 子类 → 方法 → 全局命名空间 → builtins"
一层层爬回解释器环境。所以下面 10 个问题，就是那条链的零件清单。

## 条目 1：知晓 python 中如何进行命令执行

| 函数 | 回显 | 返回值 | 备注 |
|---|---|---|---|
| `os.system(cmd)` | 无 | 退出码（int） | 输出直接打到进程 stdout，注入场景里看不到结果 |
| `os.popen(cmd).read()` | 有 | 命令输出字符串 | 主流用法 |
| `subprocess.check_output(cmd, shell=True)` | 有 | bytes/str | 常用 |
| `subprocess.run(cmd, shell=True, capture_output=True)` | 有 | CompletedProcess | 常用 |
| `os.execv` / `os.execve` | 无返回 | 替换当前进程 | 不用 |
| `pty.spawn('/bin/sh')` | 交互 | 无 | Linux 反弹 shell |
| `commands.getoutput(cmd)` | 有 | 字符串 | Python 2 专属，Py3 已删除 |

本机实测（`python 02_exec_funcs.py`）：

```
os.system('whoami') 返回值 = 0          ← 只有退出码，没有内容
os.popen('whoami').read() = 'laptop-59ul2kdl\暗炎魔主\n'
subprocess.check_output('whoami', shell=True, text=True) = 'laptop-59ul2kdl\暗炎魔主\n'
```

判断"哪种能用"的唯一标准是**回显**：拿不到 stdout 就等于没打进去。

## 条目 2：学习如何进行代码执行

| 入口 | 能跑什么 | 限制 |
|---|---|---|
| `eval(expr)` | 单个**表达式** | 不能有语句 |
| `exec(code)` | 任意语句 / 整段代码 | **不返回值**，结果要自己塞进变量再取 |
| `compile(src, file, mode)` | 先编译成 code 对象 | 要配合 eval/exec 才运行 |

本机实测：

```
eval('1+1')                       = 2
eval('__import__("os").getcwd()') = D:\deepseek\task8
eval('import os')                 -> SyntaxError: invalid syntax     ← import 是语句

ns = {}
exec("import os\nresult = os.getcwd()", ns)
ns['result']                      = D:\deepseek\task8                ← exec 的结果只能这样取
```

一句话：**eval 求值，exec 执行，compile 只编译。**

## 条目 3：整理可用于代码执行的不同函数

| 函数/入口 | 作用 |
|---|---|
| `eval` / `exec` / `compile` | 让字符串变成代码跑起来 |
| `__import__('os')` | 按名字导入模块（最常被当跳板） |
| `importlib.import_module('os')` | 同上，官方写法 |
| `getattr(obj, 'name')` | 按字符串取属性（过滤点号时用它绕） |
| `globals()` / `locals()` | 拿命名空间字典，从里面捞模块和函数 |
| `open(path).read()` | 读文件（不执行代码，但常是拿 flag 的最后一跳） |
| `timeit.timeit('...')` | 冷门入口，审计会遇到 |
| `pickle.loads()` / `yaml.load()` | 反序列化 RCE（另一条线） |
| `breakpoint()` / `pdb` / `code.InteractiveInterpreter` | 交互调试入口 |
| Python 2 的 `input()` | 等于 `eval(raw_input())`，历史大坑 |

其中 `builtins` 里直接可用的（实测都在 `builtins.__dict__` 里）：
`__import__` `eval` `exec` `compile` `open` `getattr` `globals` `locals` `breakpoint`。

## 条目 4：了解继承、子类、父类的概念

```python
class Animal:                       # 父类（基类）
    def __init__(self, name):
        self.name = name

class Dog(Animal):                  # 括号里写父类 = 继承；Dog 是 Animal 的子类
    def __init__(self, name, age):
        super().__init__(name)      # 调父类构造
        self.age = age
    def bark(self):                 # 实例方法
        return f"{self.name}: 汪"
```

三条必须建立的直觉：

1. **一切皆对象**：类本身也是对象，它的类型是 `type`；`object` 是继承树的根。
2. **实例只存数据，方法挂在类上**（实例字典里只有 `name`/`age`，`bark` 在 `Dog` 上）。
3. **继承链是一张可以上下爬的图**：往上靠 `__base__` / `__mro__`，往下靠 `__subclasses__()`。

## 条目 5：学习如何编写一个类，如何实例化它的子类

```python
class Animal:
    def __init__(self, name):
        self.name = name
    def breathe(self):
        return f"{self.name} 在呼吸"

class Dog(Animal):
    species = "Canis lupus familiaris"      # 类属性
    def __init__(self, name, age):
        super().__init__(name)
        self.age = age
    def bark(self):
        return f"{self.name}: 汪！我 {self.age} 岁"

d = Dog("旺财", 3)          # ← 实例化：调用类 = 造实例，__init__ 自动触发
print(d.bark())             # 旺财: 汪！我 3 岁
```

要点：`class 子类(父类)` 建立继承；子类用 `super()` 复用父类构造；**调用类名即实例化**。

## 条目 6：如何通过一个实例对象获取它的类

```python
d.__class__            # <class '__main__.Dog'>
type(d)                # <class '__main__.Dog'>      两种写法等价
d.__class__.__name__   # 'Dog'

"".__class__           # <class 'str'>     ← payload 里最常用的起点
```

## 条目 7：如何获取一个类的父类

```python
Dog.__base__     # <class '__main__.Animal'>        第一个直接父类
Dog.__bases__    # (<class '__main__.Animal'>,)     元组，多继承时有多个
Dog.__mro__      # (Dog, Animal, object)            方法解析顺序，最后一个一定是 object
```

`''` 的 MRO（payload 里下标的来源）：

```
Python 3:  __mro__[0] = <class 'str'>   __mro__[1] = <class 'object'>
Python 2:  __mro__[0] = <class 'str'>   __mro__[1] = <class 'basestring'>   __mro__[2] = <class 'object'>
```

## 条目 8：如何获取一个类的子类

```python
Animal.__subclasses__()   # 只返回 Animal 的【直接】子类
object.__subclasses__()   # 所有直接继承 object 的类 —— 利用链的弹药库
```

本机实测：

```
object.__subclasses__() 返回类型 = <class 'list'>
当前进程里数量 = 180          （导入 Flask 后变成 584）
[0] <class 'type'>   [1] <class 'async_generator'>   [2] <class 'bytearray_iterator'> ...
```

两条结论：

- 数量和顺序取决于该进程 import 了哪些模块 → **下标必须现场枚举**；
- 只给直接子类，找不到孙子类（要找得对子类再调一次）。

模板里枚举下标的写法：

```jinja
{% for c in ''.__class__.__mro__[1].__subclasses__() %}{{ loop.index0 }}:{{ c.__name__ }} {% endfor %}
```

## 条目 9：如何获取某一个类的某个方法

```python
Dog.__dict__                # 类的命名空间，里面有 species / __init__ / bark
Dog.bark                    # <function Dog.bark>              函数对象
d.bark                      # <bound method Dog.bark of ...>    绑定方法
d.bark.__func__             # <function Dog.bark>               剥回裸函数
getattr(d, 'bark')          # 按字符串取
Dog.__dict__['bark']        # 按名字从类字典取
Dog.__init__                # 每个类都有它，payload 里因此爱用 __init__
```

## 条目 10：方法的全局命名空间是什么意思，有什么用处

**每个函数对象都带一个 `__globals__`，值就是它定义所在模块的全局变量字典。**

```python
Dog.bark.__globals__        # <class 'dict'>   ← 那个模块的全局空间
```

本机实测内容：

```
共 20+ 个 key： ['__name__', '__doc__', '__package__', '__loader__', '__spec__',
                 '__builtins__', '__file__', '__cached__', 'sys', 'builtins',
                 'LINE', 'step', 'Animal', 'Dog', 'd', ...]
'__builtins__' -> <class 'module'>       '__name__' -> __main__
```

用处（也是它在 SSTI 里的价值）：

- 模板的命名空间里**没有** `os`、`sys`、`__import__`；
- 但模板里能摸到的**任何函数或类**都携带着"它所属模块的全局空间"，里面往往就有 `os` 和 `__builtins__`；
- 于是顺着这条路，就能从受限的模板上下文爬回完整的解释器环境。

对比记忆：`__module__` 只给模块**名字**（字符串），`__globals__` 直接给**那个字典**。
Python 2 里这个属性叫 `func_globals`。

## 条目 11：什么是 builtins，有什么作用

`builtins` 是**内建命名空间**，Python 找名字的顺序是 LEGB：
**L**ocal → **E**nclosing → **G**lobal → **B**uilt-in，最后一层就来自每个模块 globals 里的 `__builtins__`。
所以 `print` `len` `open` `__import__` 这些名字不用 import 就能直接用。

```
builtins 模块 = <module 'builtins' (built-in)>
builtins.__dict__ 里共 160 个名字（前几个：__name__ __doc__ __package__ __loader__ __spec__ __build_class__）

__main__ 里：        type(__builtins__) = <class 'module'>
被 import 的模块里：  json.__builtins__ is builtins.__dict__ -> True    （是 dict）
C 实现的内建模块里：  sys.__builtins__  -> AttributeError             （根本没有这个属性）
```

**这个差异直接决定 payload 怎么写**：模块形态用 `.__builtins__.__import__`，字典形态用 `['__builtins__']['__import__']`；
稳妥写法是把它当字典处理（`['__import__']`），或先做 `isinstance(b, dict)` 判断。

它为什么是 RCE 的最后一环：`builtins.__dict__` 里同时装着 `__import__` `eval` `exec` `open` `getattr` `chr` —— 拿到它就等于拿到了整套能力。

## 本部分完成标准

```
能默写：实例 → 类 → 父类 → 子类 → 方法 → __globals__ → __builtins__ 这条链的每一步
能解释：__mro__[1] 为什么是 object；__subclasses__() 的下标为什么不能抄
能说清：__globals__ 是什么、为什么它能绕开模板命名空间的限制
```
