# WS1508 硬件说明

## 规格

| 项目 | 参数 | 依据 |
|---|---|---|
| SoC | Amlogic S805（meson8b），4 核 Cortex-A5 @1.5GHz，ARMv7 32 位 | 官方规格 / 拆机照片 |
| GPU | Mali-450 | S805 规格 |
| 内存 | **512MB** DDR3，单颗 x16 颗粒，**16 bit 位宽** | 拆机照片 + 串口日志 |
| 内置存储 | **4GB**（32Gb），裸 NAND **或** eMMC，视批次而定 | 拆机照片 + 社区反馈 |
| 网口 | 100Mbps，RMII 接口，PHY 复位接 GPIOH_4 | 设备树 / OpenWrt 移植 |
| USB | USB 2.0 × 1，OTG | 官方规格 |
| 无线 | 无 | 官方规格 |
| 显示输出 | **无**（主板不带 HDMI） | 拆机 / 社区反馈 |
| TF 卡槽 | **无**（一代有，二代砍掉了） | 社区反馈 |
| 指示灯 | 红 GPIOAO_2 / 绿 GPIOAO_3 / 蓝 GPIOAO_4 | 设备树 |
| 按键 | 1 个，GPIOAO_5 | 设备树 |
| 电源 | 12V / 1A | 官方规格 |
| 串口 | 主板焊盘，115200 8N1，3.3V | 社区 TTL 教程 |

### 内存为什么确定是 512MB

网上流传的 `meson8b-ws1508.dts` 里写的是 1GB，那是错的 —— 它是从玩客云
（WS1608，确实是 1GB）的设备树复制过来时忘了改。同一份文件里还留着玩客云的
`Realtek RTL8211F` 注释和 `ETH_RGMII_TX_CLK` 引脚名，而 WS1508 是 RMII 百兆，
可见作者只改了 model/compatible/LED/phy-mode，其余原样保留。

实机证据：

1. **串口日志**（社区 TTL 教程里的截图）：
   ```
   DDR mode: 16 bit mode lane0+1
   DDR size: 512MB (auto)
   DDR check: Pass!
   ...
   DRAM:  512 MiB
   ```
   `(auto)` 表示这是 Amlogic `ddr_size_auto_detect()` 实测出来的，不是编译时写死的。

2. **拆机照片**：两块不同的 WS1508 v1.1 主板，都只焊了**一颗** NANYA DDR3
   （96 球 FBGA，x16），旁边还有一个**完全空着的同款焊盘**，背面没有内存颗粒。
   单颗 x16 = 16 bit 位宽，正好对上串口里的 `16 bit mode lane0+1`。
   玩客云则是两颗都焊上，所以是 1GB。

3. 包装盒丝印、爱搞机评测、百度百科、天极产品库等约 10 份公开资料
   全部写 512MB，**没有一份**说 WS1508 是 1GB。

本项目的设备树已经改成 512MB。不过实际生效的值来自 U-Boot：
Amlogic 的 BSP U-Boot 开了 `CONFIG_DDR_SIZE_AUTO_DETECT`，
会自动探测出真实容量，并在进内核前用 `fdt_fixup_memory_banks()`
覆盖设备树里的 `memory` 节点。

> ⚠️ 改设备树时注意：那个 `memory` 节点**不能**改名成 `memory@40000000`。
> U-Boot 是用 `fdt_path_offset(blob, "/memory")` 精确匹配路径去找它的，
> 一旦带上单元地址就找不到，U-Boot 会另外插一个空的 `memory` 节点然后直接返回，
> 探测到的内存大小就被丢掉了。`dtc` 会为此报一个
> `unit_address_vs_reg` 警告 —— 那个警告是**故意留着**的。

---

## 怎么分辨自己是 NAND 版还是 eMMC 版

WS1508 的闪存位置是**一个二合一焊盘**：外圈是 TSOP-48 的引脚焊盘，
中间是一片 BGA 球阵。迅雷两种都用过，**同一个 v1.1 主板版本都存在两种**。

