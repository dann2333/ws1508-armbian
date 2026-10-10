# 升级：不重刷、不丢数据

从这一版开始，WS1508 和普通 Armbian 板子一样，用 `apt` 就能升级 ——
**内核、设备树、启动脚本、`ws1508-*` 工具全都走 deb 包更新**，
不用重刷，也不动你的数据和配置。

---

## 先说最要紧的：老设备都应该装一个 pin

**之前发布的所有镜像都有一颗定时炸弹，跟你用不用这个更新通道无关。**

Armbian 构建的镜像默认启用 Armbian 官方源（`/etc/apt/sources.list.d/armbian.sources`，
带 `main` 组件），而官方源里有两个**和本项目内核同名**的包：

- `linux-image-current-meson`
- `linux-dtb-current-meson`

官方的版本是给 Odroid-C1、玩客云这些板子编的，**不带 WS1508 的设备树**
（`meson8b-ws1508.dtb`）。WS1508 的启动脚本固定加载这个文件，
它一没，机器就起不来。

现在之所以没出事，纯属版本号碰巧：老镜像里的内核包版本是 `26.11.0-trunk`，
比官方最新的 `26.8.3` 大，apt 就不会去换。**等 Armbian 发布 26.11.1
（按惯例在 11 月）或更高版本之后，老镜像上一次普通的 `apt upgrade`
就会把内核和设备树换成官方的，重启后机器无法启动。**

解决办法是给 apt 装一个 pin，告诉它「这两个包永远不要从 Armbian 官方源装」。
官方源里别的东西（固件、`armbian-config` 等）照常更新，不受影响。
下面的升级步骤会自动装上它；如果你暂时不想升级，至少单独装 pin：

```bash
curl -fLO https://github.com/dann2333/ws1508-armbian/releases/latest/download/ws1508-apt-setup.sh
sudo bash ws1508-apt-setup.sh pin
```

这一版起刷的新镜像已经自带 pin，不用管。

---

## 老设备：一次性开启更新通道

适用于用**之前任何一版**镜像装好、正在运行的机器（U 盘启动的、装进 eMMC 的都一样）。
SSH 登录后：

```bash
curl -fLO https://github.com/dann2333/ws1508-armbian/releases/latest/download/ws1508-apt-setup.sh
sudo bash ws1508-apt-setup.sh
sudo reboot
```

脚本做了这几件事，可以自己核对：

1. 写入 pin：`/etc/apt/preferences.d/ws1508`（见上一节）
2. 写入本项目的 apt 源：`/etc/apt/sources.list.d/ws1508.sources`
3. `apt-get update`
4. 只升级已经装着的 WS1508 板级包（内核、设备树、板级支持包 `armbian-bsp-cli-ws1508-current`），
   升级前会列出「当前版本 → 新版本」并问你一次

升级板级支持包时它还会顺带：

- 把 `/boot/boot.cmd`、`/boot/boot.scr` 换成新版启动脚本
  （旧的备份在 `/usr/share/armbian/boot.cmd-<时间戳>`）。
  **你自己的设置都在 `/boot/armbianEnv.txt` 里，这个文件不会被动。**
- 把 `ws1508-*` 工具换成新版，放在 `/usr/sbin/`，
  并删掉老镜像装在 `/usr/local/sbin/` 里的旧副本（不然旧的会排在 PATH 前面挡住新的）

重启后跑一下 `ws1508-info`，最后的「updates」一节应该显示：

```
linux-image-current-meson        26.11.0-trunk.ws1508.2026xxxxxxxxxx
linux-dtb-current-meson          26.11.0-trunk.ws1508.2026xxxxxxxxxx
armbian-bsp-cli-ws1508-current   26.11.0-trunk.ws1508.2026xxxxxxxxxx
channel: enabled  ('apt update && apt full-upgrade' updates the kernel too)
pin:     present
```

版本号末尾那串数字是构建时间（UTC），也就是对应 Release 的标签。

## 之后：日常升级

```bash
sudo apt update
sudo apt full-upgrade
sudo reboot          # 内核有更新时
```

和任何 Armbian 板子一样。Debian/Ubuntu 的软件来自发行版官方源，
WS1508 的内核和板级包来自本项目每次发布的 Release。

