# task8 Part 2 讲义：HTML 与 Flask 模板基础

> 严格对应 task8 清单第 2 部分：引子里的 3 项要求 + 7 个条目，逐条作答。
> 计划 2 天
> 配套实验：`..\4-靶场实践\lab\ssti_lab.py`（本地 5 关 + 3 个对照页）

## 引子要求 1：服务器最终传递给浏览器的只有渲染完成的 HTML

清单原话是对的，精确版是这样一条链路：

```
① 浏览器发请求：GET /hello?name=clover HTTP/1.1
② 服务器（Flask 路由）执行 Python，取到 name="clover"
③ 模板引擎（Jinja2）在服务端拼接：
      模板文件  <h1>你好，{{ name }}</h1>   +   数据 name="clover"
      ──────────────────────────────────────────────
      渲染结果  <h1>你好，clover</h1>
④ 响应体 = 那串 HTML（Content-Type: text/html; charset=utf-8）
⑤ 浏览器解析 HTML → 建 DOM → 渲染 → 执行页面里的 JS
```

**`{{ }}`、`{% %}`、`{# #}` 只存在于服务端的模板里，模板引擎在服务端就把它们吃掉了，浏览器收到的是纯 HTML。**
所以：浏览器里看不到模板语法是正常的；如果**在浏览器源码里看到了 `{{7*7}}`**，
说明那个位置根本没走模板引擎（不是注入点），或者被转义成了字面量。

## 引子要求 2：借助网页源代码区分"页面展示"和"真实响应"

| 看哪里 | 看到的是什么 | 用途 |
|---|---|---|
| 右键 → 查看网页源代码（Ctrl+U） | 服务器返回的**原始 HTML** | 找注释、隐藏字段、判断模板是否执行 |
| F12 → Elements | **当前 DOM**（JS 改过、浏览器补全过） | 看页面结构、定位元素 |
| F12 → Network → 点请求 → Response | 精确的响应体 | 最准，抓包确认 |
| F12 → Network → Headers | 状态码 / Content-Type / Set-Cookie | 协议层信息 |

判据表（判断模板表达式是否成功执行）：

| 你发的 payload | 响应里出现 | 结论 |
|---|---|---|
| `{{7*7}}` | `49` | 表达式被服务端执行了 → 确认 SSTI |
| `{{7*7}}` | `{{7*7}}` 原样 | 没被当模板解析（普通回显点） |
| `{{7*7}}` | `&#123;&#123;7*7&#125;&#125;` | 经过 HTML 转义输出，同样说明没进模板引擎 |
| `{{7*'7'}}` | `7777777` | 引擎是 Jinja2（字符串重复） |
| `{{7*'7'}}` | `49` | 引擎更像 Twig（PHP，数字乘法） |
| `{{7*7}}` | 报错页出现 `jinja2.exceptions` | 引擎是 Jinja2，且 DEBUG 开着 |

## 引子要求 3：理解 Jinja2 自动转义的影响

Flask 的 `render_template` / `render_template_string` **默认开启自动转义**（裸 `jinja2.Template("...")` 默认不转义）。

```jinja
{{ '<b>hi</b>' }}        开启转义：  &lt;b&gt;hi&lt;/b&gt;    （浏览器显示成字面量）
{{ '<b>hi</b>'|safe }}   关掉转义：  <b>hi</b>               （浏览器真渲染成粗体）
```

两个必须记住的点：

1. **转义只影响"输出呈现"，不影响"表达式求值"。**
   `{{ ''.__class__ }}` 照样执行，只是结果里的 `<` `>` `'` 变成实体：
   你会看到 `&lt;class &#39;str&#39;&gt;` —— 这**不是失败**。
2. 读返回结果要学会脑内反转义：`&#39;`→`'`，`&lt;`→`<`，`&gt;`→`>`，`&#34;`→`"`，`&amp;`→`&`。
   读 flag 时通常不受影响（flag 一般只有字母数字和 `{}`）。

## 条目 1：了解 HTML 页面的基本结构与常见标签