### 方法一：开机后用软件看（最省事）

如果机器已经能跑本项目的系统（U 盘启动也行）：

```bash
ws1508-info
```

它会直接告诉你是 eMMC 还是 NAND。手动看也行：

```bash
lsblk                      # 有 mmcblk1 → eMMC 版
ls /dev/mmcblk*
dmesg | grep -i mmc
```

- 能看到 **`/dev/mmcblk1`**（约 3.6GiB）→ **eMMC 版**
- 一个 `mmcblk*` 都没有 → **NAND 版**（这机器没有 TF 卡槽，所以正常情况下
  `mmcblk0` 本来就不存在，能出现的只有 eMMC 的 `mmcblk1`）

> 注意：默认设备树里 NAND 控制器是关掉的，所以 NAND 版机器上默认
> **不会**出现 `/dev/mtd*`，看不到不等于没有闪存。本项目现在带了一个
> 实验性的 meson8b 裸 NAND 驱动，需要手动切设备树才生效，
> 见下面「裸 NAND：能做什么、不能做什么」。

### 方法二：拆机看闪存芯片

看主板上靠近边缘的那颗闪存：

| 封装 | 长相 | 结论 |
|---|---|---|
| TSOP-48 | 长方形，**两条长边各有 24 条向外伸的鸥翼引脚** | **NAND 版** |
| BGA | 一小块方形芯片，**没有外露引脚**，坐在焊盘中间，上下两排引脚焊盘空着 | **eMMC 版** |

eMMC 不存在 TSOP-48 封装，所以看到引脚就一定是裸 NAND。
NAND 版上那颗芯片一般印的是迅雷自己的料号（例如 `WS1508CRA10L`），
查不到容量，属正常。

### 方法三：看 U-Boot 的探测结果（不用拆机、不用串口）

本项目的 U-Boot 会把自己探测到的存储类型通过内核命令行传给系统，
所以 SSH 进去就能看到：

```bash
cat /proc/cmdline | tr ' ' '\n' | grep ws1508.store
# ws1508.store=1  → 裸 NAND
# ws1508.store=2  → eMMC
# ws1508.store=3  → 没探测到（不正常，见 development.md）
```

`ws1508-info` 会直接把它翻译成人话。

如果你确实接了串口，通电时也能看到对应的
`try nand boot` / `try emmc boot` 字样。

---

## 裸 NAND：能做什么、不能做什么

主线的 `drivers/mtd/nand/raw/meson_nand.c` 原本只认 `amlogic,meson-gxl-nfc`
和 `amlogic,meson-axg-nfc`。本项目在
`userpatches/kernel/archive/meson-6.12/` 下带了 **5 个**补丁
（`ws1508-0100` 到 `ws1508-0104`），把 meson8/meson8b 加了进去：
寄存器映射和命令编码和 GXL 完全一样，差别在时钟树、启动页的 BCH 码、
加扰器和一个会越界的 DMA。

| 补丁 | 动的文件 |
|---|---|
| `0100` | `meson_nand.c`：给 DMA info 缓冲区定尺，并给 ECC 完成轮询加超时 |
| `0101` | `meson_nand.c`：加 meson8/meson8b 两个 compatible 和它们的差异项 |
| `0102` | `meson_nand.c`：厂商引导区写保护（单独一个补丁，免得被顺手丢掉） |
| `0103` | `Documentation/devicetree/bindings/mtd/amlogic,meson-nand.yaml` |
| `0104` | `arch/arm/boot/dts/amlogic/meson8b.dtsi`：NFC 节点和 nand 引脚组 |

审查或 rebase 的时候请数够 5 个 —— 尤其是 `0102`，
它是 `meson_nand.allow_write=1` 和厂商引导区之间唯一的东西。

### 先说清楚：这**不会**让机器从内置存储启动

不会，但理由不是「引导程序读不到 NAND」——那句话本仓库早先版本写过，是错的。
准确的分界线是：