镜像为了省内存关掉了自动更新（`apt-daily*`、`unattended-upgrades`），
所以**升级只在你手动执行时发生**。

---

## 能升级什么，不能升级什么

| 内容 | 通过 apt 更新？ | 说明 |
|---|---|---|
| 内核、内核模块（含 NAND 驱动的修复） | ✅ | `linux-image-current-meson` |
| 设备树 | ✅ | `linux-dtb-current-meson` |
| 启动脚本 `boot.scr` | ✅ | 随板级支持包刷新，`armbianEnv.txt` 不动 |
| `ws1508-info`、`ws1508-install-to-emmc` 等工具 | ✅ | 随板级支持包 |
| Debian / Ubuntu 软件 | ✅ | 发行版官方源，一直都能更新 |
| **U-Boot（引导程序）** | ❌ | 只能用 USB Burning Tool 刷，**这一版不需要刷** |
| 已经装好的系统配置（SSH、内存调优、主机名等） | — | 不动；那些是装机时写进去的，升级不会覆盖 |
| 发行版大版本（如 Debian 12 → 13） | ❌ | 不在这个通道里，建议刷新镜像 |

U-Boot 没法走 apt：它在内置存储的引导区里，Linux 碰不到那块地方
（NAND 版尤其如此，在厂商的 NFTL 后面）。目前的内核和启动脚本对旧版
U-Boot 是兼容的，所以升级不需要动引导。

---

## 出问题了怎么办

**升级后起不来：** U-Boot 的启动顺序是 USB → SD → eMMC → NAND。
插一个写好新镜像的 U 盘开机，就能进系统；然后把内置系统挂上来修，
或者干脆用 `ws1508-install-to-emmc` 重装一遍（eMMC 版）。

**想退回某个旧版本：** 从这一版起，每个 Release 都是一个完整的 apt 仓库
（更早的 Release 里没有，退不到那些版本）。
把 `/etc/apt/sources.list.d/ws1508.sources` 里的
`releases/latest/download/` 换成 `releases/download/<那个版本的标签>/`，
然后：

```bash
sudo apt update
apt list -a linux-image-current-meson        # 看看有哪些版本
sudo apt install --allow-downgrades linux-image-current-meson=<版本> linux-dtb-current-meson=<版本>
```

**不想再收更新：** `sudo ws1508-apt-setup disable` 只删掉源，pin 保留 ——
pin 是防止官方内核被装上的，任何时候都应该留着。

**`apt update` 报 GitHub 下载失败：** 国内访问 GitHub 不稳定时会这样，
重试即可，不影响已经装好的系统。也可以给 apt 配代理
（`/etc/apt/apt.conf.d/` 里写 `Acquire::https::Proxy "http://...";`）。

---

## 这个更新通道是怎么做的（给想核对的人）

- **仓库在哪：** 每次发布 Release 时，CI 把内核、设备树、头文件和板级支持包，
  连同 `Packages` / `Packages.gz` / `Release` 索引，作为 Release 附件一起传上去
  （`scripts/make-apt-repo.sh`）。apt 源指向
  `https://github.com/dann2333/ws1508-armbian/releases/latest/download/`，
  GitHub 会把这个地址下的任何文件名重定向到最新 Release 里的同名文件，
  所以「最新」会自动跟着走，不需要另外的服务器。
- **没有签名：** 源文件里写了 `Trusted: yes`。完整性靠的是到 github.com 的
  HTTPS 加上索引里每个包的 SHA256 —— 和你当初下载镜像时信任的是同一个来源。
- **版本号：** Armbian 默认给所有包打同一个版本号（`26.11.0-trunk`，几个月都不变），
  这样 apt 永远不会认为有更新。本项目在后面追加了构建时间：
  `26.11.0-trunk.ws1508.<UTC 时间>`，保证每次构建都比上一次新，
  也比之前所有镜像里的 `26.11.0-trunk` 新。
- **pin 的内容：** 见 `/etc/apt/preferences.d/ws1508`，或者
  `ws1508-apt-setup print-pin`。它按 Release 文件里的 `Origin: Armbian`
  匹配，所以对 Armbian 的所有镜像站（清华、北外等）同样有效。
