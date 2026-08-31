# ws1508-armbian

给 **迅雷赚钱宝二代 / 赚钱宝 Pro（型号 WS1508）** 移植的 Armbian，
基于官方 [armbian/build](https://github.com/armbian/build) 框架 + 主线 6.12 内核，
由 GitHub Actions 全自动编译，**开机自启 SSH**。

- **eMMC 版机器**：可以直刷内置存储，拔掉 U 盘照样开机。
- **NAND 版机器**：可以直刷引导（U-Boot），系统跑在 U 盘/SD 卡上。

> WS1508 同时存在 **NAND** 和 **eMMC** 两种版本（连同一块 v1.1 主板都有两种），
> 本项目对两种都做了适配，但**能做到的程度不一样**，
> 原因见下面「NAND 版：为什么现在还不能从内置存储启动」。

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

eMMC 版还有一条**更稳妥的备选路线**：只刷 `ws1508-uboot.burn.img`，
U 盘启动后 SSH 进去跑 `ws1508-install-to-emmc`，由它自己在 eMMC 上写标准
MBR 并把系统装进去。不依赖烧录工具的分区行为，失败了插回 U 盘就复原。

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

## NAND 版：为什么现在还不能从内置存储启动

这一节以前写错过，现在按代码重写。要分开的是两件常被混在一起的事：
**引导程序读不读得到 NAND**，和**本项目有没有实现从 NAND 启动**。

### 引导程序读得到 NAND

本项目的 U-Boot 开了 `CONFIG_NEXT_NAND`（`uboot/configs/m8b_ws1508.h:153`），
这个宏同时做了两件方向相反的事：

- 它把 `drivers/mtd/libmtd.o` 和 `drivers/mtd/nand/libnand.o` 从构建里踢掉
  （厂商 U-Boot `Makefile:216-226`）。所以引导程序里**没有文件系统层**，
  `fatload` 不可能从 NAND 上的某个文件系统里读出 uImage；
- 但同一个宏又把 `common/store_interface.o` 编了进去
  （`common/Makefile:173-176`）。`store read <名字> <内存地址> <偏移> <长度>`
  在 `device_boot_flag` 是 NAND 时会转成 `amlnf read_byte` 下去
  （`common/store_interface.c:293-311`），命令自带的用法说明写的就是
  「read 'size' bytes … skipping bad blocks」（同文件 `:938`）。
  `amlnf read` / `amlnf chipinfo` 也都在（`drivers/amlnf/dev/cmd_amlnf.c`）。

也就是说：**按裸偏移读 NAND，引导程序做得到**——厂商 3.10 固件正是这么从
内置 NAND 启动的。缺的是文件系统那一层，不是读闪存的能力。

### 缺口在本项目这一侧：没做，不是做不了

1. **没有走 `store read` 的启动路径。**
   `userpatches/bootscripts/boot-ws1508.cmd` 从头到尾只有
   `fatload ${bootdev} …`，只认 usb / sd / mmc。要从内置 NAND 引导，
   得另写一个用 `store read` 把 uImage / uInitrd / dtb 从裸偏移读进内存
   再 `bootm` 的启动脚本，还得有一份和厂商分区表对得上的偏移。
   本仓库没有这个东西，也没有在实机上试过。
2. **根文件系统没有着落。**
   内置闪存上是厂商的 NFTL 布局，主线 Linux 没有能挂上去的驱动。
   想在上面放 UBI 就得动厂商保留区，而那块区域丢了补不回来（见下文）。
   理论上还可以整个塞进 initramfs 全内存跑，但这机器只有 512MB，
   那是另一个问题了。

所以准确的说法是：**这条路本项目没有实现、也没有验证过**，
而不是引导那一端原理上读不到 NAND。想接着做的人，上面两条就是入口。

现在能做到的是：把 U-Boot 刷进 NAND（U-Boot 自己带 Amlogic 的 `amlnf` 驱动，
读写 NAND 没问题），然后由它去 U 盘/SD 卡上把系统引导起来。

### 内核这边：有一个实验性的只读驱动

本项目给主线的 `drivers/mtd/nand/raw/meson_nand.c` 打了补丁，把
meson8/meson8b 加了进去（原本只认 `amlogic,meson-gxl-nfc` 和
`amlogic,meson-axg-nfc`）。默认**不启用**；在 `/boot/armbianEnv.txt` 里加
`fdtfile=meson8b-ws1508-nand.dtb` 重启之后，**如果驱动认得出这颗芯片**，
NAND 版机器上会出现一个**只读**的 `/dev/mtd0`。

在 eMMC 版机器上误加这一行不会把机器搞死：启动脚本会拿 U-Boot 自己探测到的
`${store}` 卡一道，不是裸 NAND 就打一行提示、退回 eMMC 设备树继续启动。

「如果」两个字是认真的：主线 meson-nand **从来没有在 meson8b 芯片上跑过**，
本项目也没有实机。预期之内的结果包括：`nand_scan()` 根本枚举不出芯片、
压根没有 `/dev/mtd0`；或者出来了，但读厂商写过的页全是 ECC 纠不回来。
在 ECC 强度和加扰器设置被确认对得上之前，后一种是**预期结果**，不是驱动坏了。

它的用处是把内置闪存**读**出来，看驱动读得对不对；不是让系统跑在上面。
默认关闭、默认只读，驱动还会挡掉落在厂商引导区里的擦写请求
（那道保护同样没在实机上验证过）。
细节、已知的未知、以及开之前该做什么，见
[`docs/hardware.md`](docs/hardware.md) 的「裸 NAND：能做什么、不能做什么」。

这也是为什么社区里现有的 WS1508 直刷包普遍写着「只支持 emmc 的，nand 的刷不了」：
它们用的是玩客云的 U-Boot，而玩客云是纯 eMMC 机器，
那份 U-Boot **没有开 `CONFIG_CMD_NAND`**，
于是 `get_device_boot_flag()` 压根不会去探测 NAND，NAND 机器自然启动不了。
本项目的 U-Boot 打开了这个选项，NAND 和 eMMC 两种机器都能识别、都能刷。

如果你就是要 NAND 版把系统装进内置存储并从那里启动，**现成能用的**
只有一条路：用厂商 3.10 内核的老固件（社区有 Debian 10 的 NAND 直刷包）。
那条路和主线内核 / 新版 Debian / Docker 是互斥的，本项目不做。
自己去实现上面那两个缺口是另一条路，但那是开发工作，不是刷个包就行。

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
    dt/meson8b-ws1508.dts     设备树（已修正内存为 512MB / 基址 0、网口为 RMII）
    dt/meson8b-ws1508-nand.dts  裸 NAND 版设备树（实验性，默认不用）
    ws1508-0100..0102-*.patch 给 meson_nand.c 加 meson8/meson8b 支持的内核补丁
                              （DMA info 缓冲区定尺 / SoC 支持 / 厂商区写保护）
    ws1508-0103-*.patch       dt-bindings: amlogic,meson-nand.yaml 加两个 compatible
    ws1508-0104-*.patch       arch/arm/boot/dts/amlogic/meson8b.dtsi 加 NFC 节点和引脚
  extensions/ws1508-nand.sh   打开 MTD / 裸 NAND 的内核配置
                              （编译时带 WS1508_NAND_SLUB_DEBUG=yes 可加 SLUB 调试）
  customize-image.sh          SSH 自启 + 512MB 调优
  overlay/ws1508-install-to-emmc  在机器上把系统装进 eMMC（自己写 MBR）
  overlay/ws1508-nand-probe   裸 NAND 只读诊断 / dump 工具
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