- 引导程序**没有文件系统层**。`CONFIG_NEXT_NAND`
  （`uboot/configs/m8b_ws1508.h:153`）让 Amlogic 的 `Makefile` 把
  `drivers/mtd/libmtd.o` 和 `drivers/mtd/nand/libnand.o` 从构建里踢掉
  （`Makefile:216-226`），所以 `fatload` 不可能从 NAND 上的某个文件系统里
  读出 uImage。
- 但引导程序**能按裸偏移读 NAND**。同一个宏把 `common/store_interface.o`
  编了进去（`common/Makefile:173-176`）：`store read <名字> <地址> <偏移> <长度>`
  在探测到 NAND 时转成 `amlnf read_byte`（`common/store_interface.c:293-311`），
  用法说明就写着「read 'size' bytes … skipping bad blocks」（`:938`）。
  厂商 3.10 固件就是靠这条路从内置 NAND 启动的。
- 差的是**本项目没实现这条路**。`userpatches/bootscripts/boot-ws1508.cmd`
  只会 `fatload ${bootdev} …`，没有 `store read` 分支；而且就算引导起来了，
  内置闪存上是厂商的 NFTL 布局，主线 Linux 没有能挂上去的根文件系统方案。

所以：**从内置 NAND 启动在本项目里是「没做」，不是「做不到」。**
谁想做，缺口就是上面两条——一个 `store read` 版的启动脚本（外加一份对得上的
偏移表），和一个不动厂商保留区的根文件系统方案。在此之前，
内核、initrd、dtb 一律来自 U 盘或 SD 卡。

内核这边**期望**给出的是一个 `/dev/mtd0`：把闪存**读**出来，仅此而已。
写「期望」是因为这个驱动从来没在 meson8b 芯片上跑过 —— 见下面
「已知没验证过的地方」。

### 怎么开

**先确认你这台是 NAND 版。** 跑 `ws1508-info`，只有它报
`store: raw NAND` 才往下走。

> 加错了不会把机器搞成起不来：`boot-ws1508.cmd` 会拿 U-Boot 自己的探测结果
> `${store}` 卡一道，只有 `store=1`（裸 NAND）才放行这个设备树，否则打一行
> `... needs a raw-NAND unit (store=...) - falling back to meson8b-ws1508.dtb`
> 然后退回 eMMC 设备树照常启动。`store=3`（U-Boot 什么都没探测到）也一样挡回去。
>
> 这道闸没法用 `armbianEnv.txt` 绕开：启动脚本在 `env import` **之前**就先把
> U-Boot 的探测值抄进 `${ws1508_store}`，而 `env import` 不带 `-d` 是覆盖式的
> （`common/cmd_nvedit.c:710`）—— 在 `armbianEnv.txt` 里写 `store=1` 只改得掉
> `${store}`，改不掉判断用的那一份，传给内核的 `ws1508.store=` 也仍然是硬件
> 的真实结果。
>
> 之所以要有这道闸：这个设备树把 `&sdhc` 关了，`mmcblk1` 会整个消失，
> 而 eMMC 上装了系统的机器根文件系统就在那上面，内核会一直卡在 `rootwait`；
> 那行 `fdtfile=` 又写在 eMMC 的 boot 分区里，系统起不来就改不了。
> 现在这条路走不到了，代价是「设备树被忽略」而不是「机器不启动」。
>
> 注意这道闸在**本项目的 `boot.scr`** 里。用别的启动脚本（比如社区的
> 玩客云底包）就没有这层保护，那时上面那段仍然成立：救法是做一张启动 U 盘
> 插上（U-Boot 是 USB 优先），从 U 盘进系统挂上 `/dev/mmcblk1p1` 把那行删掉。
> SD 卡槽走的是另一个控制器（`&sdio`），这个设备树不动它，所以 SD 卡也能救。

确认是 NAND 版之后，在 `/boot/armbianEnv.txt` 里加一行，然后重启：

```
fdtfile=meson8b-ws1508-nand.dtb
```