```html
<!DOCTYPE html>                        <!-- 声明：HTML5 文档 -->
<html lang="zh-CN">                    <!-- 根元素 -->
  <head>                               <!-- 给浏览器/搜索引擎看的元信息，不直接显示 -->
    <meta charset="utf-8">             <!-- 编码，乱码问题多半出在这 -->
    <title>页面标题</title>             <!-- 显示在标签页上 -->
    <link rel="stylesheet" href="/static/style.css">
    <style> h1 { color: red; } </style>
    <script> console.log("页面里的 JS"); </script>
  </head>
  <body>                               <!-- 真正显示出来的部分 -->
    <!-- 注释：源码可见，页面不显示，常被出题人用来藏提示 -->
    <h1>一级标题</h1>
    <p>段落文本</p>
    <a href="/flag">超链接</a>
    <img src="/static/cat.png" alt="图片">
    <div id="box" class="card">块级容器</div>
    <span>行内容器</span>
    <ul><li>无序列表项</li></ul>
    <table><tr><th>表头</th></tr><tr><td>单元格</td></tr></table>
    <form action="/search" method="GET">
      <input type="text" name="q" value="clover">
      <input type="hidden" name="debug" value="0">      <!-- 隐藏字段也是参数 -->
      <button type="submit">提交</button>
    </form>
  </body>
</html>
```

常见标签：

| 分类 | 标签 | 作用 |
|---|---|---|
| 结构 | `html` `head` `body` `div` `span` | 容器与分区 |
| 文本 | `h1`~`h6` `p` `br` `hr` `strong` `em` `code` `pre` | 标题、段落、换行、强调、代码 |
| 链接媒体 | `a` `img` `video` `audio` `iframe` | 跳转与嵌入 |
| 列表 | `ul` `ol` `li` `dl` `dt` `dd` | 列表 |
| 表格 | `table` `tr` `th` `td` `thead` `tbody` | 表格 |
| 表单 | `form` `input` `textarea` `select` `option` `button` `label` | 注入点的主要来源 |
| 元信息 | `meta` `title` `link` `style` `script` | 头部资源与脚本 |
| 注释 | `<!-- -->` | 源码可见，浏览器不渲染 |

常用属性：`id` / `class` / `name` / `value` / `type` / `action` / `method` / `href` / `src` /
`placeholder` / `disabled` / `readonly` / `hidden` / `data-*` / `style`。

## 条目 2：理解浏览器、服务器和 HTML 页面之间的关系

见上面「引子要求 1」的五步链路。三句话概括：

- **浏览器**：只认 HTML/CSS/JS，负责解析、渲染、执行脚本；
- **服务器**：跑业务逻辑（Python/Flask），拿数据、选模板、渲染成 HTML 字符串；
- **HTML 页面**：是两者之间唯一的"货物"，服务器发出去的就是它。

## 条目 3：搞清 html 网页的方便之处

1. **纯文本 + 标签**：任何编辑器能写，浏览器容错解析（少个闭合标签也能显示）。
2. **声明式描述结构**：只说"这是一级标题"，不用管字号像素。
3. **超链接把文档连成网**：`<a href>` 是 Web 的骨架。
4. **表单把用户输入标准化成 HTTP 请求**：填表 → GET 拼到 URL query / POST 放进 body。
   安全视角下**表单就是"注入点地图"**：`action` 指路由，`method` 指 GET/POST，`name` 指参数名。
5. **能嵌 CSS/JS**：变成完整应用。
6. **源码即情报**：注释、隐藏字段、`data-*`、JS 里的 API 路径全在源码里。

## 条目 4：知晓最终发送给浏览器的是什么（模板还是？）

**是渲染完成的 HTML 字符串，不是模板。**

```
模板（服务端资产）  --渲染-->  HTML 字符串（发给浏览器）
```

验证方法（本地靶场）：

| 实验 | 操作 | 观察点 |
|---|---|---|
| 1 | 打开 `/hello?name=clover` | Ctrl+U 看源码，`{{ name }}` 已经变成 `clover` |
| 2 | 打开 `/hello?name={{7*7}}` | 页面出现 `49` → 输入被当模板执行了 |
| 3 | 打开 `/esc?name=<b>x</b>` | 源码里是 `&lt;b&gt;x&lt;/b&gt;` → autoescape |
| 4 | 打开 `/safe?name={{7*7}}` | 原样返回 → 模板固定、输入只当变量，打不动 |
| 5 | F12 → Network → Response | 与 Ctrl+U 内容一致，确认这就是服务器发出来的字节 |

