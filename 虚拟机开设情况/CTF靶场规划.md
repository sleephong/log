# CTF 靶场规划

> 这台 Windows 虚拟机的第二个用途：作为 CTF 练习环境的基座
> 当前状态：**基座已就绪，Kali 和靶机待建**

---

## 一、核心原则：网络隔离

### 为什么必须隔离

靶机是**故意带漏洞**的机器。如果图省事用「桥接模式（Bridged）」，等于把一台满是漏洞的机器**直接插进你家局域网**：

| 后果 | 说明 |
|---|---|
| 同网段任何设备都能扫到并攻击它 | 你的手机、智能家居、电视盒子 |
| 邻居蹭网设备也能打到 | 同一路由器下不分是谁 |
| 靶机可以横向扫描你的真实设备 | 反过来威胁宿主机和家庭网络 |
| 万一靶机带蠕虫类漏洞 | 自动扩散，不受你控制 |

所以本方案从建立之初就**只给 NAT + 内部网络**，**任何情况下都不使用桥接**。

### 网络拓扑

```
                    ┌─────────────── 宿主机 (Win11 家庭版) ────────────────┐
                    │                                                      │
                    │   VirtualBox                                         │
                    │                                                      │
   互联网 ──NAT─────┼──▶ ┌─────────────────┐        ┌─────────────────┐    │
   (只出不进)        │    │  Win11-Daily    │        │  Kali-CTF       │    │
                    │    │  nic1 = NAT     │        │  nic1 = NAT     │    │
                    │    │  nic2 = CTFLab ─┼───┬────┼─ nic2 = CTFLab  │    │
                    │    └─────────────────┘   │    └─────────────────┘    │
                    │                        │                           │
   互联网 ──NAT─────┼──▶ （将来可加更多攻击机）│                           │
                    │                        │                           │
                    │            内部网络 CTFLab（Host-Only 级隔离）        │
                    │        ⚠ 连【宿主机】都访问不到这个网段              │
                    │                        │                           │
                    │                 ┌──────┴──────┐                    │
                    │                 │   靶机们     │                    │
                    │                 │ Metasploitable 2                  │
                    │                 │ VulnHub 系列  │                   │
                    │                 │ DVWA 等      │                    │
                    │                 └─────────────┘                    │
                    └──────────────────────────────────────────────────────┘
```

### 两种网卡的作用

| 网卡类型 | 作用 | 谁能访问谁 |
|---|---|---|
| **NAT** | 让虚拟机**出去上网**（装工具、更新系统、下载靶机） | 虚拟机 → 互联网 ✅<br>互联网 → 虚拟机 ❌ |
| **内部网络 `CTFLab`** | **靶场专用隔离网段** | 挂了这张网卡的虚拟机之间互通 ✅<br>**宿主机也访问不到** ❌<br>外部网络 ❌ |

> **内部网络（Internal Network）比 Host-Only 更严格**：Host-Only 至少宿主机能访问，Internal Network 连宿主机都进不去，是纯封闭的靶场。

---

## 二、网络地址规划

| 网段 | 用途 | 说明 |
|---|---|---|
| `10.0.2.0/24` | NAT 网段 | VirtualBox 固定分配，网关 `10.0.2.2`，DNS `10.0.2.3`，虚拟机固定拿 `10.0.2.15` |
| `169.254.0.0/16` | CTFLab 网段（当前） | 内部网络**没有 DHCP**，Windows 拿不到地址会自分配 link-local 地址，属正常现象 |
| `192.168.56.0/24` | （建议）CTFLab 改用静态地址 | 建 Kali 时**手动给固定 IP**，比 link-local 好记也好写脚本 |

**建议的静态地址分配**（建 Kali 和靶机时手动配置）：

| 主机 | IP | 说明 |
|---|---|---|
| Kali-CTF | `192.168.56.10` | 攻击机 |
| Metasploitable 2 | `192.168.56.20` | 入门靶机 |
| VulnHub 靶机 A | `192.168.56.21` | |
| VulnHub 靶机 B | `192.168.56.22` | |
| … | `192.168.56.2x` | 以此类推 |

---

## 三、加入 Kali 攻击机

### 方式一：官方预装镜像（推荐）

Kali 官方提供 VirtualBox 预装镜像，省去安装步骤：

