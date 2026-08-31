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

	# Forward-looking hygiene, not a guarantee that holds today.
	# CONFIG_MTD_PARTITIONED_MASTER=n only suppresses the whole-chip
	# master device once a partitions node exists. meson8b-ws1508-nand.dts
	# deliberately declares none, so right now /dev/mtd0 IS the whole
	# unpartitioned chip and the only thing keeping a write off the
	# bootloader is the driver's address guard. This symbol matters the
	# day somebody adds partitions.
	kernel_config_set_n MTD_PARTITIONED_MASTER

	if [[ "${slub_debug}" == "yes" ]]; then
		kernel_config_set_y SLUB_DEBUG
		kernel_config_set_y SLUB_DEBUG_ON
	fi

	# Deliberately NOT enabled: MTD_UBI, MTD_UBI_BLOCK, UBIFS_FS and
	# MTD_BLOCK. That keeps the kernel from mounting anything on this
	# flash, which is the point at stage 1.
	#
	# It is NOT a defence against a user erasing the chip, and nothing
	# here should be read as one. userpatches/customize-image.sh installs
	# mtd-utils into every image, Debian's mtd-utils is the combined
	# package, and flash_erase / nandwrite / nandtest / ubiformat all work
	# straight through /dev/mtdN with MEMERASE and MEMWRITE ioctls and
	# need no UBI or mtdblock support in the kernel at all. So the
	# barriers that actually exist are the two in the driver:
	#
	#   - the MTD is read-only unless meson_nand.allow_write=1, and
	#   - erase, program, OOB write and mark-bad are refused below the
	#     vendor boot region whatever allow_write says -- including the
	#     MEMSETBADBLOCK path, which erases the block before marking it
	#     and which "nandtest --markbad" issues after a refused erase.
	#
	# Turn UBI on only after the ECC, scrambler and bad-block behaviour
	# have been checked against a real unit.
}
