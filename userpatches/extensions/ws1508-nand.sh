#!/usr/bin/env bash
#
# Enable the raw-NAND (MTD) stack in the WS1508 kernel.
#
# The driver this turns on is the meson8/meson8b support added by the
# ws1508-01xx-mtd-rawnand-* patches in
# userpatches/kernel/archive/meson-6.12. It has never been run on real
# S805 silicon.
#
# Nothing here changes what an eMMC unit does: the module only ever binds
# if the running device tree has an enabled amlogic,meson8b-nfc node, and
# only meson8b-ws1508-nand.dtb has one. See that file for what the
# feature is and is not.
#
# Enabled from userpatches/config/boards/ws1508.conf via enable_extension.
#
# Optional: build with WS1508_NAND_SLUB_DEBUG=yes to add SLUB debugging.
# That is the thing that turns a DMA overrun in this driver from "an
# unrelated kfree() explodes some time later" into a report that names
# the buffer. It costs memory and speed on every allocation in the
# system, so it is off by default and released images do not have it.

function custom_kernel_config__ws1508_nand() {
	display_alert "Enabling meson8b raw-NAND (MTD) support" "ws1508" "info"

	local slub_debug="no"
	if [[ "${WS1508_NAND_SLUB_DEBUG:-no}" == "yes" ]]; then
		slub_debug="yes"
		display_alert "Adding SLUB debugging for NAND bring-up" "ws1508" "wrn"
	fi

	# Armbian calls this hook twice: once with no .config present, purely
	# to fold the symbols below into the artifact version hash, and once
	# for real. Declare the intent unconditionally so a change here
	# invalidates the cached kernel .debs, and only touch .config when
	# there is one.
	kernel_config_modifying_hashes+=(
		"MTD=y"
		"MTD_OF_PARTS=y"
		"MTD_RAW_NAND=y"
		"MTD_NAND_MESON=m"
		"MTD_PARTITIONED_MASTER=n"
		"MTD_UBI=m"
		"MTD_UBI_BLOCK=y"
		"UBIFS_FS=m"
		"UBIFS_FS_ADVANCED_COMPR=y"
		"UBIFS_FS_LZO=y"
		"UBIFS_FS_ZLIB=y"
		"UBIFS_FS_ZSTD=y"
	)
	# Announced as the real symbols, so the debug kernel and the normal one
	# cannot share a cached artifact and the announcement names something
	# that exists.
	if [[ "${slub_debug}" == "yes" ]]; then
		kernel_config_modifying_hashes+=("SLUB_DEBUG=y" "SLUB_DEBUG_ON=y")
	fi
	[[ -f .config ]] || return 0

	kernel_config_set_y MTD
	kernel_config_set_y MTD_OF_PARTS
	kernel_config_set_y MTD_RAW_NAND

	# A module, not built-in, so that the eMMC image cannot even have the
	# code resident unless something asks for it. On the default dtb
	# nothing matches the driver's of_device_id table, so it never binds
	# either way -- but keeping it out of vmlinux makes that obvious
	# rather than something you have to reason about.
	kernel_config_set_m MTD_NAND_MESON

	# meson8b-ws1508-nand.dts now declares a partitions node, so this
	# symbol does what it was put here for: with it off there is no
	# whole-chip master device, and the only MTDs are the two partitions
	# -- /dev/mtd0 "vendor" (read-only) and /dev/mtd1 "ubi".
	#
	# Nothing depends on that numbering, deliberately: the bootloader
	# says ubi.mtd=ubi and ws1508-install-to-nand looks partitions up by
	# label. So turning this back on would waste a device node but would
	# not misdirect UBI at the vendor region.
	kernel_config_set_n MTD_PARTITIONED_MASTER

	if [[ "${slub_debug}" == "yes" ]]; then
		kernel_config_set_y SLUB_DEBUG
		kernel_config_set_y SLUB_DEBUG_ON
	fi

	# UBI/UBIFS: the root filesystem for a unit booting from internal
	# NAND. UBI is what makes raw NAND usable as a rootfs medium at all
	# -- it does the wear levelling and bad-block handling that the
	# vendor's closed NFTL blob does on its side of the chip, except in
	# a format Linux can actually read.
	#
	# Modules, not built-in, for the same reason MTD_NAND_MESON is: an
	# eMMC image should not carry this code resident. The initramfs
	# carries meson_nand, ubi and ubifs instead (see
	# userpatches/customize-image.sh), which is what a UBIFS root needs.
	#
	# MTD_UBI_BLOCK is =y because it is a bool, not a tristate; it costs
	# nothing without MTD_UBI loaded and gives a read-only block device
	# over a UBI volume, which is the escape hatch if a squashfs root is
	# ever preferred over UBIFS.
	kernel_config_set_m MTD_UBI
	kernel_config_set_y MTD_UBI_BLOCK
	kernel_config_set_m UBIFS_FS
	kernel_config_set_y UBIFS_FS_ADVANCED_COMPR
	kernel_config_set_y UBIFS_FS_LZO
	kernel_config_set_y UBIFS_FS_ZLIB
	kernel_config_set_y UBIFS_FS_ZSTD

	if [[ "${slub_debug}" == "yes" ]]; then
		kernel_config_set_y SLUB_DEBUG
		kernel_config_set_y SLUB_DEBUG_ON
	fi

	# Still NOT enabled: MTD_BLOCK. mtdblock over raw NAND has no
	# bad-block handling at all, so it is a trap rather than a fallback.
	# Everything here goes through UBI.
	#
	# None of this is a defence against a user erasing the chip, and
	# nothing here should be read as one. userpatches/customize-image.sh
	# installs mtd-utils into every image and flash_erase / nandwrite /
	# nandtest / ubiformat all work straight through /dev/mtdN with
	# MEMERASE and MEMWRITE ioctls. The barriers that actually exist are:
	#
	#   - /dev/mtd0 "vendor" is read-only in the device tree, covering
	#     the whole 384MiB the vendor stack owns,
	#   - the MTD is read-only altogether unless meson_nand.allow_write=1,
	#     and
	#   - erase, program, OOB write and mark-bad are refused below the
	#     driver's own guard whatever allow_write says -- including the
	#     MEMSETBADBLOCK path, which erases the block before marking it
	#     and which "nandtest --markbad" issues after a refused erase.
	#
	# The write path has still never been exercised on real silicon.
}
