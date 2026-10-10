# ws1508-armbian

给 **迅雷赚钱宝二代 / 赚钱宝 Pro（型号 WS1508）** 移植的 Armbian，
基于官方 [armbian/build](https://github.com/armbian/build) 框架 + 主线 6.12 内核，
由 GitHub Actions 全自动编译，**开机自启 SSH**。

- **eMMC 版机器**：可以直刷内置存储，拔掉 U 盘照样开机。
- **NAND 版机器**：直刷引导（U-Boot），系统跑在 U 盘上。
  内置 NAND 装不了系统 —— 实测芯片是 MLC，见下面「NAND 版：内置 NAND 的现状」。
- **已经装好的机器**：用 `apt` 升级，内核和设备树一起更新，**不用重刷**，
  见 [`docs/upgrading.md`](docs/upgrading.md)。

> WS1508 同时存在 **NAND** 和 **eMMC** 两种版本（连同一块 v1.1 主板都有两种），
> 本项目对两种都做了适配：eMMC 版可以完全跑在内置存储上，
> NAND 版用本项目的引导从 U 盘启动。

---

## 硬件

| 项目 | 参数 |
|---|---|
| SoC | Amlogic S805（meson8b），4 核 Cortex-A5 @ 1.5GHz，32 位 ARMv7 |
| 内存 | **512MB** DDR3（单颗 x16 颗粒，16 bit 位宽） |
| 内置存储 | **4GB**，早期批次是裸 NAND，后期批次是 eMMC |
| 网口 | 100Mbps，RMII |
| USB | USB 2.0 × **1**（OTG，同时也是刷机口） |
| 指示灯 | 红 / 绿 / 蓝，分别接 GPIOAO_2 / 3 / 4 |
| 按键 | 1 个，接 GPIOAO_5 |
| 串口 | 主板 4 个焊盘，115200 8N1，3.3V |

⚠️ **别和 WS1608 搞混**：WS1608 是赚钱宝三代 / 玩客云（OneCloud），
它是 **1GB 内存 + 8GB eMMC**，硬件不一样。
网上流传的 `meson8b-ws1508.dts` 是从玩客云的设备树改的，
**内存节点忘了改**，一直写着 1GB —— 本项目已经修正为 512MB。

各代对比：

| 代 | 型号 | SoC | 存储 | 内存 |
|---|---|---|---|---|
| 一代 | WS1408 | S805 | 1Gb NAND | 256MB |
| **二代 / Pro** | **WS1508** | **S805** | **4GB NAND 或 eMMC** | **512MB** |
| 三代 / 玩客云 | WS1608 | S805 | 8GB eMMC | 1GB |

详见 [`docs/hardware.md`](docs/hardware.md)，里面有**怎么分辨自己的机器是 NAND 还是 eMMC**。

---

## 下载与刷机

到 [Releases](../../releases) 下载，然后按你的机器类型选：

| 你的机器 | 下载文件 | 刷入方式 | 结果 |
|---|---|---|---|
| **eMMC 版** | `Armbian-*.burn.img` | Amlogic USB Burning Tool | ✅ 直刷内置存储，完全脱离 U 盘 |
| **NAND 版** | `ws1508-uboot.burn.img` | Amlogic USB Burning Tool | ⚠️ 只刷引导，系统在 U 盘上 |
| **先试试看** | `Armbian-*.img.xz` | 解压后写入 U 盘 / SD 卡 | 不动内置存储 |

> 🔴 **NAND 版第一次刷本项目的引导，必须在烧录工具里勾上「擦除 flash」**
> —— `ws1508-uboot.burn.img` 也一样。本项目改了 NAND 分区表，不勾擦除时
> 烧录工具用 `store init 1` 初始化存储，分区表对不上会直接失败，一个分区
> 都写不进去。代价是一机一份的 `nkey`/`nsec` 永久丢失、本项目无法恢复。
> 详见 [`docs/flashing.md`](docs/flashing.md)。eMMC 版不受这条影响。

完整步骤（含进入刷机模式、救砖）见 [`docs/flashing.md`](docs/flashing.md)。

eMMC 版还有一条**更稳妥的备选路线**：只刷 `ws1508-uboot.burn.img`，
U 盘启动后 SSH 进去跑 `ws1508-install-to-emmc`，由它自己在 eMMC 上写标准
MBR 并把系统装进去。不依赖烧录工具的分区行为，失败了插回 U 盘就复原。

### 已经装好了？用 apt 升级，不用重刷

```bash
curl -fLO https://github.com/dann2333/ws1508-armbian/releases/latest/download/ws1508-apt-setup.sh
sudo bash ws1508-apt-setup.sh      # 只需一次：开启更新通道，并把内核升到最新
sudo reboot
```

之后就是普通的 `apt update && apt full-upgrade`。这一版起刷的新镜像已经自带更新通道。

> ⚠️ **之前发布的所有镜像都建议尽快跑一次上面的脚本**（不想升级就用
> `sudo bash ws1508-apt-setup.sh pin`）。Armbian 官方源里有和本项目内核同名、
> 但不带 WS1508 设备树的包；Armbian 发布 26.11.1 之后，老镜像上一次普通的
> `apt upgrade` 就会装上它，机器随即无法启动。原因和细节见
> [`docs/upgrading.md`](docs/upgrading.md)。

### 首次登录

刷完插网线通电，等约 1 分钟，然后：

```bash
ssh root@<设备IP>        # 也可以试 ssh root@ws1508.local
```

- 用户名：`root`
- 密码：`1234`（可在编译时通过 workflow 参数改，或直接填自己的 SSH 公钥）

**不需要接显示器，也不需要接串口。** 镜像里已经：

- 开机自启 `sshd`，允许 root 登录；
- 去掉了 Armbian 首次登录必须交互设置密码 / 建用户的向导；
- SSH 主机密钥在**首次开机时由 `armbian-firstrun` 重新生成**，
  所以不会所有人的机器长期共用同一份密钥。
  （镜像里保留了构建时的密钥：Armbian 的 `armbian-firstrun.service` 是
  `After=ssh.service`，构建期就删掉密钥的话，首次开机 sshd 会因为
  `sshd -t` 失败而根本起不来。）

> 🔒 刷完请立刻 `passwd` 改密码。默认密码是为了让你能进得去，不是为了长期用。
> 如果这台机器会暴露在公网上，建议编译时直接填 SSH 公钥并把
> `root_password_login` 关掉。

登录后可以运行 `ws1508-info`，它会告诉你这台机器是 NAND 还是 eMMC、
内存多大、根文件系统在哪、以及 **U-Boot 到底探测到了什么存储**
（这一项通过内核命令行 `ws1508.store=` 传进来）。

> **不需要串口。** 刷机、验证、日常使用全程只靠网线和 SSH。
> 蓝灯心跳闪 = 内核活着，红灯常亮 = 通电，机器拿到 IP 就说明一切正常。
> 串口只在"刷完完全不亮也不上网、想知道卡在哪"时才有用，
> 焊盘位置和安全接法见 [`docs/hardware.md`](docs/hardware.md#串口大多数情况下你不需要它)。

---

## NAND 版：内置 NAND 的现状

**结论：NAND 版用本项目的引导从 U 盘启动，这就是正式用法。内置 NAND 装不了系统。**

第一份来自真实 WS1508 NAND 版的报告（[issue #2](../../issues/2)）给出了芯片：
海力士 **H27UBG8T2C**（ID `ad d7 94 91 60 44`），32Gbit **MLC**，
**8KB 页** + 640 字节 OOB，2MB 擦除块。这一颗芯片同时卡死了两条路：

- **UBI 拒绝挂载 MLC NAND**（`drivers/mtd/ubi/build.c`）。
  本项目原本的设计是 Linux 用 UBI/UBIFS 占芯片后半段做根文件系统，在 MLC 上这条路不存在。
- **主线 `meson_nand` 在 S805 上读不了大于 4KB 的页**：厂商代码给这种芯片用的是
  控制器的「new OOB」布局，驱动没实现，所以会直接拒绝挂载。

另一台 S805 盒子（MXQ，[issue #1](../../issues/1)）上的数据是同一个结论：
那台是 16KB 页的 SanDisk MLC。这一代电视盒子用的基本都是大页 MLC。
两份报告也确认了驱动本身在 S805 上**能跑**：时钟、引脚复用、复位和读 ID 都对。

### 这次修掉的问题

旧内核会把 H27UBG8T2C **误认成 4KB 页**（主线的海力士 ID 解码对这颗 20nm 料算错了，
页大小和 OOB 都只算出一半，正好绕过了上面那道「大于 4KB 就拒绝」的检查）。
驱动于是带着错误的几何参数挂载上去；如果再加了 `meson_nand.allow_write=1`
并运行安装脚本，擦写命令会落到**另外的物理块**上，地址超出芯片的部分还可能绕回芯片开头，
也就是厂商引导和元数据所在的位置。驱动自带的写保护是按同一套错误参数算的，拦不住。

现在：

- 内核按完整 ID 正确识别这颗芯片（8KB 页），驱动随即拒绝挂载，不会再有可写的 MTD；
- 芯片要求的 ECC 强度这个控制器满足不了时（误识别的典型症状），驱动一律只读，
  `allow_write=1` 也不放行；
- `ws1508-install-to-nand` 在擦除任何东西之前就拒绝 MLC 芯片和只读的 MTD；
- 驱动的挂载日志会打印芯片完整 ID，方便以后定位型号。

**如果你在旧版本上跑过 `ws1508-install-to-nand`：** 内置 NAND 的厂商区可能被写坏了一部分。
机器只要还能正常进 U-Boot 从 U 盘启动，就不影响使用；如果引导坏了，
按 [`docs/flashing.md`](docs/flashing.md) 用 USB Burning Tool（勾「擦除 flash」）重刷引导即可。

### 那「从内置 NAND 启动」的代码呢

U-Boot 里的 `boot_nand`、`scripts/make-nand-image.sh`、`ws1508-install-to-nand`
都还在仓库里，留给万一存在的「SLC、页不大于 4KB」的机器，
但 NAND 安装包已经不再随 Release 发布。真正能让这类盒子从内置 NAND 跑主线系统的路，
是把厂商的 `amlnf` 驱动连同 NFTL 二进制移植到新内核（RK3229 上有人这样做成过，
见 issue #1），目前没有人做。设计细节和来龙去脉见 [`docs/hardware.md`](docs/hardware.md)
和 [`docs/development.md`](docs/development.md)。

### 为什么社区的直刷包说「只支持 eMMC」

它们用的是玩客云的 U-Boot，而玩客云是纯 eMMC 机器，那份 U-Boot **没有开
`CONFIG_CMD_NAND`**，于是 `get_device_boot_flag()` 压根不会去探测 NAND，
NAND 机器自然启动不了。本项目的 U-Boot 打开了这个选项，
NAND 和 eMMC 两种机器都能识别、都能刷、都能从 U 盘启动。

---

## 针对 512MB 内存做的事

这机器只有 512MB，跑通用镜像很容易一开机就被 OOM 教做人。镜像里默认：

- **zram 交换**：lz4 算法，disksize 为内存的 200%，压缩数据最多占用内存的 50%
  （即最多 ~1GB 交换空间，实际最多吃掉 ~256MB 真实内存）；
- `vm.swappiness=100`、`vm.page-cluster=0`（zram 是随机访问，预读邻页纯属浪费）、
  `vm.vfs_cache_pressure=200`、更小的 dirty 比例；
- systemd journal 只放内存，上限 16MB；`armbian-ramlog` 缩到 32MB；
- 屏蔽掉这机器用不上或会在后台吃内存的服务：
  `ModemManager`、`bluetooth`、`wpa_supplicant`（没有无线硬件）、
  `apt-daily*` 定时器、`unattended-upgrades`、`man-db` 索引；
- 默认编译 `minimal` 镜像（可在 workflow 里改成 `cli`）。

具体见 [`userpatches/customize-image.sh`](userpatches/customize-image.sh)。

---

## 自己编译

### 用 GitHub Actions（推荐）

1. Fork 本仓库；
2. Actions → **Build WS1508 Armbian** → **Run workflow**；
3. 可选参数：
   - `release`：`trixie`(Debian 13，默认) / `bookworm`(Debian 12) / `noble`(Ubuntu 24.04) / `resolute`(Ubuntu 26.04)
   - `build_type`：`minimal`（推荐）/ `cli`
   - `root_password`：默认 root 密码
   - `ssh_authorized_key`：直接塞一把 SSH 公钥进去
4. 跑完在 Releases / Artifacts 里下载。手动触发且勾了 `publish_release` 的构建会发布 Release，
   同时也发布这一版的 apt 仓库（见 [`docs/upgrading.md`](docs/upgrading.md)）。

### 本地编译

需要 x86_64 的 Ubuntu 22.04/24.04 或 Debian 12/13，以及 root 权限：

```bash
# u-boot 用的是厂商自带的 32 位 x86 工具链，所以要开 i386 multiarch
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y build-essential git curl xz-utils python3 apt-utils \
    android-sdk-libsparse-utils device-tree-compiler \
    libc6:i386 zlib1g:i386 libstdc++6:i386

git clone https://github.com/dann2333/ws1508-armbian
cd ws1508-armbian

bash scripts/build-uboot.sh                    # 引导（约 3 分钟）
sudo -E bash scripts/build-armbian.sh build    # Armbian 镜像（较慢）
sudo -E bash scripts/make-burn-image.sh        # 打包直刷镜像
sudo -E bash scripts/make-apt-repo.sh          # 可选：把内核 / 板级包排成 apt 仓库
```

产物在 `output/` 下。

---

## 仓库结构

```
uboot/
  configs/m8b_ws1508.h        U-Boot 板级配置（开了 CONFIG_CMD_NAND，改了启动顺序）
  m8b_ws1508/                 板级代码：LED / 按键 / SD / USB / RMII 网口 / DDR 时序 / 分区表
  boards.cfg.append           注册到 U-Boot 板列表
userpatches/
  config/boards/ws1508.conf   Armbian 板级定义
  bootscripts/boot-ws1508.cmd 启动脚本
  bootenv/ws1508.txt          /boot/armbianEnv.txt 模板
  kernel/archive/meson-6.12/
    0000.patching_config.yaml 让 Armbian 自动把 dts 塞进内核并改 Makefile
    dt/meson8b-ws1508.dts     设备树（已修正内存为 512MB / 基址 0、网口为 RMII）
    dt/meson8b-ws1508-nand.dts  裸 NAND 版设备树（实验性，默认不用）
    ws1508-0100..0102-*.patch 给 meson_nand.c 加 meson8/meson8b 支持的内核补丁
                              （DMA info 缓冲区定尺 / SoC 支持 / 厂商区写保护）
    ws1508-0103-*.patch       dt-bindings: amlogic,meson-nand.yaml 加两个 compatible
    ws1508-0104-*.patch       arch/arm/boot/dts/amlogic/meson8b.dtsi 加 NFC 节点和引脚
    ws1508-0105-*.patch       nand_ids.c 按完整 ID 收录海力士 H27UBG8T2C（主线把它误认成 4KB 页）
    ws1508-0106-*.patch       ECC 满足不了芯片要求时强制只读；日志打印芯片完整 ID
  extensions/ws1508-nand.sh   打开 MTD / 裸 NAND 的内核配置
                              （编译时带 WS1508_NAND_SLUB_DEBUG=yes 可加 SLUB 调试）
  extensions/ws1508-bsp.sh    把 ws1508-* 工具放进板级支持包，写 apt pin，给镜像开更新通道
  customize-image.sh          SSH 自启 + 512MB 调优
  overlay/ws1508-info         报告机器型号、存储类型、更新通道状态
  overlay/ws1508-apt-setup    开启 / 修复 apt 更新通道和 pin（老设备从 Release 下载 .sh 版）
  overlay/ws1508-install-to-emmc  在机器上把系统装进 eMMC（自己写 MBR）
  overlay/ws1508-install-to-nand  装进内置 NAND（实验性；MLC 芯片会直接拒绝）
  overlay/ws1508-nand-probe   裸 NAND 只读诊断 / dump 工具
scripts/
  common.sh                   共用配置（U-Boot 固定 commit；Armbian 跟最新 main）
  build-uboot.sh              编译 U-Boot 并打包引导刷机包
  build-armbian.sh            调用 armbian/build 编译镜像（给每次构建的包打上递增版本号）
  make-burn-image.sh          合成完整直刷镜像
  make-apt-repo.sh            把内核 / 设备树 / 板级包排成 apt 仓库，随 Release 发布
  make-nand-image.sh          NAND 内核包（实验性，只作为构建产物，不随 Release 发布）
docs/
  flashing.md                 刷机、救砖
  upgrading.md                不重刷的 apt 升级
  hardware.md                 硬件细节、NAND / eMMC 分辨、串口
  development.md              开发笔记、已验证 / 未验证的东西
```

---

## 来源与致谢

- [armbian/build](https://github.com/armbian/build) —— Armbian 编译框架
- [syb999/uboot-onecloud](https://github.com/syb999/uboot-onecloud) —— 玩客云的 Amlogic BSP U-Boot，
  本项目的 `m8b_ws1508` 板级由它的 `m8b_onecloud` 派生
- [hzyitc/AmlImg](https://github.com/hzyitc/AmlImg) —— 打包 / 解包晶晨刷机镜像
- hzyitc —— 最早的玩客云主线移植与 `meson8b-ws1508.dts` 原始作者
- [lunatickochiya/Matrix-Action-Openwrt](https://github.com/lunatickochiya/Matrix-Action-Openwrt)
  —— WS1508 的 OpenWrt 移植与设备树
- 恩山无线论坛与各位折腾赚钱宝的网友

## 许可

设备树与 U-Boot 板级代码沿用上游许可（GPL-2.0）。
其余脚本与文档以 GPL-2.0 发布。
