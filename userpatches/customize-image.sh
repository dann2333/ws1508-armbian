#!/bin/bash
#
# Image customisation for the Xunlei WS1508 (Amlogic S805, 512MB RAM).
#
# Runs inside the image's chroot. Two jobs:
#   1. Make the image usable headlessly: sshd up on first boot, no
#      interactive first-run wizard standing between the user and a shell.
#   2. Keep the running system inside 512MB of RAM.
#
# Build-time knobs:
#   WS1508_ROOT_PASSWORD        root password to bake in (default: 1234)
#   WS1508_SSH_AUTHORIZED_KEY   an SSH public key to install for root
#   WS1508_ROOT_PASSWORD_LOGIN  "no" to allow key-only root SSH login
#   WS1508_HOSTNAME             hostname (default: ws1508)
#   WS1508_TIMEZONE             tz database name (default: Asia/Shanghai)
#   WS1508_EXTRA_PACKAGES       extra packages to preinstall
#
# scripts/build-armbian.sh writes these to userpatches/overlay/ws1508-build.conf,
# which Armbian bind-mounts at /tmp/overlay inside this chroot. That file is
# the primary channel; plain environment variables are honoured as a
# fallback for anyone running compile.sh by hand. Going through the overlay
# rather than relying on the environment matters because Armbian invokes
# this script via `chroot ... /usr/bin/env bash -c`, and what survives that
# is an implementation detail we should not depend on.

set -euo pipefail

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"
ARCH="${5:-}"

if [ -r /tmp/overlay/ws1508-build.conf ]; then
	# shellcheck disable=SC1091
	. /tmp/overlay/ws1508-build.conf
fi

ROOT_PASSWORD="${WS1508_ROOT_PASSWORD:-1234}"
SSH_KEY="${WS1508_SSH_AUTHORIZED_KEY:-}"
ROOT_PASSWORD_LOGIN="${WS1508_ROOT_PASSWORD_LOGIN:-yes}"
HOSTNAME="${WS1508_HOSTNAME:-ws1508}"
TIMEZONE="${WS1508_TIMEZONE:-Asia/Shanghai}"
EXTRA_PACKAGES="${WS1508_EXTRA_PACKAGES:-}"

# Needed by /usr/local/sbin/ws1508-install-to-emmc. BUILD_MINIMAL images do
# not carry rsync or dosfstools, and discovering that only when the user
# tries to install to eMMC would be a poor joke.
#
# mtd-utils is for ws1508-nand-probe on raw-NAND units, which uses only
# nanddump. Be clear about what else lands with it: Debian/Ubuntu ship one
# combined mtd-utils, so the image also gets flash_erase, nandwrite,
# nandtest and ubiformat/ubiattach. Nothing here calls them, and leaving
# CONFIG_MTD_UBI off does not disarm them (ubiformat erases through
# /dev/mtdN with plain MEMERASE/MEMWRITE ioctls). So on a NAND unit the
# only thing between those tools and the vendor bootloader region is the
# kernel-side guard in ws1508-0102-*.patch plus the read-only default --
# not the absence of tooling. Anyone reading a claim to the contrary
# elsewhere in the tree should trust this line, and check `dpkg -L
# mtd-utils` on a built image.
REQUIRED_PACKAGES="rsync dosfstools e2fsprogs util-linux parted mtd-utils"

