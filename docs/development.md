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

### 2. `CONFIG_CMD_NAND` 本身还不够

只开这个宏还是不行 —— 这一点是代码审查抓出来的，我一开始漏了。
`get_device_boot_flag()` 是这么写的：

```c
device_boot_flag = CARD_BOOT_FLAG;     // ← 先设成 CARD
...
    if(amlnf_init(0x5) == 0) {
        device_boot_flag = NAND_BOOT_FLAG;   // ← 想在成功后再设成 NAND
```

而 `amlnf_init()` 第一件事就是 `get_boot_device()`
（`drivers/amlnf/dev/amlnf_dev.c`），它读的正是这个全局变量：

```c
if(device_boot_flag == CARD_BOOT_FLAG){
    boot_device_flag = -1;
    aml_nand_msg("CARD BOOT: not init nand");
    return -1;
}
```

于是 `amlnf_init()` 在真正碰 NAND 之前就返回 -1，那句
`device_boot_flag = NAND_BOOT_FLAG` **永远执行不到**。表现是串口打出
`try nand boot` 紧接着 `CARD BOOT: not init nand`，然后什么都没发生。

`uboot/patches/0001-board-set-NAND_BOOT_FLAG-before-probing-NAND.patch`
把顺序改过来：探测前先认领 `NAND_BOOT_FLAG`，失败再还回 `CARD_BOOT_FLAG`。
eMMC 那一支不用改，`emmc_init()` 不看这个变量（这也是为什么玩客云一直没事）。

反汇编可以验证补丁生效（`mov r6,#1` 存进去，然后才 `bl amlnf_init`）：

```console
$ arm-none-eabi-objdump -d build/arch/arm/lib/board.o | sed -n '/<get_device_boot_flag>:/,/^$/p'
 11c: mov r3, #3     ← 初始 CARD_BOOT_FLAG
 1b8: mov r6, #1     ← NAND_BOOT_FLAG，补丁加的
 1c0: mov r0, #5     ← amlnf_init(0x5)
 1dc: mov r3, #3     ← 失败还回 CARD_BOOT_FLAG
```

`scripts/build-uboot.sh` 会检查补丁是否在位，不在就拒绝出包。

### 3. 启动顺序

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
| `memory` 基址 `0x40000000` → `0x00000000` | 所有主线 meson8b 板子都写 0x40000000，但那个值从来没生效过（引导总会重写）。真实基址是 0，见下 |
| 蓝灯触发器换成 `heartbeat` | 原版是 `usb-host`；`heartbeat` 让没串口时也能看出内核死没死 |
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

## 加载地址：512MB 板子最容易踩的雷

`boot-ws1508.cmd` 一开始是照抄 Armbian 的 `boot-onecloud.cmd` 的，
它把 `armbianEnv.txt` / uImage / dtb / uInitrd 加载到
`0x20800000` / `0x21800000` / `0x22000000`。
玩客云有 1GB，这些地址（520~544MB）都在内存里，没问题。
**WS1508 只有 512MB，内存到 `0x20000000` 就结束了。**

而且后果比"地址没有内存"更直接：`CONFIG_ACS` 会让 `dram_init()` 调用
`update_ddr_mmu_table()`，它按运行期实测出来的容量
（`CONFIG_DDR_SIZE_IND_ADDR` 里的 512）把**超出部分每个 1MB 段的一级页表项清零**。
U-Boot 此时 MMU 是开着的（`cpu_init_crit` → `cache_init` 无条件置位 SCTLR.M），
所以往 `0x20800000` 写就是**翻译错误 → data abort → U-Boot 直接挂掉**。
第一个踩雷的其实是 `armbianEnv.txt` 那一行，内核都还没轮到。

（注意：这跟我改的 `PHYS_MEMORY_SIZE` 无关。开了
`CONFIG_DDR_SIZE_AUTO_DETECT` 之后 `cpu.h` 会 `#undef CONFIG_MMU_DDR_SIZE`
并强制成 2GB，页表是运行期按实测容量裁的。）

DRAM 基址是 `0x00000000`，不是设备树里写的 `0x40000000`：
`arch/arm/include/asm/arch-m8b/cpu.h` 里 `CONFIG_SYS_SDRAM_BASE 0x00000000`，
`dram_init_banksize()` 拿它填 `gd->bd->bi_dram[0].start`，
再由 `fdt_fixup_memory_banks()` 写进设备树。

