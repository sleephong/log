# 极客大挑战（SYC） · 画一个完美的圆

> 环境：`Perfect Waf` 同批下发的 ctfplus 动态实例（Apache/2.4.54 Debian）
> 日期：2026-10-06
> flag：`SYC{5UcH_@_Wo0d3rfUl_CiRc1e}`

## 一、题目长什么样

首页只有一句话和一个入口：

```html
<h1>Welcome to This Challenge</h1>
<p>画出一个完美的圆我就给你flag</p>
<a href="./circle.html">开始挑战</a>
```

`circle.html` 是 295 KB —— 一个仿 Google「画个完美的圆」的 SVG 小游戏：按下鼠标画圆，实时算圆度百分比，画满 360 度就结算。

提示说「**找到 js 文件获得 base64 编码的字符**」。

## 二、卡点：js 文件找不到

按提示去 `js/` 目录翻，全部扑空：

| 路径 | 结果 |
|---|---|
| `js/mzy.js` | 200，5.3 KB，无 flag |
| `js/common.js` | 200，63 KB，无 flag |
| `js/common-audio.js` | 200，48 KB，有 `atob`/`base64` 但**是 Howl 音频库的 WAV data-URI**（`UklGRigA…` = `RIFF`） |
| `js/mzypop.css` | 404 |
| `js/21367589.js` | 404 |

**提示里的「js 文件」不是外部 `.js`，而是 `circle.html` 自己的内联 `<script>`。**

## 三、正解：搜 `atob`

在 `circle.html` 里 `Ctrl+F` 搜 `atob`（或搜 `U1lD`），命中的就是答案：

```javascript
if (score == 100) {
    FfFlLLlllaaaaaggggg = atob("U1lDezVVY0hfQF9XbzBkM3JmVWxfQ2lSYzFlfQ==");
    alert(FfFlLLlllaaaaaggggg);
}
```

解码：

```python
import base64
base64.b64decode("U1lDezVVY0hfQF9XbzBkM3JmVWxfQ2lSYzFlfQ==").decode()
# SYC{5UcH_@_Wo0d3rfUl_CiRc1e}
```

浏览器里直接出弹窗：

```javascript
alert(atob("U1lDezVVY0hfQF9XbzBkM3JmVWxfQ2lSYzFlfQ=="))
```

## 四、触发条件是幌子

```javascript
if (Math.round((1000 * accuracyTotal) / angleTotal) > Math.round((1000 * highScore))) {
    ...
    if (score == 100) { alert(atob(...)) }
}
```

要触发它得**画出 100.0% 圆度的圆**，手动画基本不可能。题目正文「画出一个完美的圆我就给你flag」就是用来把人往「真去画圆」上引的。

**正解不是玩游戏，是读源码。**

## 五、踩坑点

| 问题 | 原因 | 解决 |
|---|---|---|
| 在 `js/` 目录里找不到 flag | 提示说的「js 文件」指**内联脚本** | 搜 `atob` / `base64` / `U1lD` 而不是翻文件 |
| `common-audio.js` 里的 `base64` 是误报 | Howl 音频库内嵌 WAV data-URI | 看内容不看关键词 |
| 295 KB 的 HTML 肉眼读不动 | 文件太大 | 直接 grep，不要顺读 |

## 六、可复用的方法

**base64 前缀速查**（比搜函数名更直接）：

| 明文开头 | base64 开头 |
|---|---|
| `SYC{` | `U1lD` |
| `flag{` | `ZmxhZ` |
| `PKWCTF{` | `UEtXQ1RG` |
| `0xGame{` | `MHhHYW1l` |

**「找不到文件」时的排查顺序**：

```
① 先搜函数名 / 编码前缀（atob、btoa、base64、U1lD、ZmxhZ）
② 再看主 HTML 的内联 <script>
③ 再看 <script src=...> 引用的外部文件
④ 最后看静态资源与图片元数据
```

**判断提示真伪**：题目正文（「画一个完美的圆」）通常是**叙事包装**；真正的技术提示在别处（"找到 js 文件"）。两者冲突时以技术提示为准。

## 七、同类题特征

| 特征 | 说明 |
|---|---|
| 页面是个小游戏 / 交互挑战 | 判定逻辑必然在前端 |
| 提示出现「源码」「js」「编码」 | 找 `atob` / `btoa` / `eval` |
| 触发条件看起来极难达成 | 说明触发条件不是解法，读源码才是 |
| 页面体积大（几百 KB） | 内容必然藏在里面，但要靠搜不靠读 |

## 附：素材位置

```
D:\deepseek\ctf-circle\
├── circle.html           （295 KB，flag 在其内联脚本里）
├── js_mzy.js
├── js_common.js
├── js_common-audio.js    （误报来源）
└── js_21367589.js        （404 的空文件）
```