这个设备树会**关掉 eMMC 控制器 `&sdhc`**（BOOT_0..BOOT_10 这组焊盘是
NAND 总线和 sdxc_c 总线共用的，两个控制器不可能同时开），并打开 NAND 控制器。
在 NAND 版机器上关掉 eMMC 没有任何损失，它本来就找不到卡。
SD 卡槽在 `&sdio` 上，不受影响。

开起来之后跑 `ws1508-nand-probe`：它只读，会打印几何参数、时钟频率、
以及 `/proc/interrupts` 里有没有这个控制器（**预期是没有**，设备树里
根本没写 `interrupts`，见下面「已知没验证过的地方」）。
它也可以 dump 一段出来：长度按芯片自报的擦除块大小算，至少盖满
驱动写保护的那 16MiB，块数太少时兜底 100 个块。
如果压根没有 `/dev/mtd0`，那也是一种结果，见下面「已知没验证过的地方」。

默认是**只读**的。要写必须显式加 `meson_nand.allow_write=1`，
而且即便加了，驱动仍然会挡掉落在厂商引导区里的擦写请求。
边界取两个值里大的那个：按芯片自己上报的页/块大小算出来的
「前 1024 页 + 64 个块」，和一个写死的 **16MiB 下限**
（`MESON8_VENDOR_MIN_BYTES`，见 `ws1508-0102-*.patch`）。
这道保护本身**没有在实机上验证过**。

> ⚠️ 镜像里装了 `mtd-utils`（`ws1508-nand-probe` 要用它的 `nanddump`）。
> Debian / Ubuntu 是一个合并的包，所以 `flash_erase`、`nandwrite`、
> `nandtest`、`ubiformat` 也一并装进来了 —— 内核没开 `MTD_UBI` 挡不住
> `ubiformat`，它是直接对 `/dev/mtdN` 发 `MEMERASE` / `MEMWRITE`。
> **别把这些工具指向 `/dev/mtd0`。** 拦着它们的只有驱动里那两道：
> 不加 `meson_nand.allow_write=1` 时整个 MTD 是只读的，
> 以及厂商引导区那道无论如何都不放行的地址闸。
> 两道都没在实机上验证过。要读就只用 `nanddump`。

### 开之前

1. 确认 Amlogic USB Burning Tool 那条路是通的（见 `flashing.md`）。
   它是唯一的救砖通道。
2. 想清楚 `nkey` / `nsec` 这件事。厂商保留区里有一份一机一份的
   `nkey` / `nsec`，烧录包里没有、工具也生成不出来 —— 覆盖掉就是永久丢失。

关于第 2 条，有一件事必须说清楚，因为本文档早先版本把它写反了：

> **`ws1508-nand-probe` dump 出来的东西不是备份，是诊断样本。**
> 它的用途是和厂商 U-Boot 读出来的同一段做对照，判断驱动读得对不对。
> 三条理由：
>
> - ECC 强度和加扰器设置**还没被证实**和厂商一致（设备树里 ECC 是故意
>   没写死的），所以 dump 出来的内容本身就可能是错的；
> - `nanddump` 不加 `--omitoob` / `--noecc` 时**不含 OOB**，
>   而这块区域的元数据就在 OOB 里；
> - 本项目**没有任何**能把这块区域写回去的东西：驱动会挡掉落在
>   厂商引导区里的擦写请求，加 `meson_nand.allow_write=1` 也不放行。
>
> 换句话说：拿着这个 dump 不等于 `nkey` / `nsec` 安全了。
> 如果你要的是真能写回去的备份，得用厂商 U-Boot 的
> `amlnf` / `store` 命令去读（需要串口），
> 而且**怎么写回去、写回去管不管用，本项目没有验证过**。

关于内存踩踏：2019 年那次移植是靠 `CONFIG_SLUB_DEBUG_ON=y` 才发现 DMA
越界的，不开的话内存被踩了也不报，要等到某个不相干的 `kfree()` 炸掉才知道。
**但发布镜像的内核没有开这个选项**。两条现实的路：