低 512MB 里已经有主的区域：

| 地址 | 占用者 |
|---|---|
| `0x10000000` (256MB) | U-Boot 自己（`CONFIG_SYS_TEXT_BASE`）+ 12MB malloc |
| `0x12000000` (288MB) | `${loadaddr}`：`boot.scr` 本体，脚本跑完之前一直在用 |
| `0x13000000` (304MB) | `${loadaddr_logo}`，`imgread pic resource` 用 |
| `0x15100000` (337MB) | `${fb_addr}`，framebuffer（1280x720x24 约 2.7MB） |

所以现在的布局全部避开它们：

| 地址 | 用途 |
|---|---|
| `0x11000000` (272MB) | `armbianEnv.txt` 暂存 |
| `0x16000000` (352MB) | `uImage`，留了 64MB |
| `0x1a000000` (416MB) | `dtb` |
| `0x1a800000` (424MB) | `uInitrd`，下面还有约 88MB |

移植到其它内存更小的 S805 板子时，这是第一个要改的地方。

---

## 镜像里做的验证

出错要在构建期炸掉，不能等用户刷进去才发现：

| 脚本 | 检查 |
|---|---|
| `build-uboot.sh` | 编出来的 U-Boot 里同时有 `try nand boot` 和 `try emmc boot`；NAND 探测顺序补丁在位 |
| `build-armbian.sh` | 镜像 boot 分区里有 `dtb/meson8b-ws1508.dtb`、`boot.scr` 和 `uInitrd`（启动脚本无条件加载 uInitrd，缺了就起不来） |
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

## eMMC 直刷：一个没能静态确认的环节

`.burn.img` 把 Armbian 镜像的 p1 / p2 写进 U-Boot 分区表里的 `boot` / `rootfs`
两个分区，但**没有**写 LBA 0 的 MBR（那块地方属于 `bootloader` 分区）。

而 U-Boot 这边，`fatload mmc 1 ...` 的解析路径是
`fat_register_device()`（`fs/fat/fat.c`）：它先读第 0 扇区，检查 0x55AA 签名，
再走 `get_partition_info()` → `get_partition_info_dos()`。本板只开了
`CONFIG_DOS_PARTITION`，`disk/part.c` 里也没有 Amlogic 的特殊分支，
`mmc_bread()` 也没有给块地址加任何基址偏移。

照这个链路推，eMMC 上没有 MBR 的话 `fatload mmc 1` 应该找不到分区。
但玩客云那边**同样的流水线**（hzyitc / suwei8 / lunatickochiya，都是
`img2simg p1/p2` + `PARTITION:boot` / `PARTITION:rootfs`，U-Boot 默认环境也是
`fatload mmc 1 boot.scr`）是公认能从 eMMC 启动的。也就是说这中间还有一环
我没能只靠读代码确认 —— 大概率是烧录工具写 `bootloader` 分区时的实际落盘位置，
和我推断的分区偏移不一样。

**对使用者的意义，以及怎么在没有串口的情况下判断**：

eMMC 版刷完 `.burn.img`、拔掉 U 盘、通电，等 2 分钟：

- **能在路由器里看到 `ws1508` / 能 SSH 进去** → 这一环没问题，直刷可用；
- **完全没上网** → 大概率就是这个原因。不用接串口，直接走
  `ws1508-install-to-emmc` 那条路（刷 `ws1508-uboot.burn.img` →
  U 盘启动 → 跑脚本），它自己写 MBR，绕开整个问题。

只有在你**想知道具体卡在哪**的时候才需要串口，那时的特征是
`** Partition 1 not valid on device 1 **` 或 `fatload` 失败。

请把结果反馈回来，确认后我会把写 MBR 这一步固化进构建流程。

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

**这些都不需要串口就能反馈。** U-Boot 的存储探测结果会通过内核命令行
`ws1508.store=`（1=NAND / 2=eMMC / 3=没探测到）传进系统，
SSH 进去跑 `ws1508-info` 就能看到，机器能上网就够了。

欢迎有实机的同学反馈。
