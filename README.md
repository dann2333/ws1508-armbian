# ws1508-armbian

给 **迅雷赚钱宝二代 / 赚钱宝 Pro（型号 WS1508）** 移植的 Armbian，
基于官方 [armbian/build](https://github.com/armbian/build) 框架 + 主线 6.12 内核，
由 GitHub Actions 全自动编译，**开机自启 SSH**。

- **eMMC 版机器**：可以直刷内置存储，拔掉 U 盘照样开机。
- **NAND 版机器**：可以直刷引导（U-Boot），系统跑在 U 盘/SD 卡上。

> WS1508 同时存在 **NAND** 和 **eMMC** 两种版本（连同一块 v1.1 主板都有两种），
> 本项目对两种都做了适配，但**能做到的程度不一样**，
> 原因见下面「NAND 版为什么不能把系统装进内置存储」。

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
| **eMMC 版** | `Armbian_*_ws1508_*.burn.img` | Amlogic USB Burning Tool | ✅ 直刷内置存储，完全脱离 U 盘 |
| **NAND 版** | `ws1508-uboot.burn.img` | Amlogic USB Burning Tool | ⚠️ 只刷引导，系统在 U 盘上 |
| **先试试看** | `Armbian_*_ws1508_*.img.xz` | 解压后写入 U 盘 / SD 卡 | 不动内置存储 |

完整步骤（含进入刷机模式、救砖）见 [`docs/flashing.md`](docs/flashing.md)。

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
- SSH 主机密钥在**首次开机时才生成**（不会所有人的机器共用同一份密钥）。

> 🔒 刷完请立刻 `passwd` 改密码。默认密码是为了让你能进得去，不是为了长期用。
> 如果这台机器会暴露在公网上，建议编译时直接填 SSH 公钥并把
> `root_password_login` 关掉。

登录后可以运行 `ws1508-info`，它会告诉你这台机器是 NAND 还是 eMMC、
内存多大、根文件系统在哪。

---

## NAND 版为什么不能把系统装进内置存储

主线 Linux **没有** S805（meson8b）的裸 NAND 控制器驱动 ——
内核里的 `drivers/mtd/nand/raw/meson_nand.c` 只认 `amlogic,meson-gxl-nfc`
和 `amlogic,meson-axg-nfc`，meson8b 不在其中。
所以 NAND 版机器上，Linux 根本读不到内置存储，根文件系统只能放在 U 盘或 SD 卡。

能做到的是：**把 U-Boot 刷进 NAND**（U-Boot 自己带 Amlogic 的 `amlnf` 驱动，
读写 NAND 没问题），然后由它去 U 盘/SD 卡上把系统引导起来。

这也是为什么社区里现有的 WS1508 直刷包普遍写着「只支持 emmc 的，nand 的刷不了」：
它们用的是玩客云的 U-Boot，而玩客云是纯 eMMC 机器，
那份 U-Boot **没有开 `CONFIG_CMD_NAND`**，
于是 `get_device_boot_flag()` 压根不会去探测 NAND，NAND 机器自然启动不了。
本项目的 U-Boot 打开了这个选项，NAND 和 eMMC 两种机器都能识别、都能刷。

如果你就是要 NAND 版把系统装进内置存储，目前只有一条路：
用厂商 3.10 内核的老固件（社区有 Debian 10 的 NAND 直刷包）。
那条路和主线内核 / 新版 Debian / Docker 是互斥的，本项目不做。

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
   - `release`：`bookworm`(Debian 12) / `trixie`(Debian 13) / `noble`(Ubuntu 24.04)
   - `build_type`：`minimal`（推荐）/ `cli`
   - `root_password`：默认 root 密码
   - `ssh_authorized_key`：直接塞一把 SSH 公钥进去
4. 跑完在 Releases / Artifacts 里下载。

### 本地编译

需要 x86_64 的 Ubuntu 22.04/24.04 或 Debian 12/13，以及 root 权限：

```bash
# u-boot 用的是厂商自带的 32 位 x86 工具链，所以要开 i386 multiarch
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y build-essential git curl xz-utils python3 \
    android-sdk-libsparse-utils device-tree-compiler \
    libc6:i386 zlib1g:i386 libstdc++6:i386

git clone https://github.com/dann2333/ws1508-armbian
cd ws1508-armbian

bash scripts/build-uboot.sh                    # 引导（约 3 分钟）
sudo -E bash scripts/build-armbian.sh build    # Armbian 镜像（较慢）
sudo -E bash scripts/make-burn-image.sh        # 打包直刷镜像
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
    dt/meson8b-ws1508.dts     设备树（已修正内存为 512MB、网口为 RMII）
  customize-image.sh          SSH 自启 + 512MB 调优
scripts/
  common.sh                   共用配置（上游仓库均已固定 commit）
  build-uboot.sh              编译 U-Boot 并打包引导刷机包
  build-armbian.sh            调用 armbian/build 编译镜像
  make-burn-image.sh          合成完整直刷镜像
docs/
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