- 自己本地编译，带上 `WS1508_NAND_SLUB_DEBUG=yes`：

  ```bash
  sudo -E WS1508_NAND_SLUB_DEBUG=yes bash scripts/build-armbian.sh build
  ```

  `userpatches/extensions/ws1508-nand.sh` 认这个变量，会顺手打开
  `SLUB_DEBUG` 和 `SLUB_DEBUG_ON`。注意它是**编译主机上的环境变量**，
  走的不是 `WS1508_ROOT_PASSWORD` 那些经 `overlay/ws1508-build.conf`
  传进 chroot 的通道 —— 所以得让它一路传到 `compile.sh`（上面的 `sudo -E` 就是干这个的）。
  **不要自己去改那个函数体**：
  扩展同时把这两个符号塞进了 `kernel_config_modifying_hashes`，
  Armbian 靠它算内核产物的版本哈希 —— 手改函数体绕过这一步，
  debug 内核就可能直接复用普通内核缓存好的 `.deb`，白编一遍。
  这条路本项目没有实际跑过。
- 用发布镜像：那就把判据换掉 —— 开了这个设备树之后，
  内核**任何**莫名其妙的 oops（哪怕调用栈里和 NAND 毫无关系）
  都先按 DMA 越界处理并反馈，别当成不相干的问题排查。

### 闪存到底是哪颗，未知

NAND 版上那颗芯片印的是迅雷自己的料号（例如 `WS1508CRA10L`），
查不到规格。想知道真实型号，在 U-Boot 命令行里跑：

```
amlnf chipinfo
```

本项目的 U-Boot 保留了 `amlnf` 命令（`drivers/amlnf/dev/cmd_amlnf.c`）。
**这一步需要串口**——它是全文里少数几个真的绕不过串口的场合之一。
不想接串口的话，也可以直接看驱动 attach 时打印的那行，信息基本够用，
只是拿不到厂商料号。

几何参数一出来，有三个判断可以立刻做——驱动在 attach 时会打印一行
`page ... oob ... erase ... ecc ... bch ... clk ...`，照着看：

| 看到什么 | 结论 |
|---|---|
| `page` > 4096 | 厂商是用 `AML_NAND_NEW_OOB` 模式写的，主线驱动复现不了这种排布 |
| `page` + `oob` > 16383 | `meson_nand_attach_chip()` 直接拒绝，raw 模式一次传不完一页 |
| `oob` 大小 | 决定能选多强的 ECC：厂商的规则是 `oobsize / 步数 >= ecc_bytes + 2` |

设备树里 ECC 是**故意没写死**的，等实机读出几何参数之后再填
`nand-ecc-step-size` 和 `nand-ecc-strength`。

### 已知没验证过的地方

这一节是整个 NAND 部分里最重要的一节。**本项目没有 WS1508 实机**，
下面每一条都没有在真芯片上跑过。

- 主线 meson-nand **从来没有**在 meson8b 芯片上跑过。2019 年唯一一次尝试
  是在 Meson8m2 上，而且没进主线。
- **可能根本没有 `/dev/mtd0`。** `nand_scan()` 有可能枚举不出这颗芯片
  （时钟、引脚复用、R/B 等待、DMA 任何一环不对都会），
  那样开了设备树也什么都不会出现。这不是「回归」，是还没验证过的东西没跑通。
- **就算出来了，读到的内容也可能是错的。** 厂商写过的页用硬件 ECC 读回来
  纠不动，是 ECC 强度 / 加扰器设置还没对上的**预期结果**，
  不能直接当成「闪存坏了」。设备树里 ECC 故意没写死，就是等实机数据。
- **中断号是个未知数，所以设备树里干脆没写。** `ws1508-0104` 给
  `meson8b.dtsi` 加的那个 nfc 节点**没有 `interrupts` 属性**，
  于是 `platform_get_irq_optional()` 返回 `-ENXIO`，`use_soft_waitrdy`
  保持为真，驱动用软件轮询等 ready —— 厂商自己的 m8 驱动也是无条件走这条路的，
  这是目前唯一有依据的行为。
  跟着来的一条：在本项目发的 dtb 上加 `meson_nand.use_irq_rb=1`
  **什么都不会发生**，没有中断号可用，那个参数只在设备树里真有
  `interrupts` 时才起作用。想试中断，得先在自己的 `.dts` 里把属性加上，
  再带这个参数启动，然后看 `/proc/interrupts` 里的计数涨不涨。
