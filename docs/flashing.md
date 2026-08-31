# WS1508 刷机指南

> 先读一句：**刷机之前请确认你的机器是 NAND 版还是 eMMC 版**，
> 两种机器能做到的事情不一样。分辨方法见 [`hardware.md`](hardware.md)。
>
> 不想拆机的话，烧录工具本身就能分辨：**不勾任何擦除**直接刷
> `ws1508-uboot.burn.img`，刷成功就是 eMMC 版；卡在初始化存储那一步失败，
> 就是 NAND 版 —— 那一步失败时一个分区都还没写，勾上「擦除 flash」重刷即可
> （**先看完下面 NAND 版那一节的 🔴 警告再决定**，擦除是不可逆的）。
>
> 还有一句：**刷了新的 U-Boot，原厂系统基本就回不去了。**
> eMMC 版还能在刷之前把内置存储整个 `dd` 出来，NAND 版没有这条路
> （本项目没有可用的原厂备份手段，见文末「备份 / 恢复原厂」）。
> 需要原厂功能的话，别刷。

---

## 你需要准备

- 一根 **双公头 USB 线**（两端都是 USB-A 公头），用来把设备接到电脑
- Windows 电脑一台（**Amlogic USB Burning Tool 只有 Windows 版**）
- **Amlogic USB Burning Tool** v2.1.7 或 v2.2.0
  （晶晨烧录工具，网上和各 Amlogic 盒子社区都能找到）
- **不需要串口线。** 刷机、验证、日常使用都不需要它，出了问题也有不拆机的排查办法
  （见文末「刷完不开机怎么查」）。只有在你想看引导过程的每一行输出时才用得上，
  焊盘位置和接法见 [`hardware.md`](hardware.md)

---

## 一、eMMC 版：直刷内置存储

这是最理想的情况 —— 系统完整跑在机器里，U 盘可以拔掉。

### 1. 下载

从 [Releases](../../releases) 下载 **`Armbian_*_ws1508_*.burn.img`**（不要下 `.img.xz`，
那个是给 U 盘用的）。

### 2. 进入刷机模式

1. 设备**断电**（拔掉 12V）；
2. 用双公头 USB 线，把设备的 USB 口接到电脑；
3. **按住机器上的 RESET 键不放**；
4. 插上 12V 电源；
5. 等 2~3 秒后松开 RESET。

USB Burning Tool 里应该出现「连接成功」。

> 如果按键法不认，也可以短接主板上闪存的引脚（网上称「短接刷机」）。
> 但**先试按键法**，它不需要拆机。

### 3. 刷入

1. 打开 USB Burning Tool；
2. 「文件」→「导入烧录包」，选刚下载的 `.burn.img`；
3. 勾选 **擦除 flash** 和 **擦除 bootloader**；
4. 点「开始」；
5. 进度走到 100% 显示成功后，点「停止」，拔电源、拔 USB 线。

### 4. 开机

插网线，通电。第一次开机会自动扩展根分区并生成 SSH 主机密钥，
**等 1~2 分钟**（这机器只有 4 核 A5，慢是正常的），然后：

```bash
ssh root@<设备IP>     # 密码 1234
```

IP 从路由器的 DHCP 客户端列表里找，主机名是 `ws1508`。
也可以试试 `ssh root@ws1508.local`。

---

## 二、NAND 版：刷引导 + U 盘跑系统

这是 NAND 版的**推荐做法**，也是唯一在逻辑上没有未验证前提的做法：
把引导刷进 NAND，系统跑在 U 盘上。想把系统也装进 NAND，
见下面「二（进阶）」——那条路已经实现，但一次都没在实机上跑过。

> 为什么，说准一点：引导程序里**没有文件系统层**
> （`CONFIG_NEXT_NAND` 让 Amlogic 的 Makefile 把 `libmtd.o` / `libnand.o`
> 从构建里踢掉），所以 `fatload` 没法从 NAND 上的某个文件系统里读出 uImage。
> 引导程序**能读 NAND**（`store read` / `amlnf read`，厂商 3.10 固件就是
> 这么启动的），**但走的是厂商 NFTL，不是裸偏移** —— 那一层只有编译好的
> 二进制，Linux 复现不了它的逻辑→物理映射。
> 所以**不能**让引导程序和 Linux 共用同一块区域。
>
> 绕开的办法是按物理位置切开芯片，这条路本项目**已经实现了**，
> 见下面「装到内置 NAND（实验性）」。**一次都没在实机上跑过。**