1. 从 https://www.kali.org/get-kali/#kali-virtual-machines 下载 **VirtualBox 64-bit** 镜像（约 4 GB 的 7z 压缩包）
2. 解压出 `.vdi` 文件，放到 `D:\VMs\Kali\`
3. 建虚拟机并**务必按下面配网卡**：

```powershell
$vbm = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

# 创建虚拟机
& $vbm createvm --name 'Kali-CTF' --ostype Debian_64 --register --basefolder 'D:\VMs'
& $vbm modifyvm 'Kali-CTF' `
    --memory 4096 --cpus 4 --vram 128 `
    --nic1 nat --nictype1 82540EM `
    --nic2 intnet --intnet2 CTFLab `
    --mouse ps2 `
    --clipboard-mode bidirectional --draganddrop bidirectional

# 挂载解压出来的 vdi
& $vbm storagectl 'Kali-CTF' --name 'SATA' --add sata --controller IntelAhci --portcount 2 --bootable on
& $vbm storageattach 'Kali-CTF' --storagectl 'SATA' --port 0 --device 0 --type hdd `
    --medium 'D:\VMs\Kali\kali-linux-2025.x-virtualbox-amd64.vdi'

# 启动
& $vbm startvm 'Kali-CTF' --type gui
```

> `--mouse ps2` 建议保持一致。Linux 客户机不受那个 USB 平板 bug 影响（见 [踩坑与修复.md](./踩坑与修复.md) 坑 7），但统一配置更省心。

Kali 默认账户：`kali` / `kali`

### 方式二：ISO 全新安装

从 https://www.kali.org/get-kali/#kali-installer-images 下载 ISO，按常规流程安装。适合需要自定义分区或做持久化配置的场景。

---

## 四、加入靶机

| 靶机 | 来源 | 建议内存 | 说明 |
|---|---|---|---|
| **Metasploitable 2** | VulnHub / SourceForge | 512 MB | 经典入门靶机，漏洞极多，适合第一次练手 |
| **DVWA** | 可跑在 Kali 的 Docker 里 | — | Web 漏洞练习（SQL 注入 / XSS / 文件包含等） |
| **VulnHub 系列** | https://www.vulnhub.com/ | 1 GB | 各类 CTF 风格靶机，从入门到困难都有 |
| **OWASP Juice Shop** | Docker | — | 现代 Web 漏洞练习平台 |

**靶机建机的关键配置**：

```powershell
& $vbm modifyvm '靶机名' `
    --memory 1024 --cpus 1 `
    --nic1 intnet --intnet2 CTFLab      # ← 只给内部网络
    # 不要加 --nic2 nat，更不要用 bridged
```

> ⚠️ **靶机不要给 NAT。** 攻击机（Kali）有 NAT 是为了上网装工具；靶机不需要上网，多一张通往外部的网卡只会扩大风险面。

---

## 五、每次开打的标准流程

```powershell
$vbm = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

# ═══ 1) 准备阶段：先关机，再给每台打快照 ═══
# ⚠ 绝对不要在运行状态下打快照（见踩坑文档坑 8）

& $vbm controlvm 'Kali-CTF' acpipowerbutton
& $vbm controlvm '靶机名'   acpipowerbutton
# 等所有 VM 状态变成 poweroff

& $vbm snapshot 'Kali-CTF' take '开打前'
& $vbm snapshot '靶机名'   take '开打前'

# ═══ 2) 开打 ═══
& $vbm startvm '靶机名'   --type gui     # 先开靶机
& $vbm startvm 'Kali-CTF' --type gui     # 再开攻击机

# ═══ 3) 收尾：回滚，把痕迹和残留全部清掉 ═══
& $vbm controlvm '靶机名'   acpipowerbutton
& $vbm controlvm 'Kali-CTF' acpipowerbutton

& $vbm snapshot '靶机名'   restore '开打前'
& $vbm snapshot 'Kali-CTF' restore '开打前'
```

### 为什么要回滚

| 不回滚的问题 | 回滚的好处 |
|---|---|
| 靶机上留下攻击痕迹，影响下次练习的干净度 | 每次都从完全相同的初始状态开始 |
| 万一练到一半被反打（靶机也可以攻击你） | 恶意软件、后门全部消失 |
| 磁盘里堆积大量临时文件 | 磁盘不膨胀（差分磁盘可回收） |
| 想复现某个步骤时环境已经变了 | 随时回到已知状态，结果可复现 |

---

## 六、⚠️ 第一次开打前必须做的隔离自检

**在 Kali 里执行**：

```bash
# 1) 看路由表：应该只有 10.0.2.x（NAT）和 192.168.56.x（CTFLab）
ip route

