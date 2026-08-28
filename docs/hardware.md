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

### 方法三：看 U-Boot 串口输出

接上串口，通电后本项目的 U-Boot 会打印：

```
try nand boot        ← 在探测 NAND
try emmc boot        ← 在探测 eMMC
```

哪个成功就是哪种。

---

## 串口

主板上有 4 个焊盘（GND / TX / RX / VCC）。用 USB-TTL 转换器，
**3.3V 电平**，波特率 **115200 8N1**。VCC 那根**不要接**，
设备自己有 12V 供电，只接 GND / TX / RX 三根。

内核里串口是 `ttyAML0`。镜像默认 `console="both"`，由于 Armbian 的启动脚本
把串口放在最后，串口就是主控制台（systemd 用最后一个）。这机器没有 HDMI，
所以 `tty1` 那一路实际上没有意义，想干净点可以在 `/boot/armbianEnv.txt` 里
改成 `console="serial"`。

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
| 绿灯 | GPIOAO_3，触发器 `disk-activity` |
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
