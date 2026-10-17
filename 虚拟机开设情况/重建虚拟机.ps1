# 重建虚拟机 · 一键复现脚本
#
# 用途：按《搭建全过程.md》记录的最终配置，从零重建 Win11-Daily 虚拟机。
#       所有踩过的坑都已经固化在参数里（PS/2 鼠标、Secure Boot 顺序、专业版镜像索引）。
#
# 用法：
#   1) 先准备好 Windows 11 ISO，路径填到下面的 $IsoPath
#   2) powershell -ExecutionPolicy Bypass -File 重建虚拟机.ps1
#   3) 脚本会创建虚拟机并启动无人值守安装（约 25 分钟）
#
# 注意：新建虚拟机和挂载光驱不需要管理员权限；
#       但安装 VirtualBox 本身、以及创建 Host-Only 网卡需要 UAC。

[CmdletBinding()]
param(
    [string]$VmName  = 'Win11-Daily',
    [string]$BaseDir = 'D:\VMs',
    [string]$IsoPath = 'D:\VMs\ISO\Win11_zh-cn_x64.iso',
    [string]$UserName = 'dsh',
    [string]$FullName = 'DSH',
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$vbm = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

function Step([string]$m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }

# ---------- 0) 前置检查 ----------
Step '前置检查'
if (-not (Test-Path $vbm)) { throw "找不到 VBoxManage：$vbm（VirtualBox 未安装？）" }
Ok ("VirtualBox " + (& $vbm --version))

if (-not (Test-Path $IsoPath)) { throw "找不到 ISO：$IsoPath" }
$isoBytes = (Get-Item $IsoPath).Length
Ok ("ISO {0:N2} GB" -f ($isoBytes / 1GB))
if ($isoBytes -lt 3GB) { Warn 'ISO 小于 3GB，可能不完整' }

$existing = (& $vbm list vms) -join "`n"
if ($existing -match [regex]::Escape('"' + $VmName + '"')) {
    throw "虚拟机 '$VmName' 已存在。先删除：VBoxManage unregistervm '$VmName' --delete"
}
Ok "名称 $VmName 可用"

# 密码：不写死在脚本里，运行时输入
$sec = Read-Host '设置虚拟机账户密码' -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
if ([string]::IsNullOrWhiteSpace($plain)) { throw '密码不能为空' }

# ---------- 1) 创建虚拟机 ----------
Step '创建虚拟机'
& $vbm createvm --name $VmName --ostype Windows11_64 --register --basefolder $BaseDir | Out-Null
Ok "已创建并注册到 $BaseDir\$VmName"

# ---------- 2) 硬件参数 ----------
Step '配置硬件（EFI + 虚拟 TPM2.0 + 6核6GB）'
# ⚠ --mouse ps2 是必须的：USB 平板鼠标会导致关机时 VUsbPeriodFrm 线程死锁
& $vbm modifyvm $VmName `
    --memory 6144 --cpus 6 --vram 256 `
    --chipset ich9 --ioapic on --hpet on `
    --firmware efi --rtc-use-utc off `
    --tpm-type 2.0 `
    --mouse ps2 `
    --graphicscontroller vboxsvga --accelerate-3d on `
    --audio-driver default --audio-controller hda `
    --nic1 nat --nictype1 82540EM --cable-connected1 on `
    --nic2 intnet --intnet2 CTFLab `
    --clipboard-mode bidirectional --draganddrop bidirectional `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none
Ok '内存 6144MB / 6 核 / EFI / TPM2.0 / PS2鼠标 / NAT + 内部网络 CTFLab'

# ---------- 3) Secure Boot（顺序不能错）----------
Step '启用 Secure Boot'
# ⚠ 必须在虚拟机【首次启动之前】完成，否则 EFI 会改写变量库格式导致 VERR_VFS_UNSUPPORTED_FORMAT
& $vbm modifynvram $VmName inituefivarstore   | Out-Null
& $vbm modifynvram $VmName enrollmssignatures | Out-Null
& $vbm modifynvram $VmName enrollorclpk       | Out-Null
& $vbm modifynvram $VmName secureboot --enable | Out-Null
$nv = (& $vbm showvminfo $VmName) -join "`n"
if ($nv -match 'UEFI Secure Boot:\s+enabled') { Ok 'Secure Boot 已启用（PK/KEK 已登记）' }
else { Warn 'Secure Boot 状态未确认，请检查 .vbox 里的 TrustedPlatformModule 节点' }

# ---------- 4) 磁盘与光驱 ----------
Step '创建 80GB 动态磁盘并挂载光驱'
$vdi = Join-Path $BaseDir "$VmName\$VmName.vdi"
& $vbm createmedium disk --filename $vdi --size 81920 --format VDI --variant Standard | Out-Null
& $vbm storagectl $VmName --name 'SATA' --add sata --controller IntelAhci --portcount 4 --bootable on | Out-Null
& $vbm storageattach $VmName --storagectl 'SATA' --port 0 --device 0 --type hdd --medium $vdi | Out-Null
& $vbm storageattach $VmName --storagectl 'SATA' --port 1 --device 0 --type dvddrive --medium $IsoPath | Out-Null
Ok "磁盘 $vdi（80GB 动态分配）"

# ---------- 5) 无人值守安装 ----------
if ($SkipInstall) {
    Step '已跳过安装（-SkipInstall）'
    Write-Host "  启动：& '$vbm' startvm $VmName --type gui"
    exit 0
}

Step '启动无人值守安装（约 25 分钟，会自动重启几次）'
# ⚠ --image-index=4 才是【专业版】。不指定的话 VBox 默认选 index 1 = 家庭版，
#    会丢掉远程桌面服务端、组策略编辑器、BitLocker、域加入 —— CTF 域渗透靶场要用。
& $vbm unattended install $VmName `
    --iso=$IsoPath `
    --user=$UserName `
    --user-password=$plain `
    --full-user-name=$FullName `
    --locale=zh_CN --country=CN --time-zone=Asia/Shanghai `
    --image-index=4 `
    --install-additions `
    --additions-iso='C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso' `
    --start-vm=gui

Ok '安装已启动，在 VirtualBox 窗口里可以看到进度'

# ---------- 6) 装完后的必做项 ----------
Write-Host "`n================ 装完之后必须做的两件事 ================" -ForegroundColor Yellow
Write-Host @"
1) 关闭快速启动和休眠（在虚拟机里用【管理员】命令行执行，然后重启一次）：
     powercfg /h off
   注册表 HiberbootEnabled 也要置 0（有些版本 powercfg 不会改它）。

2) 确认 Guest Additions 真的装上了（--install-additions 会静默失败）：
     在虚拟机里执行  sc query VBoxService
     看到 DISPLAY_NAME = VirtualBox Guest Additions Service 才算成功。
     如果没装上，手动挂载 GA ISO 再装：
       & '$vbm' storageattach $VmName --storagectl 'SATA' --port 1 --device 0 ``
           --type dvddrive --medium 'C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso'
     然后在虚拟机里运行 D:\VBoxWindowsAdditions.exe /S
     ⚠ UAC 弹窗的默认焦点在「否」上，要先按 ← 再按空格。

3) 开机确认无误后，【关机】再打基线快照（绝不要在运行中打快照）：
     & '$vbm' snapshot $VmName take '干净基线'
"@ -ForegroundColor Gray