say() { printf '\n\033[1;36m[ws1508]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# SSH: reachable on first boot, with no console interaction
# ---------------------------------------------------------------------------
setup_ssh() {
	say "Configuring SSH for headless first boot"

	# Armbian ships a first-login wizard that runs from /etc/profile.d on
	# every login while /root/.not_logged_in_yet exists. It forces a root
	# password change AND a new-user creation before it will let go. That
	# is exactly wrong for a headless box you only ever reach over SSH, so
	# the marker is removed and the same configuration is applied here
	# instead.
	rm -f /root/.not_logged_in_yet

	# Armbian's build installs agetty overrides that log root in with no
	# password on tty1 and on EVERY serial console, so that the first-login
	# wizard can run without credentials:
	#
	#   ExecStart=-/sbin/agetty --noissue --autologin root %I $TERM
	#
	# armbian-firstlogin deletes them when it finishes -- and we just
	# removed the marker that makes it run. Left in place they would mean
	# anyone who clips a USB-TTL adapter onto the WS1508's four serial pads
	# gets a root shell, no password asked, forever. Delete them here, the
	# same files the wizard would have.
	rm -f /etc/systemd/system/getty@tty1.service.d/override.conf
	rm -f /etc/systemd/system/getty@.service.d/override.conf
	rm -f /etc/systemd/system/serial-getty@.service.d/override.conf
	rm -f /etc/systemd/system/serial-getty@ttyGS0.service.d/override.conf

	# The wizard would normally chmod +x these; do it ourselves so the
	# login banner still works.
	chmod +x /etc/update-motd.d/* 2>/dev/null || true

	echo "root:${ROOT_PASSWORD}" | chpasswd

	mkdir -p /etc/ssh/sshd_config.d
	{
		echo "# Installed by the ws1508-armbian image build."
		echo "# Edit this file (or /etc/ssh/sshd_config) to change SSH policy."
		if [ "${ROOT_PASSWORD_LOGIN}" = "no" ]; then
			echo "PermitRootLogin prohibit-password"
			echo "PasswordAuthentication no"
		else
			echo "PermitRootLogin yes"
			echo "PasswordAuthentication yes"
		fi
		echo "UseDNS no"
		echo "ClientAliveInterval 60"
	} > /etc/ssh/sshd_config.d/10-ws1508.conf

	# Older sshd builds ignore the drop-in directory unless it is included.
	if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
		sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
	fi

	if [ -n "${SSH_KEY}" ]; then
		say "Installing the provided SSH public key for root"
		mkdir -p /root/.ssh
		chmod 700 /root/.ssh
		printf '%s\n' "${SSH_KEY}" > /root/.ssh/authorized_keys
		chmod 600 /root/.ssh/authorized_keys
	fi

	# Host keys.
	#
	# A published image must not ship host keys that every WS1508 in the
	# world then shares. Armbian already solves this: armbian-firstrun.service
	# is enabled at build time and, with OPENSSHD_REGENERATE_HOST_KEYS=true,
	# deletes and regenerates the host keys on first boot.
	#
	# What we must NOT do is delete the keys here. armbian-firstrun.service
	# declares "After=ssh.service", so on first boot sshd starts BEFORE it --
	# and Debian's ssh.service runs "sshd -t" as ExecStartPre, which fails
	# when there is no host key. The image would come up with sshd in a
	# failed state, which is precisely the outcome this image exists to
	# avoid. So the build-time keys stay, and firstrun swaps them out
	# seconds into the first boot.
	if [ -f /etc/default/armbian-firstrun ]; then
		sed -i 's/^OPENSSHD_REGENERATE_HOST_KEYS=.*/OPENSSHD_REGENERATE_HOST_KEYS=true/' \
			/etc/default/armbian-firstrun
	fi

	systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true

	# Safety net for the case where the image somehow has no host key at all
	# (and for Debian trixie, where openssh-server is socket-activated and
	# ssh.socket can start sshd without ssh.service ever being ordered).
	# It is a no-op whenever keys are present, which is the normal case.
	cat > /etc/systemd/system/ws1508-sshd-keygen.service <<-'EOF'
		[Unit]
		Description=Generate SSH host keys if none are present
		Before=ssh.service ssh.socket
		ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/bin/ssh-keygen -A

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl enable ws1508-sshd-keygen.service || true
}

# ---------------------------------------------------------------------------
# Identity and locale
# ---------------------------------------------------------------------------
setup_identity() {
	say "Setting hostname to ${HOSTNAME} and timezone to ${TIMEZONE}"
	echo "${HOSTNAME}" > /etc/hostname
	if grep -q '127.0.1.1' /etc/hosts; then
		sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
	else
		echo -e "127.0.1.1\t${HOSTNAME}" >> /etc/hosts
	fi

	if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
		ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
		echo "${TIMEZONE}" > /etc/timezone
	fi
}

# ---------------------------------------------------------------------------
# Memory: this board has 512MB and no swap partition
# ---------------------------------------------------------------------------
setup_memory() {
	say "Tuning for 512MB of RAM"

	# zram. Armbian enables its zram service by default; these values are
	# picked for a small, slow, flash-backed box:
	#   - lz4 for swap. On a 1.5GHz Cortex-A5 the compression ratio gain
	#     from zstd is not worth its CPU cost in the swap path.
	#   - 200% of DRAM as zram disksize with a 50% memory limit, i.e. up to
	#     ~1GB of compressed swap that can occupy at most ~256MB of real
	#     RAM. Overcommitting like this is the point of zram.
	#   - zstd for the log and /tmp devices, which are written rarely and
	#     benefit from the better ratio.
	cat > /etc/default/armbian-zram-config <<-'EOF'
		# Tuned for the WS1508's 512MB of RAM by the ws1508-armbian build.
		ENABLED=true

		SWAP=true
		# 200% of DRAM as compressed swap...
		ZRAM_PERCENTAGE=200
		# ...but never let it hold more than 50% of DRAM of compressed data.
		MEM_LIMIT_PERCENTAGE=50
		# lz4 is the right trade-off on a Cortex-A5: much cheaper than zstd
		# and the ratio difference barely matters for swap pages.
		SWAP_ALGORITHM=lz4
		SWAP_PRIORITY=100
		ZRAM_MAX_DEVICES=1

		RAMLOG_ALGORITHM=zstd
		TMP_ALGORITHM=zstd
		TMP_SIZE=64M
	EOF

	# Keep the RAM log small; the default 50M is a lot on a 512MB box.
	if [ -f /etc/default/armbian-ramlog ]; then
		sed -i 's/^SIZE=.*/SIZE=32M/' /etc/default/armbian-ramlog
	fi

	cat > /etc/sysctl.d/98-ws1508-lowmem.conf <<-'EOF'
		# Low-memory tuning for the WS1508 (512MB, zram swap, flash storage).

		# With zram, swapping is cheap and should be preferred over evicting
		# the page cache; the kernel default of 60 is tuned for spinning disks.
		vm.swappiness = 100

		# zram is random-access, so reading a cluster of neighbouring pages on
		# a fault is pure waste. 0 means "fault in one page at a time".
		vm.page-cluster = 0

		# Reclaim dentry/inode caches more eagerly than the default 100.
		vm.vfs_cache_pressure = 200

		# Write dirty pages back sooner. Small absolute limits keep a burst of
		# writes from pinning a large share of 512MB, and shorten the flush
		# that would otherwise stall the box on slow eMMC/USB storage.
		vm.dirty_ratio = 10
		vm.dirty_background_ratio = 5

		# Keep a reserve so the allocator does not fail under sudden pressure.
		vm.min_free_kbytes = 8192

		# Allow overcommit; without it, forking large processes fails early on
		# a machine whose "swap" is compressed RAM.
		vm.overcommit_memory = 0
	EOF

	# systemd's journal is a notable memory and flash consumer. Keep it in
	# RAM and small; Armbian's ramlog already handles /var/log persistence.
	mkdir -p /etc/systemd/journald.conf.d
	cat > /etc/systemd/journald.conf.d/98-ws1508.conf <<-'EOF'
		[Journal]
		Storage=volatile
		RuntimeMaxUse=16M
		RuntimeMaxFileSize=4M
		ForwardToSyslog=no
		Compress=yes
	EOF
}

# ---------------------------------------------------------------------------
# Trim services this board cannot use or does not need at boot
# ---------------------------------------------------------------------------
trim_services() {
	say "Disabling services this board has no hardware for"

	# The WS1508 has no wireless, no Bluetooth and no modem.
	for unit in ModemManager.service bluetooth.service wpa_supplicant.service \
	            hciuart.service brcm-patchram-plus.service; do
		systemctl disable "${unit}" 2>/dev/null || true
		systemctl mask "${unit}" 2>/dev/null || true
	done

	# The unattended apt timers are the single biggest memory spike on a
	# small box: apt's solver can transiently want hundreds of MB, and it
	# fires while the user is doing something else. Updates stay entirely
	# possible, just not automatic and not at a random moment.
	for unit in apt-daily.timer apt-daily-upgrade.timer \
	            unattended-upgrades.service man-db.timer; do
		systemctl disable "${unit}" 2>/dev/null || true
		systemctl mask "${unit}" 2>/dev/null || true
	done

	# man-db's index rebuild on every package install is slow and
	# memory-hungry on this CPU, and the image has no man pages worth
	# indexing.
	cat > /etc/dpkg/dpkg.cfg.d/98-ws1508-nodoc <<-'EOF'
		path-exclude=/usr/share/man/*
		path-exclude=/usr/share/doc/*
		path-include=/usr/share/doc/*/copyright
	EOF
}

# ---------------------------------------------------------------------------
# A small helper so users can tell which WS1508 variant they have
# ---------------------------------------------------------------------------
install_helper() {
	say "Installing the ws1508-info helper"
	cat > /usr/local/sbin/ws1508-info <<-'EOF'
		#!/bin/sh
		# Report what this WS1508 actually is, which decides whether the
		# system can live on internal storage.
		echo "=== WS1508 ==="
		echo "model:   $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')"
		echo "kernel:  $(uname -r)"
		printf 'memory:  '; awk '/MemTotal/ {printf "%d MB\n", $2/1024}' /proc/meminfo
		echo
		echo "--- what the bootloader found ---"
		# u-boot's own storage detection, handed over on the kernel command
		# line by boot-ws1508.cmd. This is the answer without a serial cable.
		store=$(sed -n 's/.*ws1508\.store=\([0-9]*\).*/\1/p' /proc/cmdline)
		case "$store" in
		    0) echo "store:   SPI (unexpected on this board)" ;;
		    1) echo "store:   raw NAND  <- u-boot detected NAND" ;;
		    2) echo "store:   eMMC      <- u-boot detected eMMC" ;;
		    3) echo "store:   NONE detected - u-boot found no internal flash." ;;
		    *) echo "store:   (not reported; bootloader predates this feature)" ;;
		esac
		echo
		echo "--- internal storage as Linux sees it ---"
		if [ -e /sys/class/mmc_host/mmc1/mmc1:0001 ] || \
		   lsblk -dno NAME 2>/dev/null | grep -q '^mmcblk1$'; then
		    size=$(lsblk -bdno SIZE /dev/mmcblk1 2>/dev/null)
		    echo "type:    eMMC (/dev/mmcblk1)"
		    [ -n "$size" ] && echo "size:    $((size / 1024 / 1024)) MB"
		    echo
		    echo "This unit CAN run entirely from internal storage."
		    echo "Flash the full *.burn.img with the Amlogic USB Burning Tool."
		else
		    echo "type:    no eMMC detected - this is most likely a raw-NAND unit"
		    echo
		    if [ -e /sys/class/mtd/mtd0 ]; then
		        mtdsize=$(cat /sys/class/mtd/mtd0/size 2>/dev/null || echo 0)
		        mtdflags=$(cat /sys/class/mtd/mtd0/flags 2>/dev/null || echo 0)
		        echo "mtd0:    $((mtdsize / 1024 / 1024)) MB, erase block $(cat /sys/class/mtd/mtd0/erasesize) B, page $(cat /sys/class/mtd/mtd0/writesize) B"
		        # 0x400 is MTD_WRITEABLE; the driver clears it by default
		        if [ $((mtdflags & 0x400)) -eq 0 ]; then
		            echo "access:  READ-ONLY (the driver's default)"
		        else
		            echo "access:  writable - meson_nand.allow_write=1 is set"
		        fi
		        echo
		        echo "The raw-NAND driver is bound and enumerated the chip."
		        echo "Whether it is reading it CORRECTLY is a separate"
		        echo "question: this driver has never run on meson8b"
		        echo "silicon, and until the ECC strength and scrambler"
		        echo "settings are confirmed to match the vendor, reads of"
		        echo "vendor-written pages may come back uncorrectable."
		        echo
		        echo "Booting from it IS implemented, but has never run on"
		        echo "real silicon: the bootloader reads an Android boot.img"
		        echo "from the vendor 'boot' partition, and Linux roots on a"
		        echo "UBI volume in /dev/mtd1. Right now this box is running"
		        echo "from USB, SD or eMMC."
		        echo
		        echo "Run 'ws1508-nand-probe' to inspect or dump the flash."
		        echo "Run 'ws1508-install-to-nand' to install the root"
		        echo "filesystem -- read docs/flashing.md first, the kernel"
		        echo "half needs the USB Burning Tool."
		    else
		        echo "There is no /dev/mtd0. Two possible reasons:"
		        echo
		        echo "  1. the running device tree leaves the NAND"
		        echo "     controller disabled - the default, and the"
		        echo "     likely one. To turn it on, add this to"
		        echo "     /boot/armbianEnv.txt and reboot:"
		        echo
		        echo "         fdtfile=meson8b-ws1508-nand.dtb"
		        echo
		        echo "  2. it is enabled and nand_scan() did not manage to"
		        echo "     enumerate the fitted die. That is a real"
		        echo "     possibility: this driver has never run on"
		        echo "     meson8b silicon. Check dmesg for meson-nand."
		        echo
		        echo "Read the notes beside that fdtfile line first: it is"
		        echo "experimental and unvalidated, it gives a READ-ONLY"
		        echo "mtd if it works at all, and it does NOT let the box"
		        echo "boot from internal storage."
		    fi
		    echo
		    echo "The root filesystem stays on USB or SD on this variant."
		    echo "Flash ws1508-uboot.burn.img (bootloader only) and boot the"
		    echo "system from a USB stick."
		fi
		echo
		echo "--- current root ---"
		findmnt -no SOURCE,FSTYPE,SIZE,USED /  2>/dev/null || df -h /
		echo
		echo "--- swap ---"
		swapon --show 2>/dev/null || echo "(none)"
	EOF
	chmod +x /usr/local/sbin/ws1508-info

	# The on-device eMMC installer: an alternative to flashing the full
	# *.burn.img that writes a normal MBR itself, so it does not depend on
	# how the Amlogic burning tool happens to lay partitions out. Shipped
	# as a file in userpatches/overlay rather than inlined here, because it
	# is long enough to want reviewing on its own.
	if [ -r /tmp/overlay/ws1508-install-to-emmc ]; then
		install -m 0755 /tmp/overlay/ws1508-install-to-emmc \
			/usr/local/sbin/ws1508-install-to-emmc
	fi

	# Read-only diagnostics for the raw-NAND variant. Harmless to ship on
	# an eMMC unit: it exits early when the running device tree is not the
	# NAND one.
	if [ -r /tmp/overlay/ws1508-nand-probe ]; then
		install -m 0755 /tmp/overlay/ws1508-nand-probe \
			/usr/local/sbin/ws1508-nand-probe
	fi

	# The on-device NAND installer. Writes only the UBI root filesystem;
	# the kernel side goes into the vendor "boot" partition with the USB
	# Burning Tool, because that partition is behind Amlogic's NFTL. Also
	# harmless on an eMMC unit: it refuses to run unless the bootloader
	# reported store=1 and the running device tree gave it an MTD
	# partition labelled "ubi".
	if [ -r /tmp/overlay/ws1508-install-to-nand ]; then
		install -m 0755 /tmp/overlay/ws1508-install-to-nand \
			/usr/local/sbin/ws1508-install-to-nand
	fi

	# A UBIFS root has to be mountable before the root filesystem exists,
	# so the modules have to be in the initramfs. Listing them here means
	# the USB image already carries an initramfs that can mount NAND --
	# which is what the Android boot.img packed by scripts/make-nand-image.sh
	# picks up, since it takes the initrd straight out of the built image.
	# ws1508-install-to-nand writes the same three lines into the system it
	# installs, so a later update-initramfs there keeps them.
	for _mod in meson_nand ubi ubifs; do
		grep -qxF "${_mod}" /etc/initramfs-tools/modules 2>/dev/null \
			|| echo "${_mod}" >> /etc/initramfs-tools/modules
	done
	unset _mod

	# Show the essentials, including the default-password warning, on login.
	cat > /etc/update-motd.d/09-ws1508 <<-EOF
		#!/bin/sh
		echo ""
		echo "  Xunlei WS1508 - Armbian (ws1508-armbian)"
		echo "  Run 'ws1508-info' to see RAM, storage type and root device."
		echo "  Booted from USB on an eMMC unit? 'ws1508-install-to-emmc'"
		echo "  copies this system to the internal eMMC."
		echo "  On a raw-NAND unit: 'ws1508-install-to-nand' (experimental)."
	EOF
	if [ "${ROOT_PASSWORD_LOGIN}" = "yes" ] && [ -z "${SSH_KEY}" ]; then
		cat >> /etc/update-motd.d/09-ws1508 <<-EOF
			echo ""
			echo "  !! This image ships a default root password. Change it now:"
			echo "  !!     passwd"
		EOF
	fi
	echo 'echo ""' >> /etc/update-motd.d/09-ws1508
	chmod +x /etc/update-motd.d/09-ws1508
}

install_packages() {
	local pkgs="${REQUIRED_PACKAGES} ${EXTRA_PACKAGES}"
	# shellcheck disable=SC2086
	set -- ${pkgs}
	[ "$#" -gt 0 ] || return 0
	say "Installing packages: $*"
	export DEBIAN_FRONTEND=noninteractive
	apt-get -y update
	apt-get -y --no-install-recommends install "$@"
	apt-get -y clean
	rm -rf /var/lib/apt/lists/*
}

Main() {
	setup_ssh
	setup_identity
	setup_memory
	trim_services
	install_helper
	install_packages
	say "WS1508 customisation done"
}

Main "$@"