### 1. 刷 U-Boot

下载 **`ws1508-uboot.burn.img`**，按上面「进入刷机模式」的步骤操作，
在 USB Burning Tool 里导入这个文件并刷入。

这个包只有约 1.4MB，只写引导相关的分区。

> 🔴 **NAND 版第一次刷本项目的引导，必须勾上「擦除 flash」（Erase flash）。**
>
> 本项目改了分区表的 `mask_flags`（`resource` 和 `boot` 从 `nfdata` 挪到
> `nfcode`）。`confirm_dev_para()` 比的是排好序的分区表，所以这种改动和改名
> 一样会被抓到。名字和大小都没动，**不是**可以跳过的理由。
>
> 不勾擦除的话，**烧录过程本身就会失败**，轮不到下次启动：烧录工具发
> `disk_initial 0` → `optimus_storage_init()` 翻成 `store_init(1)`
> （`optimus_download.c:750`）→ `do_store` 跳过擦除那一遍、直接跑
> `amlnf init 1`（`store_interface.c:684-693`）→
> `amlnand_configs_confirm()` 比对失败。而容错只在 flag 2、3 时才给
> （`chipenv.c:2859`），flag 1 不在里面 —— 于是 `disk_initial` 返回失败，
> 一个分区都还没写就结束了。
>
> 勾了擦除走的是 `store_init(3)`：先跑一遍 `amlnf init 3` 把配置块擦掉，
> 再跑 `amlnf init 1`，这次芯片上没有旧表（`arg_valid == 0`），
> 直接把新表存下来，烧录继续。
>
> 代价：擦除会一并抹掉一机一份的 `nkey` / `nsec`，**永久丢失**，
> 本项目没有任何办法备份或恢复。`chipenv_init_erase_protect()` 里那道
> 「保护 key 区」的判断在这个 U-Boot 里是空的，原因见下面「二（进阶）」
> 那一节。跑 Armbian 用不到这些 key，但这不可逆 ——
> 想留着回原厂固件可能性的人到此为止。详见「备份 / 恢复原厂」。
>
> eMMC 版不受这条影响（那边的表由 `mmc_device_init()` 直接重写一次记录，
> 不会失败），但 eMMC 版走的是「一、」那条路，本来也不看这里。

### 2. 做启动 U 盘

