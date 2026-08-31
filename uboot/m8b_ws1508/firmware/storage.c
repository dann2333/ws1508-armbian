/*
 * Storage / partition layout for the Xunlei WS1508, used by the ACS blob
 * and by the USB burning protocol.
 *
 * Layout matches what the Armbian image expects:
 *   resource -   4MB  boot logo + u-boot resources
 *   boot     - 256MB  FAT32 on eMMC / an Android boot.img on NAND
 *   rootfs   -  rest  ext4 root filesystem (eMMC only; see below)
 *
 * mask_flags is read by exactly one thing: amlnand_get_dev_num() in
 * drivers/amlnf/phy/chipenv.c, which sorts these entries into the three
 * amlnf "phy devices" nfcache (STORE_CACHE), nfcode (STORE_CODE) and
 * nfdata (STORE_DATA). Nothing on the eMMC path looks at it at all, so
 * the choice below is a pure NAND decision and changes nothing for an
 * eMMC unit.
 *
 * resource and boot are STORE_CODE on purpose. The NFTL layer is a
 * prebuilt blob (drivers/amlnf/logic/libamlnf_logic_150311.z) and its
 * amlnf_logic_init() skips the nfdata device when called with flag 0 --
 * which is exactly how arch/arm/lib/board.c:750 calls it on every normal
 * boot. With all three partitions tagged STORE_DATA, as they were, a
 * NAND unit came up with NO NFTL devices at all: "store read boot",
 * "imgread kernel boot" and even the existing "imgread pic resource
 * bootup" in CONFIG_PREBOOT could never have worked. Moving the two
 * partitions the bootloader actually reads into nfcode is what makes
 * booting from internal NAND possible.
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
 * WARNING: changing the name or size of any entry here changes the
 * partition table stored on the chip, and amlnand_configs_confirm()
 * (chipenv.c:1995) treats a mismatch against the on-chip copy as fatal
 * unless the burn was told to erase. The first flash of a bootloader
 * carrying a changed table MUST be done with the USB Burning Tool's
 * "erase flash" ticked. That erase also destroys the per-unit nkey/nsec
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