对照页说明：`/safe` 是安全写法（模板源固定，用户输入只作为变量值），`/esc` 是转义演示，`/search` 演示表单三要素与 HTML 注释。

## 条目 5：学习 flask 模板语法

三种定界符：

```jinja
{{ ... }}      输出表达式的值（按 autoescape 规则转义）
{% ... %}      语句：if / for / set / include / extends / block / macro / raw ...
{# ... #}      模板注释：只在模板文件里，渲染后彻底消失
```

注释对比（对攻击者的可见性）：

| 写法 | 位置 | 会进浏览器源码吗 |
|---|---|---|
| `<!-- HTML 注释 -->` | HTML | **会**（出题人爱用它藏提示） |
| `{# 模板注释 #}` | 模板 | 不会 |
| `// JS 注释` | 页面脚本 | **会** |

Flask 额外注入的全局名字（不是你传进去的）：

| 名字 | 来源 | 里面有什么 |
|---|---|---|
| `config` | Flask | 全部配置（SECRET_KEY、DB URI…） |
| `request` / `session` / `g` | Flask | 当前请求、会话、请求级全局 |
| `url_for` / `get_flashed_messages` | Flask | 函数 |
| `lipsum` `cycler` `joiner` `namespace` | **Jinja2 自带** | 函数/类 |
| `range` `dict` | Python 内建（模板只放行了这几个） | 函数/类 |

常用过滤器：`upper` `lower` `length` `default('x')` `safe` `attr('...')` `join(',')` `int` `tojson` `trim` `first` `last`。
字符串拼接运算符是 `~`。

## 条目 6：如何获取变量值，如何执行语句

**取变量值**用 `{{ }}`（表达式）：

```jinja
{{ name }}                      变量
{{ user.name }}                 先试属性，失败再试下标
{{ user['name'] }}              下标
{{ items[0] }} {{ items[-1] }}  列表下标（负数也行）
{{ user.get('name', '默认') }}   调方法
{{ name|upper }}                过滤器
{{ name|default('匿名') }}       默认值
```

> 点号 `.` 的规则（SSTI 的命根子）：**先 `getattr`，失败再 `getitem`**。
> 所以 `''.__class__` 等价于 `getattr('', '__class__')`；过滤了点号就可以换成 `['__class__']` 或 `|attr('__class__')`。

**执行语句**用 `{% %}`。模板里没有 `import`、没有 `def`、不能跑任意 Python，能用的块只有这些：

```jinja
{% set x = 1 %}                       赋值（块作用域）
{% if %} {% elif %} {% else %} {% endif %}
{% for %} {% endfor %}
{% include 'other.html' %}
{% extends 'base.html' %}{% block content %}{% endblock %}
{% macro m(a) %} {% endmacro %}
{% filter upper %} {% endfilter %}
{% with a = 1 %} {% endwith %}
{% raw %} {{ 原样输出 }} {% endraw %}
```

## 条目 7：如何在模版里使用选择结构和循环结构

**选择结构：**

```jinja
{% if score >= 90 %}
  优秀
{% elif score >= 60 %}
  及格
{% else %}
  不及格
{% endif %}

{% if name is defined %}定义了{% endif %}
{% if items is not empty %}非空{% endif %}
```

测试运算符：`defined` `undefined` `none` `even` `odd` `string` `number` `iterable` `in` `==` `!=` `>` `<` `and` `or` `not`。

**循环结构：**

```jinja
<ul>
{% for u in users %}
  <li>{{ loop.index }}. {{ u.name }}</li>
{% else %}
  <li>没有数据</li>
{% endfor %}
</ul>
```

`loop` 变量：

| 变量 | 含义 |
|---|---|
| `loop.index` | 从 **1** 开始 |
| `loop.index0` | 从 **0** 开始（对应 Python 下标，枚举 `__subclasses__()` 用它） |
| `loop.first` / `loop.last` | 是否首/末项 |
| `loop.length` | 总长度 |
| `loop.revindex` | 倒序序号 |

## 本部分完成标准

```
能画出：浏览器 → 服务器 → 模板引擎 → HTML 响应 的完整链路
能判断：给一段响应，说出表达式是执行了 / 没进模板 / 被转义了
能默写：{{ }}  {% %}  {# #} 三种定界符 + 选择结构 + 循环结构（含 loop 变量）
能解释：autoescape 影响输出但不影响执行；点号先 getattr 再 getitem
```
