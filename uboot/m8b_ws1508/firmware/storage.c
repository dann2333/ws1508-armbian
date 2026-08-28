/*
 * Storage / partition layout for the Xunlei WS1508, used by the ACS blob
 * and by the USB burning protocol.
 *
 * Layout matches what the Armbian image expects:
 *   resource -   4MB  boot logo + u-boot resources
 *   boot     - 256MB  FAT32, holds uImage / uInitrd / dtb / boot.scr
 *   rootfs   -  rest  ext4 root filesystem
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
		.mask_flags = STORE_DATA,
	},
	{
		.name = "boot",
		.size = 256 * SZ_1M,
		.mask_flags = STORE_DATA,
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
