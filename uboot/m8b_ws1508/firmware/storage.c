/*
 * Storage / partition layout for the Xunlei WS1508, used by the ACS blob
 * and by the USB burning protocol.
 *
 * Layout matches what the Armbian image expects:
 *   resource -   4MB  boot logo + u-boot resources
 *   boot     - 256MB  FAT32 on eMMC / an Android boot.img on NAND
 *   rootfs   -  rest  ext4 root filesystem (eMMC only; see below)
 *
 * mask_flags drives the NAND layout: amlnand_get_dev_num() in
 * drivers/amlnf/phy/chipenv.c sorts these entries into the three amlnf
 * "phy devices" nfcache (STORE_CACHE), nfcode (STORE_CODE) and nfdata
 * (STORE_DATA).
 *
 * It is NOT NAND-only, though, and an earlier version of this comment
 * wrongly said it was. The eMMC path reads it too:
 * drivers/mmc/emmc_partitions.c:198 copies it into the runtime table and
 * mmc_partition_verify():408 compares it against the copy stored on the
 * eMMC. So changing it here does have an eMMC consequence -- on the
 * first boot after this bootloader is flashed, mmc_device_init() finds
 * the stored table different and calls mmc_write_partition_tbl() to
 * rewrite it (emmc_partitions.c, mmc_device_init). That rewrites the
 * table RECORD only; it does not repartition or erase, so an installed
 * eMMC system keeps working. It is a one-time write, not data loss, but
 * it is not nothing and should not be described as nothing.
 *
 * resource and boot are STORE_CODE on purpose. The NFTL layer is a
 * prebuilt blob (drivers/amlnf/logic/libamlnf_logic_150311.z), and its
 * amlnf_logic_init() decides per device whether to build a layer at all.
 * Disassembled, with the two compared strings read out of
 * .rodata.str1.1 (offset 0x22 "nfboot", 0x29 "nfdata"):
 *
 *   3988  strncmp(phydev->name, "nfboot", 6); beq skip   <- always
 *   3994  cmp flag, #0; bne size_check                   <- flag != 0
 *   39b8  strncmp(phydev->name, "nfdata", 6); beq skip   <- only flag 0
 *   39c4  ldrd phydev->size; cmpeq #0x8000000; bls skip  <- <= 128MiB
 *
 * arch/arm/lib/board.c:750 calls it with flag 0 on every normal boot, so
 * nfboot and nfdata get no NFTL devices then and nfcode and nfcache do.
 * With all three partitions tagged STORE_DATA, as they were, they all
 * landed on nfdata and a NAND unit came up with NO NFTL devices at all:
 * "store read boot", "imgread kernel boot" and even the existing
 * "imgread pic resource bootup" in CONFIG_PREBOOT could never have
 * worked. Moving the two partitions the bootloader actually reads into
 * nfcode is what makes booting from internal NAND possible.
 *
 * The same disassembly is why the Linux half of the chip is safe: with
 * flag 0 nothing ever attaches NFTL to nfdata, so its garbage collection
 * and wear levelling never run over the region UBI owns. Note the
 * converse -- with a NON-zero flag, which is what a burning session
 * uses, nfdata DOES get a layer. What that layer writes when it attaches
 * is inside the blob and unknown, so treat any burn as capable of
 * disturbing the UBI area.
 *
 * rootfs stays STORE_DATA, and that is also deliberate. It keeps the
 * name in the table for the eMMC burn path, while on NAND it lands in
 * the one device the blob does not initialise on a normal boot. So the
 * physical tail of the chip is never touched by NFTL garbage collection
 * or wear levelling, which is what lets Linux own it as raw MTD for UBI.
 * See docs/hardware.md for the resulting split.
 *
 * DO NOT SHRINK "boot" TO SAVE SPACE. The NFTL blob refuses to build a
 * layer for any phy device of 128MiB or less: amlnf_logic_init at 0x39c4
 * does "ldrd r2,[r5,#48]" (phydev->size), "cmpeq r2,#0x8000000", "bls"
 * to the skip path. resource+boot is 260MiB, which phydev.c then inflates
 * by 1/8, so nfcode lands near 292MiB and clears the bar. Retag or
 * resize these so that nfcode falls to 128MiB or below and the device
 * gets no NFTL layer at all -- at which point "imgread kernel boot"
 * fails, silently, and the box simply does not boot from NAND. Most
 * other m8b boards give "boot" 32MiB, which would be exactly this trap.
 *
 * ALSO NOTE: with these two moved into nfcode, "store erase data" now
 * erases the kernel as well. It always ran deverase on data, code AND
 * cache in sequence (common/store_interface.c:220-241); what changed is
 * that there is now something of ours in code. The USB Burning Tool's
 * erase levels reach that path, so any re-flash with erase ticked means
 * redoing the NAND install, not just the kernel half.
 *
 * WARNING: changing the name, size OR mask_flags of any entry here
 * changes the partition table stored on the chip -- confirm_dev_para()
 * compares the sorted per-device tables, so a pure mask_flags change
 * moves partitions between devices and is caught exactly like a rename.
 * amlnand_configs_confirm() (chipenv.c:1995) treats the mismatch as
 * fatal unless the burn was told to erase.
 *
 * This very commit is such a change: nfcode goes from 0 partitions to 2
 * and nfdata from 3 to 1, with no name or size touched. So "nothing was
 * renamed or resized" is NOT a reason to skip it -- the FIRST flash of
 * this bootloader onto any NAND unit MUST be done with the USB Burning
 * Tool's "erase flash" ticked. That erase also destroys the per-unit nkey/nsec
 * records, which nothing in this project can restore -- see
 * docs/flashing.md.
 *
 * store_device_flag is only the compiled-in default. At runtime
 * get_device_boot_flag() in arch/arm/lib/board.c re-detects the actual
 * medium (it probes amlnf then eMMC, gated by CONFIG_CMD_NAND /
 * CONFIG_CMD_MMC, both of which we enable) and overwrites the global
 * device_boot_flag that the store subsystem and the USB burning code
 * actually consult. That is what lets one bootloader serve both the
 * raw-NAND and the eMMC WS1508 variants.
 */

#include <asm/arch/storage.h>

#ifdef CONFIG_ACS

/* partition tables */
struct partitions partition_table[] = {
	{
		.name = "resource",
		.size = 4 * SZ_1M,
		.mask_flags = STORE_CODE,
	},
	{
		.name = "boot",
		.size = 256 * SZ_1M,
		.mask_flags = STORE_CODE,
	},
	{
		.name = "rootfs",
		.size = NAND_PART_SIZE_FULL,
		.mask_flags = STORE_DATA,
	},
};

struct store_config store_configs = {
	.store_device_flag = EMMC_BOOT_FLAG,
	.nand_configs = {
		.enable_slc = 0,
		.order_ce = 0,
		.reserved[0] = 0,
		.reserved[1] = 0,
	},
	.mmc_configs = {
		.type = ((PORT_B_CARD_TYPE << 4) | (PORT_C_CARD_TYPE << 8)),
		.port = 0,
		.reserved[0] = 0,
		.reserved[1] = 0,
	},
};

#endif
