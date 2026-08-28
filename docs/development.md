# 开发说明

这份文档记录移植过程中的关键决定和依据，方便后来者维护。

---

## 启动链

```
S805 片内 ROM
  └─ 从内置闪存（NAND 或 eMMC）读 bootloader 分区
       └─ DDR.USB (ddr_init)  ← 自动探测 DDR 位宽与容量
            └─ UBOOT_COMP.USB (UCL 压缩的 u-boot)
                 └─ u-boot
                      ├─ update 1000        留 1 秒给 USB 烧录工具
                      ├─ get_device_boot_flag()  探测 NAND → eMMC
                      └─ bootcmd: usb → sd → emmc
                           └─ fatload ${bootdev} boot.scr && autoscr
                                └─ Armbian boot.scr（由 boot-ws1508.cmd 编译而来）
                                     ├─ 读 armbianEnv.txt 拿 rootdev
                                     ├─ fatload uImage / uInitrd / dtb/meson8b-ws1508.dtb
                                     └─ bootm
                                          └─ u-boot 用实测 DDR 容量重写 /memory 节点
                                               └─ Linux 6.12
```

关键点：`${bootdev}` 由 u-boot 设置，`boot.scr` 之后所有的加载都用同一个
`${bootdev}`。所以**同一个镜像**从 U 盘、SD 卡还是 eMMC 启动都不用改。

---

## 为什么要自己编 U-Boot，而不是直接用玩客云的

社区现有的 WS1508 方案都是「刷玩客云 hzyitc 的 U-Boot 底包 + 改 dtb 和启动脚本」。
那样能用，但有两个问题：

### 1. NAND 版机器刷不了（这是最主要的原因）

`arch/arm/lib/board.c` 里的 `get_device_boot_flag()` 长这样：

```c
#ifdef CONFIG_CMD_NAND
    if (failed || POR_NAND_BOOT()) {
        ...
        if (amlnf_init(0x5) == 0) { device_boot_flag = NAND_BOOT_FLAG; return; }
        failed = true;
    }
#endif
#ifdef CONFIG_CMD_MMC
    if (failed || POR_EMMC_BOOT()) {
        ...
        if (emmc_init() == 0) { device_boot_flag = EMMC_BOOT_FLAG; return; }
        failed = true;
    }
#endif
```

玩客云是纯 eMMC 机器，`m8b_onecloud.h` 里**没有** `CONFIG_CMD_NAND`
（`build/include/autoconf.mk` 里只有 `CONFIG_CMD_MMC=y`），
整个 NAND 分支被编译掉了。于是 NAND 版 WS1508 永远探测不到自己的存储，
`device_boot_flag` 停在 `CARD_BOOT_FLAG`，U-Boot 既读不了闪存也没法接受烧录。

这正是恩山上那些直刷包统一写着「只支持 emmc 的」「nand 的刷不了」
「写入也没用，启动不了的」的根本原因。

`m8b_ws1508.h` 加了一行 `#define CONFIG_CMD_NAND 1` 就解决了 ——
amlnf 驱动本来就因为 `CONFIG_NEXT_NAND=y` 编进去了，缺的只是这个开关。
USB 烧录路径（`drivers/usb/gadget/v2_burning/`）用的也是运行期的
`device_boot_flag`，所以同一个 U-Boot 二进制能给两种机器烧录。

编译产物里可以直接验证：

```console
$ strings build/u-boot-orig.bin | grep "try .* boot"
try emmc boot
try nand boot
```

`scripts/build-uboot.sh` 会做这个检查，缺任何一个就拒绝出包。

### 2. 启动顺序

玩客云的 `CONFIG_BOOTCOMMAND` 只有 `run boot_emmc_armbian`，
NAND 机器无路可走。本项目改成 `usb → sd → emmc`，
既让 NAND 机器能从 U 盘跑，也给所有机器留了一条不用拆机的救砖通道。

---

## DDR：一份时序覆盖两种容量

`uboot/m8b_ws1508/firmware/timming.c` 是从玩客云**原样复制**的，
只改了 `#error` 里的板子名。这是有意的：

- `CONFIG_DDR_MODE_AUTO_DETECT` → `ddr_mode_auto_detect()` 依次试
  32bit、16bit lane0+2、16bit lane0+1，哪个能初始化成功用哪个；
- `CONFIG_DDR_SIZE_AUTO_DETECT` → `ddr_size_auto_detect()` 依次试
  256MB / 512MB / 1GB。

WS1508（单颗 x16，512MB）实测落在 `16 bit mode lane0+1` + `512MB`，
玩客云（双颗，1GB）落在 32bit + 1GB，同一份时序都能跑。

`m8b_ws1508.h` 里只把 `PHYS_MEMORY_SIZE` 改成 `0x20000000`，
那个宏不参与 DDR 初始化，只用来定 `CONFIG_SYS_BOOTMAPSZ`。

**没有**定义 `CONFIG_DDR_MODE_AUTO_DETECT_SKIP_32BIT`：
它能省掉一次注定失败的 32bit 尝试，但万一真有哪批 WS1508 焊了两颗内存，
跳过 32bit 就直接起不来了。省的那点时间不值这个风险。