- **info DMA 缓冲区到底该多大，没有官方说法。** 已知的只有一件事：
  Amlogic 自己的 m8 驱动给这个缓冲区留了余量 ——
  `buf_size = (pagesize / ecc_unit) * PER_INFO_BYTE; buf_size += 16;`
  （`work/uboot-nand/drivers/amlnf/phy/chip.c:233-234`）。
  厂商在自己的硅片上给自己的分配打了 16 字节的补丁，这正是怀疑主线那份
  「按 `ecc.steps` 精确分配」会被控制器写越界的理由。
  `ws1508-0100` 就照抄这个尺寸：按最小 ECC 单元（512 字节）算出的最大扇区数
  乘 `PER_INFO_BYTE`，再加厂商那 16 字节。2K 页 / 1K ECC 步长的话是
  `4*8+16 = 48` 字节，不是一整页。（「给它一整页」是本文档早先版本的说法，
  那个做法已经不在补丁里了。）
  另有一串**转述的二手信息**（「2019 年在 Meson8m2 上移植时报给 Amlogic、
  其 NFC 作者转给了内部 VLSI 团队、一直没有回音，256 字节够用、
  512 字节看不到更多」）：本项目没有复现过，也没有找到可引用的邮件列表存档，
  而且它和 Amlogic 自己的代码互相矛盾，所以**故意没有**写进分配里。
  真在 M8 硅片上撞到 slab 破坏，这里是第一个该看的地方。
- 厂商引导区写保护的边界按芯片**自报**的页/块大小算（前 1024 页 + 64 个块），
  几何认小了它就会跟着缩水 —— 所以 `ws1508-0102` 给它加了
  `MESON8_VENDOR_MIN_BYTES = 16MiB` 的下限，取两者的较大值，
  再怎么认错也不会缩到 16MiB 以下。这一条现在**是有对策的**，
  不再是敞着的风险；剩下的未知是这个下限够不够 —— 它只保证盖住
  4×256 个引导页，盖不盖得住随坏块上浮的厂商保留区尾巴，还要实机数据。

---

## 串口（大多数情况下你不需要它）

先说结论：**正常刷机、验证、日常使用都不用接串口。**
只有"机器完全不响应，且想知道卡在哪一步"时才需要。

### 不用串口怎么诊断

| 你想知道的 | 不用串口的办法 |
|---|---|
| 系统起来了吗 | 蓝灯在**心跳式闪烁** = 内核活着；红灯常亮 = 通电 |
| 拿到 IP 了吗 | 路由器 DHCP 列表里找 `ws1508`，或 `ping ws1508.local` |
| 是 NAND 版还是 eMMC 版 | SSH 进去跑 `ws1508-info` |
| **U-Boot 探测到内置闪存了吗** | 同上。U-Boot 会把探测结果通过内核命令行 `ws1508.store=` 传进系统，`ws1508-info` 直接解码；也可以 `cat /proc/cmdline` 自己看：`1`=NAND，`2`=eMMC，`3`=没探测到 |
| 从哪个介质启动的 | `ws1508-info` 会打印当前根设备 |

也就是说：**只要机器能拿到 IP，你就不需要串口。**
真正绕不过串口的只有两种情况：刷完完全不亮、也不上网（那时候串口是唯一
能看到 U-Boot 说了什么的手段），以及想用 `amlnf chipinfo` 问 U-Boot
内置闪存到底是哪一颗（见上文「裸 NAND」）。

### 焊盘位置

⚠️ **以下信息来自社区资料，本项目没有实机核实过，动手前请自己确认。**

