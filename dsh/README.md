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
| [2026-10-10](./2026-10-10-DSH无法启动与会话数据抢救.md) | 旧 DSH Desktop 彻底打不开<br>定位到 Chromium 沙箱起不了子进程（`launch-failed exitCode=18` / `0x80000003`）→ 全量抢救 50 个会话 + 62 MB 附件 → 搬进新版 `.dsh` | `沙箱` `launch-failed` `数据抢救` `会话迁移` `workspace.json` |

## 相关工具落在哪

这些不在仓库里（体积大、机器相关），放在本机：

| 位置 | 内容 |
|---|---|
| `D:\deepseek\dsh-session-recovery\` | 会话找回工具包：会话切换、导出 Markdown、会话备份、主机 RPC 探测、插件清单核对，附 README |
| `D:\deepseek\dsh-session-recovery\archive-*\` | 旧应用的**全量冷归档**：180 个文件 / 71.95 MB（含逐个 SHA256 的 `manifest.json`） |
| `D:\deepseek\dsh-session-recovery\manifest-attachments.json` | 附件归档校验：157 个文件 / 62 MB，逐个 SHA256 |
| `D:\deepseek\dsh-session-recovery\markdown\` | 50 个会话的可读 Markdown 全文 + `_索引.md`，记事本可读，不依赖任何 DSH 组件 |
| `D:\deepseek\dsh-session-recovery\rescue-archive.mjs` | 冷归档脚本（复制 + SHA256 + 会话帧完整性审计） |
| `D:\deepseek\dsh-session-recovery\export-all-md.mjs` | 批量导出会话为 Markdown（多帧 zstd 解析，不截断） |
| `D:\deepseek\dsh-session-recovery\migrate-into-new.mjs` | **把旧数据搬进新版 `.dsh`**：幂等，不加 `--apply` 是预演，不覆盖内容不同的已有文件 |
| `D:\deepseek\dsh-session-recovery\抢救报告-2026-10-10.md` | 这次抢救的完整报告（本页那篇日志的详细版） |
| `%USERPROFILE%\Documents\dsh-tools\notify.ps1` | 桌面提醒脚本（Toast + 置顶弹窗两条腿） |
| `%USERPROFILE%\Documents\dsh-tools\daily-note-reminder.ps1` | 每日笔记提醒：扫今天动过的文件 → 生成消息 → 调 notify.ps1 |
| `%USERPROFILE%\Documents\dsh-tools\install-daily-reminder-task.ps1` | 上面那个提醒的计划任务安装器（`-RunNow` / `-Test` / `-At HH:mm` / `-Uninstall`） |

## 本机关键路径速查

2026-10-10 起换用新版 `DeepSeek Harness`，主目录从 `%APPDATA%\dsh-desktop\harness` 变成 `%USERPROFILE%\.dsh`。
旧目录**没有删**，冷归档也在，两条都列出来：

```
【新版 DeepSeek Harness 0.2.0-rc.2】
DSH 主目录        %USERPROFILE%\.dsh
会话日志          %USERPROFILE%\.dsh\sessions\--D-deepseek--\<id>\session.v4.jsonl.zstd
会话投影缓存      %USERPROFILE%\.dsh\storages\session_projcache\sessions\<id>.json
工作区登记        %USERPROFILE%\.dsh\storages\workspace.json
定时任务          %USERPROFILE%\.dsh\storages\dsh_automation.json
附件库            %USERPROFILE%\.dsh\attachments\v1\objects\<hash前2位>\<sha256>
界面状态          %USERPROFILE%\.dsh\profiles\desktop\desktop-storage.json
profile 配置      %USERPROFILE%\.dsh\profiles\desktop\package.json
插件开关          %USERPROFILE%\.dsh\profiles\desktop\cordis.patch.yml
插件真身          %USERPROFILE%\.dsh\profiles\.generations\live\<genId>\node_modules\<pkg>\
Chromium userData %APPDATA%\@deepseek-ai\dsh-desktop      ← 和旧版共用，两个不能同时开

【旧版 DSH Desktop 0.11.1（已打不开，数据已迁出）】
DSH 主目录        %APPDATA%\dsh-desktop\harness
会话日志          %APPDATA%\dsh-desktop\harness\sessions\--D-deepseek--\<id>\session.vN.jsonl.zstd
运行日志          %APPDATA%\dsh-desktop\logs\harness.log
安装目录          D:\deepseek\DSH Desktop
```

**注意**：新版开着的时候旧版永远起不来（共用 `%APPDATA%\@deepseek-ai\dsh-desktop` 的 `lockfile`，
报 `Lock file can not be created! Error code: 5` → `Another instance is already running`）。
真要让旧版跑起来：先完全退出新版，再 `& "D:\deepseek\DSH Desktop\DSH Desktop.exe" --no-sandbox`。