# 2) 尝试 ping 你家路由器 —— 应该【不通】
ping -c 2 192.168.1.1        # 换成你实际的网关地址

# 3) 尝试 ping 宿主机 Wi-Fi 网段里的设备 —— 应该【不通】
ping -c 2 192.168.1.100

# 4) 确认能 ping 通靶机（说明靶场内部通着）
ping -c 2 192.168.56.20
```

**判据**：

| 目标 | 期望结果 | 说明 |
|---|---|---|
| 靶机 `192.168.56.20` | ✅ 通 | 靶场内部正常 |
| 互联网（如 `ping 8.8.8.8`） | ✅ 通（走 NAT） | 能装工具 |
| **网关 `192.168.1.1`** | ❌ **必须不通** | **隔离生效的标志** |
| **宿主机网段其他设备** | ❌ **必须不通** | |

> ⚠️ **如果 ping 通了家里网段的设备，立刻停机检查网卡配置** —— 说明有网卡被误配成了桥接。

**额外注意**：宿主机上还挂着一个 `Radmin VPN` 虚拟网卡和 Wi-Fi 网段。靶机不配桥接就碰不到它们，但如果哪天要给虚拟机加第三张网卡，一定要先确认加的是什么类型。

---

## 七、版本化：把靶场配置纳入仓库

建议给靶场建一份配置记录，纳入本仓库，内容包括：

| 记录项 | 为什么重要 |
|---|---|
| 每台虚拟机的名称、用途、内存/CPU 分配 | 重建时不用回忆 |
| 每台机器的 `nic1` / `nic2` 配置 | ⚠️ **最关键**，防止误配桥接 |
| 静态 IP 分配表 | 写脚本/记忆都靠它 |
| 快照命名规范 | 回滚时不会搞混 |
| 靶机来源 URL 和校验值 | 确保拿到的是原始镜像，不是被投毒的版本 |

> 靶机镜像一定要**从官方渠道下载并校验哈希**。网上流传的「汉化版」「优化版」靶机镜像有被植入后门的风险——你本来就是在练攻防，用来源不明的镜像等于主动开门。

---

## 八、其它注意事项

### 不要给 CTF 用的虚拟机开共享文件夹

VirtualBox 的共享文件夹是**沙箱逃逸和勒索软件爬回宿主机**的经典通道。

| 传文件需求 | 推荐方式 |
|---|---|
| 小文件、代码片段 | 剪贴板（已开双向） |
| 中等文件 | 拖放（已开双向） |
| 大文件 | 用 NAT + 临时开个 HTTP 服务 |
| ❌ 不要用 | 共享文件夹 |

### 内存不够时的取舍

宿主机只有 16 GB，全开的时候要算账：

| 场景 | 分配方案 | 宿主机剩余 |
|---|---|---|
| 只开 Win11 | Win11 = 6 GB | ~9 GB |
| Win11 + Kali | Win11 = 4 GB，Kali = 4 GB | ~7 GB |
| Kali + 2 台靶机 | Kali = 4 GB，靶机各 1 GB | ~9 GB |

**建议：打 CTF 的时候把 Win11 关掉**，只开 Kali + 靶机，内存更宽裕。

### 法律边界

| 能做 | 不能做 |
|---|---|
| 打自己搭建的靶机 | 扫描/攻击未授权的目标 |
| 打 CTF 平台提供的题目环境 | 拿学到的技术去打真实网站 |
| 在自己的隔离网络里做实验 | 把靶机暴露到公网 |

**扫描未授权的目标在中国属于违法行为**，涉及：

- 《网络安全法》第 27 条（不得从事非法侵入、干扰、窃取等危害网络安全的活动）
- 《刑法》第 285 条（非法侵入计算机信息系统罪、非法获取计算机信息系统数据罪）
- 《刑法》第 286 条（破坏计算机信息系统罪）

CTF 平台和自建靶机是合法练习的唯一途径，**这条线不要越**。

---

## 相关文档

- [虚拟机开设情况总览](./README.md)
- [搭建全过程](./搭建全过程.md)
- [踩坑与修复](./踩坑与修复.md) —— 尤其是坑 7（关机死锁）和坑 8（快照撞车）