---

## 设备树

`userpatches/kernel/archive/meson-6.12/dt/meson8b-ws1508.dts`
基于 hzyitc / lunatickochiya 的社区版本，改了三处：

| 改动 | 原因 |
|---|---|
| `memory` 节点 1GB → 512MB | 原版是从玩客云复制时漏改的，见 `hardware.md` |
| LED 触发器换成 `default-on` / `disk-activity` / `heartbeat` | 原版绿灯绑死 `mmc1`，从 U 盘启动时永远不亮；`heartbeat` 让没串口时也能看出内核死没死 |
| 去掉 `RTL8211F` 注释 | 那是玩客云的千兆 PHY，WS1508 是 RMII 百兆，注释会误导人 |

保留不动的：RMII 网口配置、`&sdhc` eMMC、`&sdio` SD 卡槽、
`usb0` OTG、PWM 调压 —— 这些社区版本是对的。

### 接入 Armbian 的方式

没有写 `.patch` 文件，而是用 Armbian 自带的设备树自动打补丁器：

```
userpatches/kernel/archive/meson-6.12/
├── 0000.patching_config.yaml
└── dt/meson8b-ws1508.dts
```

`0000.patching_config.yaml` 里的 `dts-directories` 让 Armbian 把 `dt/` 下的
所有 `.dts` 拷进 `arch/arm/boot/dts/amlogic/`，
`auto-patch-dt-makefile` 让它往那个目录的 Makefile 追加
`dtb-$(CONFIG_MACH_MESON8) += meson8b-ws1508.dtb`。

好处是**没有上下文可冲突** —— 上游怎么改 amlogic 的 Makefile 都不用 rebase。

> 注意 config 变量是 `CONFIG_MACH_MESON8` 而不是 `MESON8B`：
> 内核里 meson8b 的板子全挂在 MESON8 这个符号下面。

`KERNELPATCHDIR` 是 Armbian 按 `archive/${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}`
推出来的，也就是 `archive/meson-6.12`。
如果哪天 Armbian 把 meson 家族的内核换了版本，这个目录就不会被读到，
dtb 会**悄无声息地**从镜像里消失。`scripts/build-armbian.sh` 会检测
上游实际配置的版本并自动把目录镜像过去，同时打印警告。

---

## 镜像里做的验证

出错要在构建期炸掉，不能等用户刷进去才发现：

| 脚本 | 检查 |
|---|---|
| `build-uboot.sh` | 编出来的 U-Boot 里同时有 `try nand boot` 和 `try emmc boot` |
| `build-armbian.sh` | 镜像 boot 分区里有 `dtb/meson8b-ws1508.dtb` 和 `boot.scr` |
| `make-burn-image.sh` | 打好的 burn 包能被 AmlImg 原样解回来，且 5 个必需成员齐全 |

---

## 踩过的坑

**`set -o pipefail` + `grep -q`**
`strings foo | grep -q x` 里 grep 匹配到就退出，上游 `strings` 吃 SIGPIPE 挂掉，
pipefail 让整条管道报错 —— 明明找到了却判定成没找到。改用 `grep -c`。
GitHub Actions 的 `run:` 默认就带 `-o pipefail`，同样要注意 `| head -1`。

**容器里没有 udev**
`losetup --partscan` 依赖 udev 创建 `/dev/loopNpM`，容器里通常没有，
于是分区设备节点根本不出现，而且不报错。
`make-burn-image.sh` 改成自己解析 MBR，然后用
`losetup --offset/--sizelimit` 给每个分区单独挂一个 loop 设备。

**`memory` 节点不能带单元地址**
见 `hardware.md`。`dtc` 的 `unit_address_vs_reg` 警告是故意留的。

**给 chroot 传参数**
Armbian 用 `chroot ... /usr/bin/env bash -c` 调 `customize-image.sh`，
环境变量能不能传过去属于实现细节。改成写
`userpatches/overlay/ws1508-build.conf`，Armbian 会把 `userpatches/overlay`
绑定挂载到 chroot 里的 `/tmp/overlay`，这是有文档保证的通道。

---

## 还没验证的部分

本项目**没有 WS1508 实机**。以下是照着资料和上游代码做的，需要实机确认：

- U-Boot 的 RMII 网口初始化（`uboot/m8b_ws1508/eth.c`）照抄 Amlogic
  m8b 参考板 `m8b_m201_v1`。只影响 U-Boot 自己的 tftp/dhcp，
  Linux 会按设备树重新配置 `PREG_ETHERNET_ADDR0`，所以就算不对也不影响系统；
- `usb0` / `usb1` 两个控制器都在 U-Boot 里初始化了（照抄玩客云）。
  WS1508 只有一个 USB 口，多初始化一个不存在的控制器无害，
  这样也不用赌到底哪个是对的；
- eMMC 的 `max-frequency = <200000000>` 和 `mmc-hs200-1_8v` 沿用社区设备树。
  如果实机 eMMC 不稳定，先把这两项降下来试；
- 完整 `.burn.img` 在 NAND 版机器上的行为（预期：引导能写，
  boot/rootfs 白写，最后还是从 U 盘启动）。

欢迎有实机的同学反馈。