下载 `Armbian_*_ws1508_*.img.xz`，解压后用
[balenaEtcher](https://etcher.balena.io/)、Rufus 或 `dd` 写进 U 盘：

```bash
xz -d Armbian_*_ws1508_*.img.xz
sudo dd if=Armbian_*_ws1508_*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

（`/dev/sdX` 换成你的 U 盘，**别写错盘**。）

### 3. 开机

把 U 盘插进机器唯一的 USB 口，插网线，通电。

> ⚠️ 这机器**只有一个 USB 口**，被系统盘占掉之后就没有别的口了。
> 想再接硬盘得用 USB Hub —— 注意 Hub 要带独立供电，
> 这个口带不动 2.5 寸机械盘。

---

## 二（进阶）、NAND 版：把系统装进内置 NAND

> ⚠️ **一次都没在实机上跑过。** 底下那个 meson8b 裸 NAND 驱动
> 从来没在 S805 芯片上运行过，这一节的每一步都建立在读代码而不是
> 实测之上。做之前先把「救砖」那一节读完 —— 退路是 U 盘，
> 而且 U-Boot 的启动顺序（USB → SD → eMMC → NAND）保证了
> 插上 U 盘就一定能回来。

### 先理解这件事：芯片被切成两半

厂商的 NFTL 只有编译好的二进制，Linux 复现不了它的逻辑→物理映射，
所以两边不能共用同一块区域。物理上切开：

| 物理范围 | 归谁 | 谁能写 |
|---|---|---|
| 0 – 384MiB | 厂商 `amlnf`（引导页、元数据、`nkey`/`nsec`、引导要读的 NFTL 分区） | 只有 USB 烧录工具 / U-Boot |
| 384MiB – 末尾 | Linux（UBI + UBIFS 根） | 只有 Linux |

**内核那一半 Linux 写不了，根文件系统那一半 U-Boot 读不了。**
所以装机必然是两步，用两个不同的工具。

### 1. 刷 `ws1508-nand.burn.img`（引导 + 内核）

这个包 = 引导程序 + 一个 Android boot.img（里面是 uImage、裸 initrd、
NAND 版 dtb），后者写进厂商 `boot` 分区。

> 🔴 **第一次刷必须勾上「擦除 flash」（Erase flash）。**
>
> 本项目改了分区表的 `mask_flags`（把 `resource` 和 `boot` 挪进
> `nfcode`，否则 NFTL 那个 blob 在正常启动时根本不会给它们建设备，
> `store read` / `imgread` 一个都用不了）。而
> `amlnand_configs_confirm()`（`chipenv.c:1995`）会拿编译进去的表和
> 芯片上存的那份逐字段比对，**对不上就直接失败**，只有烧录工具告诉它
> 「这次要擦」时才放行。
>
> 代价是：**擦除会一并抹掉一机一份的 `nkey` / `nsec`，永久丢失。**
> 本项目没有任何办法备份或恢复它们（而且这个 U-Boot 里那道
> 「保护 key 区不被擦」的判断是空的 —— 它依赖的字段只在
> `CONFIG_SECURITYKEY` 下才会被填，而这个宏没开）。
> 对跑 Armbian 的机器来说这些 key 没有用处，但这是不可逆的，
> 想留着原厂固件可能性的人到此为止。

### 2. 做启动 U 盘，从 U 盘启动

和上面「二、」的第 2、3 步一样。

### 3. 打开 NAND 设备树

进系统后编辑 `/boot/armbianEnv.txt`，加两行：

```
fdtfile=meson8b-ws1508-nand.dtb
extraargs=meson_nand.allow_write=1
```

重启，然后确认：

```bash
cat /proc/mtd          # 应该看到 mtd0 "vendor" 和 mtd1 "ubi"
ws1508-nand-probe      # 打印几何、ECC、只读标志
ws1508-nand-probe 1    # 同上，看 UBI 那个分区
```

**这一步就是实机验证点。** `ws1508-nand-probe` 的输出里有三件事决定
后面能不能做：料是不是 SLC（UBI 不收 MLC）、页大小是不是 ≤4096、
以及厂商写过的页读回来 ECC 有没有过。任何一条不对，就停在这里。

### 4. 装根文件系统

```bash
sudo ws1508-install-to-nand
```

它会检查 `store=1`、`allow_write=1`、两个分区标签都在，然后
`ubiformat` → `ubimkvol` → 挂上 → `rsync` 整个系统过去，
并且写好 `/etc/fstab` 和 initramfs 模块列表。
`/dev/mtd0`（前 384MiB）在设备树里就是只读的，不会被碰。

### 5. 拔掉 U 盘，开机

```
Try to boot from USB...Fail
Try to boot from SD...Fail
Try to boot from eMMC...Fail
Try to boot from NAND...
## ANDROID Format IMAGE
```

看到最后两行就说明 `imgread` 读到了。**不拔 U 盘就还是从 U 盘启动** ——
这既是注意事项，也是退路。

### 注意：以后再进烧录工具，都可能动到根文件系统

两件事，程度不同：

- **勾了擦除 = 一定没了。** `store erase data` 在 NAND 上是连着擦
  `data`、`code`、`cache` 三个设备的（`common/store_interface.c:220-241`），
  烧录工具的擦除档位走的就是这条路。UBI 根文件系统和内核都会被抹掉，
  第 4 步要重做。
- **不勾擦除 = 说不准。** 正常启动时 U-Boot 用 flag=0 调
  `amlnf_logic_init()`，那条路会跳过 `nfdata`，所以 Linux 那一半从不被碰
  —— 这正是这个设计成立的前提。但**烧录会话用的是非 0 的 flag**，
  那时 `nfdata` 会被挂上 NFTL。挂载本身会不会写，在 blob 里面，看不到。

所以：装完之后尽量别再进烧录工具。真要更新内核，见下面。

### 内核更新怎么办

`apt upgrade` 升级内核**不会**更新 NAND 里的那一份：它在 NFTL 后面，
Linux 写不了。要更新就重新生成 `ws1508-nand.burn.img` 再刷一次
（这次不用勾擦除，分区表没变）。或者在 U-Boot 命令行里用
`usb_update boot ws1508-nand-boot.andr` 从 U 盘写。

这是这条路的真实代价，权衡之后再决定要不要走。

---

## 一（备选）、eMMC 版：先 U 盘启动，再装进 eMMC

如果直刷 `.burn.img` 之后机器起不来（见
[`development.md`](development.md) 里「eMMC 直刷：一个没能静态确认的环节」），
或者你就是想稳妥一点，可以走这条路。它**不依赖烧录工具怎么摆分区**，
是自己在机器上写一个标准 MBR，所以更可控。

1. 按上面「二、NAND 版」的步骤刷 `ws1508-uboot.burn.img`（只刷引导）；
2. 做一张启动 U 盘，插上开机，SSH 进去；
3. 跑一条命令：

```bash
sudo ws1508-install-to-emmc
```

它会：确认你确实是 eMMC 版 → 在 eMMC 上写 MBR（p1 从 16MiB 起 256MiB FAT32，
p2 接在后面 ext4，**前 16MiB 的 u-boot 区域不动**）→ 建文件系统 →
把当前系统整个 rsync 过去 → 改好新的 `armbianEnv.txt` 和 `fstab`
（顺便给新根分区换一个 UUID，避免和 U 盘撞车）。

4. `poweroff`，拔掉 U 盘，通电。

失败也不要紧：引导没被动过，把 U 盘插回去就回到原样。

---

## 三、只想试试，不动内置存储

任何版本的机器都可以：先只做一张启动 U 盘，什么都不刷。

但注意：**原厂 U-Boot 不会去 U 盘上找系统**，所以这条路要求你至少
已经刷过一次本项目的 U-Boot。也就是说：

- 已经刷过本项目 U-Boot 的机器 → 直接插 U 盘就能启动；
- 完全原厂的机器 → 至少得先刷 `ws1508-uboot.burn.img`。

---

## 启动顺序

本项目的 U-Boot 按这个顺序找系统：

```
USB → SD 卡 → eMMC → NAND
```

意思是：

- eMMC 里装了系统、USB 上没插启动盘 → 从 eMMC 启动（正常使用）；
- 插上一个做好的启动 U 盘 → 优先从 U 盘启动
  （**这是救砖通道**：内置系统搞坏了，插个 U 盘就能进去修，不用拆机）；
- 插的是普通数据 U 盘（找不到 `boot.scr`）→ 自动跳过，继续往下试；
- 前面三档都没有，且 `${store}` 报的是裸 NAND → 从内置 NAND 启动。
  这一档**不经过 `boot.scr`**（`boot.scr` 自己就得从文件系统里读，
  NAND 上没有），整条逻辑在 U-Boot 环境变量 `boot_nand` 里。
  它排在最后，所以插着 U 盘永远优先 U 盘 —— NAND 装挂了也回得来。

> SD 卡那一档基本用不上：**WS1508 相比一代砍掉了 TF 卡槽**，绝大多数机器
> 根本没有卡槽（设备树里的 SD 节点是从玩客云继承来的）。留着这一档只是
> 多花一瞬间，不影响使用。

### ⚠️ 救砖 U 盘的一个坑：UUID 撞车

Armbian 用 `root=UUID=...` 指定根文件系统。如果你的 **eMMC 系统和 U 盘系统
是同一个镜像刷出来的**，两边根分区的 UUID 完全一样 —— 这时候内核到底挂哪个
是不确定的，可能你从 U 盘启动，结果挂的还是 eMMC 里那个坏系统，救砖就失效了。

做救砖 U 盘时，写完之后改一下它的 UUID：

```bash
sudo tune2fs -U random /dev/sdX2      # sdX 换成你的 U 盘
```

然后把 U 盘 `/boot/armbianEnv.txt` 里的 `rootdev=UUID=...` 改成新 UUID
（`sudo blkid /dev/sdX2` 可以查）。或者干脆用另一个 release 的镜像做救砖盘。

---

## 再次刷机不用再按 RESET

本项目的 U-Boot 每次开机都会先留 1 秒给烧录工具：

```
Checking USBBurn...
```

所以之后要重刷，**只要在通电前把 USB 线接上电脑**，
USB Burning Tool 就能认到，不用再按 RESET、更不用拆机短接。

---

## 救砖

刷坏了基本救得回来 —— Amlogic 的 ROM 在片内，
只要 SoC 还活着，USB 烧录模式就一定在。

> ⚠️ 但烧录工具救的是**固件**，不是**这台机器独有的数据**。
> 厂商保留区里有一份一机一份的 `nkey` / `nsec`，烧录包里没有，
> 工具也生成不出来 —— 覆盖掉就是永久丢失。
> 本项目**没有**任何能把这块区域写回去的东西，所以这一条不是
> 「先备份就没事了」，而是「这块区域覆盖掉就没了」。
> 打算动内置存储（尤其是打开实验性的 NAND 设备树、
> 或者加 `meson_nand.allow_write=1`）之前，把这一点先想清楚。
> 详见下面「备份 / 恢复原厂」。

按优先级试：

1. **按住 RESET 上电**，用 USB Burning Tool 重刷。绝大多数情况这一步就够了；
2. 不按 RESET，直接把双公头 USB 线接上电脑，然后通电。本项目的 U-Boot 每次开机
   都会先留 1 秒给烧录工具，所以只要 U-Boot 还活着，工具就能认到；
3. 如果按键法完全没反应：拆机**短接闪存的数据/时钟引脚**再上电。
   原理是让 SoC 从闪存读不到有效引导，从而回落到片内 ROM 的 USB 烧录模式。

   > 本项目**没有**在 WS1508 实机上验证过具体短接点，所以这里不给引脚编号 ——
   > 照着错误的引脚捅很容易把板子弄坏。请去搜「赚钱宝二代 短接 刷机」
   > 找带清晰主板照片、明确标出短接点的教程，对照自己的板子确认后再动手。
   > 短接的是闪存芯片的引脚，不是随便哪两个点。

---

## 备份 / 恢复原厂

**刷之前做**，刷完就来不及了。

原厂固件没有公开的官方下载，所以唯一可靠的备份方式是在刷之前
自己把内置存储整个读出来。最简单的办法是先从 U 盘启动一个系统
（这本身就需要先刷 U-Boot，属于先有鸡还是先有蛋），
所以更现实的做法是：**接受这台机器刷完就回不去原厂**。

如果你确实需要原厂功能，别刷。

eMMC 版机器如果已经能从 U 盘启动，可以这样备份内置存储：

```bash
dd if=/dev/mmcblk1 of=/mnt/backup/ws1508-emmc.img bs=4M status=progress
```

### NAND 版：能做的只有诊断样本，**没有**可用的原厂备份路径

NAND 版没有块设备。实验性的 NAND 设备树**如果**能认出这颗芯片，
会给出一个 `/dev/mtd0`（在 `/boot/armbianEnv.txt` 里加
`fdtfile=meson8b-ws1508-nand.dtb` 重启）——「如果」是认真的，这个驱动
从来没在 meson8b 芯片上跑过，`nand_scan()` 枚举不出来是预期结果之一。
真出来了，`ws1508-nand-probe` 能从它 dump 一段出来：

```bash
sudo ws1508-nand-probe          # 只读；会问你要不要 dump
```

它的长度不是拍脑袋的：按芯片自报的擦除块大小，算出至少盖满驱动写保护那
16MiB 需要多少个块（块太大时兜底 100 个块），这样才不会停在厂商保留区中间。
手动做也一样：

```bash
sudo nanddump --bb=dumpbad \
              --length=$((16 * 1024 * 1024)) \
              --file=/mnt/backup/ws1508-nand-head.bin /dev/mtd0
```

**但这个 dump 不是备份，是诊断样本。** 它的用途是拿去和厂商 U-Boot 读出来的
同一段做对照，判断驱动读得对不对。把它当成保险是错的，理由有三条：

- ECC 强度和加扰器设置**还没被证实**和厂商一致（设备树里 ECC 是故意没写死的），
  所以 dump 出来的内容本身就可能是错的；
- `nanddump` 不加 `--omitoob` / `--noecc` 时**不含 OOB**，
  而厂商保留区的元数据就在 OOB 里；
- 本项目**没有任何**能把这块区域写回去的路径 ——
  驱动会挡掉落在厂商引导区里的擦写请求，加 `meson_nand.allow_write=1` 也不放行
  （这道保护和这部分的其它一切一样，没有在实机上验证过）。

所以 `nkey` / `nsec` 的正确说法是：**本项目救不回来，也没有提供备份手段。**
真要备份它，只能在厂商 U-Boot 的命令行上用 `amlnf` / `store` 命令去读
（需要串口），而且**怎么写回去、写回去管不管用，本项目没有验证过**。

> 用 `--bb=dumpbad` 不要用 `skipbad`：出厂坏块本身就是要看的信息，
> 跳过它会把后面所有偏移都错开。
>
> 关于长度：驱动的写保护边界取两个值里大的那个 —— 按芯片自报的几何算出的
> 「前 1024 页 + 64 个块」，和写死的 16MiB 下限
> （`MESON8_VENDOR_MIN_BYTES`）。上面用 16MiB 是取那个下限，
> 芯片几何大的话真实边界会更靠后。厂商保留区是按**好块**计数的，
> 出厂坏块多的机器上它整体往上浮，所以 16MiB 仍然可能读不到它的尾巴 ——
> 想稳一点就照着 `/sys/class/mtd/mtd0/erasesize` 把长度再放大一些。

---

## 常见问题

**USB Burning Tool 认不到设备**
- 换一根双公头 USB 线（很多线是只有电源没有数据的）
- 换电脑的 USB 口，优先用主板后置 USB 2.0 口
- 装一下工具自带的驱动（`WorldCup Device` / `Amlogic USB Burning`）
- 确认是**按住 RESET 再上电**，不是上电后再按

**刷完不开机怎么查**（不用串口）

按这个顺序，每一步都不用拆机：

1. **看蓝灯。** 呼吸式闪烁 = 内核已经在跑，问题只在网络或 SSH，不是启动失败。
   换个网口和网线，或者把机器直连电脑试 `ping ws1508.local`；再等两分钟，
   第一次开机要扩展根分区、重新生成 SSH 主机密钥，这机器慢。
2. **蓝灯不闪、红灯常亮** = 通电正常但系统没起来。插一张做好的启动 U 盘再通电：
   - **能起来**（路由器里能看到 `ws1508` 拿到 IP）→ U-Boot 是好的。SSH 进去跑
     `ws1508-info`：如果它说 `raw NAND`，那内置存储里要么还没装系统
     （这就是刚刷完引导的正常状态），要么装了但没起来 —— 想装进内置 NAND
     见上面「二（进阶）」，那条路没在实机上验证过；如果说 `eMMC`，
     那是内置存储里那份系统坏了，跑 `sudo ws1508-install-to-emmc`
     重装一遍即可。
   - **插 U 盘也起不来** → 问题在 U-Boot。接双公头 USB 线通电，重刷
     `ws1508-uboot.burn.img`（不用按 RESET，见上面「再次刷机不用再按 RESET」）。
3. **红灯都不亮** → 先排除电源和电源线，不是刷机的问题。

进系统之后 `ws1508-info` 会告诉你 U-Boot 探到的是 NAND 还是 eMMC、这次从哪启动的，
这是判断「刷进去了没有」最直接的依据。

**eMMC 版刷完还是从 U 盘启动**
- 正常，启动顺序是 USB 优先。拔掉 U 盘就会从 eMMC 启动

**NAND 版刷了完整 `.burn.img`（eMMC 那个）会怎样**
- 引导能刷进去，但那个包里的 `boot` 是一个 FAT 分区镜像，
  **会盖掉 NAND 里的内核**（正确的内容是 `ws1508-nand.burn.img` 里那个
  Android boot.img）。`rootfs` 那个是 ext4 镜像，经 NFTL 写下去 Linux
  永远读不回来，纯属白写 —— 而且它落在 UBI 根文件系统所在的物理区域。
- 所以 NAND 版**不要**刷 eMMC 的完整包。只装引导用
  `ws1508-uboot.burn.img`；连内核一起装用 `ws1508-nand.burn.img`。

**`reboot` 之后起不来，要拔电重启**
- 这是 S805 这批盒子的老毛病（看门狗 / 电源状态没复位），社区普遍反馈过。
  优先用 `poweroff` 后拔插电源
