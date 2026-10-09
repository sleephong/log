# DSH 折腾记录

> 这里放 **DSH（DeepSeek Harness / DSH Desktop）** 相关的排障、配置、插件折腾记录。
> **不属于 CTF 学习内容**，所以从 `logs/` 里单独拆出来，不放每日学习日志。

## 收录范围

| 放进这里 | 不放这里 |
|---|---|
| DSH 本体更新后出的故障、定位过程、修法 | CTF 题目、payload、WP |
| 插件启用/停用、版本兼容、peerDependencies 问题 | 每日学习流水 |
| 环境配置、备份/还原、脚本工具 | 赛事进度 |

## 命名与归属

- 一天一篇，文件名以日期开头：`YYYY-MM-DD-简要主题.md`
- 日期归属同样按**「哪天开始动手」**，跨零点不拆篇（和 `logs/` 的规则一致）
- 跨零点的那篇，开头用一句 `>` 注明起止时间与归属

## 目录

| 日期 | 主题 | 标签 |
|---|---|---|
| [2026-10-09](./2026-10-09-DSH更新后侧边栏会话列表消失.md) | DSH 更新到 0.11.1 后侧边栏会话列表整块消失<br>定位到插件占死 `sidebar.workspaces` 插槽 → 更新插件修好；每日提醒改用 Windows 计划任务 | `排障方法` `Cordis插槽` `peerDependencies` `计划任务` |

## 相关工具落在哪

这些不在仓库里（体积大、机器相关），放在本机：

| 位置 | 内容 |
|---|---|
| `D:\deepseek\dsh-session-recovery\` | 会话找回工具包：会话切换、导出 Markdown、会话备份、主机 RPC 探测、插件清单核对，附 README |
| `%USERPROFILE%\Documents\dsh-tools\notify.ps1` | 桌面提醒脚本（Toast + 置顶弹窗两条腿） |
| `%USERPROFILE%\Documents\dsh-tools\daily-note-reminder.ps1` | 每日笔记提醒：扫今天动过的文件 → 生成消息 → 调 notify.ps1 |
| `%USERPROFILE%\Documents\dsh-tools\install-daily-reminder-task.ps1` | 上面那个提醒的计划任务安装器（`-RunNow` / `-Test` / `-At HH:mm` / `-Uninstall`） |

## 本机关键路径速查

```
DSH 主目录        %APPDATA%\dsh-desktop\harness
会话日志          %APPDATA%\dsh-desktop\harness\sessions\--D-deepseek--\<id>\session.v4.jsonl.zstd
会话投影缓存      %APPDATA%\dsh-desktop\harness\storages\session_projcache\sessions\<id>.json
界面状态          %APPDATA%\dsh-desktop\harness\profiles\web\desktop-storage.json
插件开关          %APPDATA%\dsh-desktop\harness\profiles\web\cordis.patch.yml
运行日志          %APPDATA%\dsh-desktop\logs\harness.log
```
