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

> 注意：主线内核没有 meson8b 的 NAND 驱动，所以 NAND 版机器上
> **不会**出现 `/dev/mtd*`，看不到不等于没有闪存。

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
真正需要串口的只有一种情况——刷完完全不亮、也不上网，
那时候串口是唯一能看到 U-Boot 说了什么的手段。

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
| 裸 NAND | ❌ **无驱动**（`meson_nand.c` 只支持 gxl / axg） |
| HDMI | — 内核有 `drm/meson`，但**这块板子没有视频输出**，用不上 |
| 温度传感 | ⚠️ meson8b 支持有限 |
| GPU (Mali-450) | ⚠️ lima 驱动，对这机器没什么意义 |
