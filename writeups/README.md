# 靶场记录

> 做过的靶场与题目汇总。

---

## unserialize-lab（PHP 反序列化）

> 目标：某靶场 / un1~un11

| 关 | 考点 | 状态 |
|---|---|---|
| un1 | 绕过 `__wakeup`（属性数写大） | ✅ |
| un2 | 触发 `__wakeup` + 正则绕过（`O:+5:`） | ✅ |
| un3 | 引用 `R:n` + 强比较 | ✅ |
| un4 | Session 反序列化（handler 不一致） | ✅ |
| un5 | 大写 `S:` 转义 | ✅ |
| un6 | 数组 callable | ✅ |
| un7 | phar 反序列化 | ✅ |
| un8 | **POP 链** | ✅ |
| un9/un92 | **SoapClient SSRF + CRLF** | 🔄 卡在读回显 |

**详细 WP**：见 `unserialize-lab-WP.md` 与 `un8-POP链总结.md`

**un9 的收获**：
- 无自定义类 → 用 PHP 内置类 `SoapClient`
- `__call` 触发 SSRF
- `uri` 属性 CRLF 注入任意头 + POST body
- 用 webhook.site 验证盲 SSRF

---

## upload-labs（文件上传）

> Pass-01 ~ Pass-21，全部通关

**5 大知识点**：
1. **能被当 PHP 解析的后缀**（.php5/.phtml/.pht/大小写）
2. **阻止上传的操作**（前端/MIME/黑名单/白名单/文件头/getimagesize/exif/二次渲染/条件竞争/类封装/pathinfo/数组）
3. **绕过方法**（对应上面）
4. **`.htaccess` vs `.user.ini`**
5. **Windows 特性**（末尾空格/点、`::$DATA`、大小写不敏感）

**核心心法**：**检查的字段 ≠ 存盘的字段**。

**详细 WP**：见 `upload-labs-WP.md`

---

## lfi-labs（文件包含 + 命令注入）

> LFI-1~14 + CMD-1~6

| 类别 | 关卡 | 要点 |
|---|---|---|
| LFI | 1~14 | `php://filter` 读源码、`file://` 读文件、`....//` 绕过滤、`%00` 截断 |
| CMD | 1~6 | 命令注入，`;` 断开前缀；CMD-5 考"检查字段 ≠ 使用字段" |

**详细 WP**：见 `lfi-labs-WP.md`

---

## sqli-labs（SQL 注入）

> Less-1 ~ Less-21

| 关卡 | 类型 |
|---|---|
| 1~4 | 联合注入（`'` / 数字型 / `')` / `")`） |
| 5~6 | 报错注入 / 双引号双注入 |
| 7 | 导出文件写 Webshell |
| 8~10 | 布尔盲注 / 时间盲注 |
| 11~16 | POST 登录框注入 |
| 17 | 密码字段报错注入 |
| 18~19 | **User-Agent / Referer 注入** |
| 20 | **Cookie 注入** |
| 21 | 宽字节注入 |

**详细 WP**：见 `sqli-labs-WP.md`

---

## CTFPlus PKWCTF（实战）

| 题 | 类型 | 收获 |
|---|---|---|
| PKWSEC 员工名录 | SQL 注入 | 调试信息泄露 SQL、关键词嵌套绕过 |
| mio 空间 | 源码泄露 + 爆破 | `www.zip` 是 RAR5、魔数识别、7zr 坑 |
| 4048 Game | 前端 JS | 看 JS 逻辑 |
| 纸上谈兵 | XXE | XML 实体读文件 |
| 喵喵留言板 | API 越权 | 同资源多入口、前端 JS 是 API 地图 |
| 方法链题 | HTTP 协议 | 换方法、凭据放 Cookie/Header |
| 11De-Fusion | Misc | PNG 尾部藏 ZIP |

**详细 WP**：见 `ctfplus-writeups.md`

---

## WelCTF 新生赛（4 题）

| 题 | 考点 | 解法 |
|---|---|---|
| 1 | PHP 绕过 | — |
| 2 | SQL 注入 | 联合注入，库 syclover，表 flags |
| 3 | 文件上传/图片马 | `GIF89a<?= system('ls /'); ?>` + Burp 改后缀 |
| 4 | PHP 伪协议 | `phpphp://://filter/...` 绕 `str_ireplace` |