- 拆机：用吹风机吹软正面/背面的贴纸，取下薄的上壳，露出 4 颗螺丝；
- TTL 焊盘是 **4 个圆形过孔**，在 **PCB 背面**；
- 顺序（**从靠近 USB 口的那一端往外数**）：**RX、TX、GND、VCC**；
- 主板 **V1.2** 有丝印标注，**V1.1** 没有丝印但顺序相同。

### 接之前先用万用表确认（强烈建议）

不要照着上面的顺序盲接——认错脚可能把 USB-TTL 或主板烧了。用万用表通断档：

1. **先找 GND**：黑表笔接电源座外壳（或网口金属屏蔽壳），红表笔逐个点 4 个焊盘，
   **响的那个是 GND**。
2. **再找 VCC**：不通电时对 GND 测电阻，VCC 对地通常有几百欧到几千欧；
   通电后对 GND 应该是 **3.3V**。
3. 剩下两个就是 TX / RX。接反了不会烧，只是没输出——**对调再试即可**。

接线：**只接 3 根**（GND↔GND、设备 TX↔适配器 RX、设备 RX↔适配器 TX），
**VCC 那根绝对不要接**（设备自己有 12V 供电，接上去可能反灌烧毁）。

参数：**115200 8N1，3.3V 电平**。内核里是 `ttyAML0`。

镜像默认 `console="both"`，Armbian 的启动脚本把串口放最后，
所以串口就是主控制台（systemd 用最后一个）。这机器没有 HDMI，
`tty1` 那一路没意义，想干净点可以在 `/boot/armbianEnv.txt` 里改成 `console="serial"`。

> 串口是有密码保护的：本镜像删掉了 Armbian 构建时装的 `agetty --autologin root`
> 覆盖文件，所以接串口也需要输入 root 密码。

---

## 引脚 / 外设速查

| 外设 | 位置 |
|---|---|
| 串口 | `uart_AO`，`ttyAML0`，115200 |
| 网口 MAC | `ethmac`，RMII，`eth_rmii_pins` |
| 网口 PHY 复位 | GPIOH_4，低有效 |
| eMMC | `sdhc`（`meson-mx-sdhc`），BOOT bank 8 线，别名 `mmc1` → `/dev/mmcblk1` |
| SD 卡槽 | `sdio`（`meson-mx-sdio`），别名 `mmc0` —— **节点从玩客云继承，实际机器一般没有卡槽**，留着无害 |
| USB | `usb0` @ 0xC9040000，OTG |
| CPU 调压 | PWM_D 上的 `pwm-regulator`，860mV~1140mV |
| 红灯 | GPIOAO_2，触发器 `default-on`（电源指示） |
| 绿灯 | GPIOAO_3，触发器 `mmc1`（**只反映内置 eMMC 读写**；NAND 版或 U 盘启动时不亮） |
| 蓝灯 | GPIOAO_4，触发器 `heartbeat`（内核活着就闪，没串口时很有用） |
| 按键 | GPIOAO_5，中断号 5，上报 `KEY_RESTART` |

---

## 主线内核支持情况（meson8b / 6.12）

| 功能 | 状态 |
|---|---|
| CPU + 调频 | ✅ `pwm-regulator` + cpufreq |
| 网口 | ✅ `dwmac-meson`，RMII 100M |
| USB | ✅ `dwc2`，含 USB 存储 |
| SD / eMMC | ✅ `meson-mx-sdio` / `meson-mx-sdhc` |
| 裸 NAND | ⚠️ **实验性且未在实机验证**，本项目自带补丁把 meson8/meson8b 加进 `meson_nand.c`；默认关闭、默认只读。本项目**没有实现**从它启动的路径（引导端能读裸 NAND，缺的是启动脚本和根文件系统方案）。见上文「裸 NAND：能做什么、不能做什么」 |
| HDMI | — 内核有 `drm/meson`，但**这块板子没有视频输出**，用不上 |
| 温度传感 | ⚠️ meson8b 支持有限 |
| GPU (Mali-450) | ⚠️ lima 驱动，对这机器没什么意义 |
