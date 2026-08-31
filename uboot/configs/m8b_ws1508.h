/*
 * U-Boot configuration for the Xunlei WS1508 (迅雷赚钱宝二代 / Pro).
 *
 * Amlogic S805 (meson8b), 512MB DDR3, 4GB internal storage which is raw
 * NAND on early units and eMMC on later ones, 100Mbit RMII ethernet,
 * one USB 2.0 OTG port.
 *
 * Derived from board/amlogic/configs/m8b_onecloud.h (syb999/uboot-onecloud,
 * originally hzyitc). The differences from OneCloud, and why:
 *
 *   1. CONFIG_CMD_NAND is enabled. get_device_boot_flag() in
 *      arch/arm/lib/board.c only probes for NAND when CONFIG_CMD_NAND is
 *      defined; the OneCloud config leaves it off because the OneCloud is
 *      eMMC-only. With it off, a raw-NAND WS1508 never finds its store and
 *      cannot boot -- which is exactly the "写入也没用，启动不了的" result
 *      people hit when they flashed the stock OneCloud bootloader onto a
 *      NAND WS1508. Turning it on makes ONE bootloader serve both variants.
 *
 *   2. PHYS_MEMORY_SIZE is 512MB, not 1GB. This feeds CONFIG_SYS_BOOTMAPSZ
 *      (the region bootm may map for Linux). The DDR *initialisation* is
 *      left byte-identical to OneCloud's on purpose: ddr_size_auto_detect()
 *      probes 256MB/512MB/1GB and ddr_mode_auto_detect() probes the bus
 *      width, so the same timing set covers both boards. That auto-detected
 *      size is what reaches Linux, via fdt_fixup_memory_banks().
 *
 *   3. The boot command tries USB, then SD, then eMMC, then NAND,
 *      instead of eMMC only. USB-first gives every unit a rescue path
 *      that does not need the case opened, and NAND last means a unit
 *      whose internal install has gone wrong is always recoverable by
 *      plugging a stick in.
 *
 *      The NAND branch is boot_nand in CONFIG_EXTRA_ENV_SETTINGS below,
 *      and it deliberately does not go through boot.scr -- boot.scr is
 *      itself fatload'ed, and CONFIG_NEXT_NAND drops libmtd.o/libnand.o
 *      so there is no filesystem layer over NAND to fatload from. It
 *      uses "imgread kernel boot" instead, which reads an Android
 *      boot.img out of a vendor partition; see the comment on boot_nand.
 *
 *      Two things that used to be said here and are wrong:
 *      (a) "mainline Linux has no meson8b raw-NAND driver". It does now,
 *          carried by this repo: userpatches/kernel/archive/meson-6.12/
 *          ws1508-0100..0104-*.patch add meson8/meson8b to
 *          drivers/mtd/nand/raw/meson_nand.c. Opt-in (a separate dtb),
 *          read-only by default, and it has NEVER been run on real
 *          meson8b silicon.
 *      (b) "the bootloader cannot read NAND". It can, through the vendor
 *          NFTL -- which is also why Linux cannot share a region with
 *          it: that layer ships only as a blob. The chip is split
 *          physically instead. See firmware/storage.c for the split and
 *          what it cost.
 *
 *   4. Ethernet is RMII (100Mbit) rather than RGMII. See eth.c.
 */

#ifndef __CONFIG_M8B_WS1508_H__
#define __CONFIG_M8B_WS1508_H__



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                 UART Sectoion
// =============================================================================
#define CONFIG_CONS_INDEX	(2)
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                 ACS: DDR controller and system PLLs settings
// =============================================================================
#define CONFIG_ACS
#ifdef CONFIG_ACS
	// Pass memory size from spl to uboot
	#define CONFIG_DDR_SIZE_IND_ADDR	(0xD9000000)
#endif
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                 Security boot
// =============================================================================
#define CONFIG_AML_DISABLE_CRYPTO_UBOOT

// #define CONFIG_SECURITYKEY
// #define CONFIG_SECU_BOOT
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                             UCL data compression
// =============================================================================
#define CONFIG_UCL				1
#define CONFIG_SELF_COMPRESS
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                     Store
// =============================================================================
#define CONFIG_STORE_COMPATIBLE

#define CONFIG_SDIO_B		1
#define PORT_B_CARD_TYPE	(CARD_TYPE_SD)

#define CONFIG_SDIO_C		1
#define PORT_C_CARD_TYPE	(CARD_TYPE_MMC)
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                     eFuse
// =============================================================================
#define CONFIG_EFUSE			1
// #define CONFIG_MACHID_CHECK
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                 Video output
// =============================================================================
#define CONFIG_VIDEO_AML
#define CONFIG_VIDEO_AMLTVOUT
#define CONFIG_AML_HDMI_TX		1
#define CONFIG_OSD_SCALE_ENABLE
#define COLOR_BIT				24
#define CONFIG_AML_FONT

#if(COLOR_BIT == 16)
	#define LCD_BPP				(LCD_COLOR16)
#elif(COLOR_BIT == 24)
	#define LCD_BPP				(LCD_COLOR24)
#else
	#error "unsupported COLOR_BIT"
#endif

#define CONFIG_CMD_BMP
#define CONFIG_CMD_LOGO
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                   Commands
// =============================================================================
#define CONFIG_SYS_LONGHELP
#define CONFIG_AUTO_COMPLETE

#define CONFIG_CMD_AUTOSCRIPT
// #define CONFIG_CMD_BOOTD

#ifdef CONFIG_STORE_COMPATIBLE
	#define CONFIG_NEXT_NAND	// `store` sub-system
	#define CONFIG_CMD_IMGREAD
#endif
#define CONFIG_CMD_IMGPACK

// Raw NAND support. Required so that get_device_boot_flag() probes the
// NAND controller: without it a raw-NAND WS1508 is never detected and
// cannot boot or be flashed. Harmless on eMMC units -- the probe simply
// fails and detection falls through to eMMC.
#define CONFIG_CMD_NAND			1

#define CONFIG_CMD_CPU_TEMP

#define CONFIG_CMD_REBOOT
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                    Network
// =============================================================================
#define CONFIG_CMD_NET
#ifdef CONFIG_CMD_NET
	#define CONFIG_AML_ETHERNET
	#define CONFIG_NET_MULTI
	#define CONFIG_CMD_PING
	#define CONFIG_CMD_DHCP
	#define CONFIG_CMD_RARP

	// The WS1508 has a 100Mbit PHY on RMII (the OneCloud is RGMII).
	#define RMII_PHY_INTERFACE		1
#endif
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                      USB
// =============================================================================
#define CONFIG_CMD_USB
#ifdef CONFIG_CMD_USB
	#define CONFIG_USB_DWC_OTG_HCD
	#define CONFIG_USB_DWC_OTG_294
	#define CONFIG_USB_STORAGE
#endif
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                   USB Burn
// =============================================================================
#ifdef CONFIG_STORE_COMPATIBLE
	#define CONFIG_AML_V2_USBTOOL
	#ifdef CONFIG_AML_V2_USBTOOL
		#define CONFIG_SHA1
	#endif
#endif
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                          FDT: Flattened Device Tree
// =============================================================================
#define CONFIG_OF_LIBFDT
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                     bootm
// =============================================================================
#define CONFIG_AML_GATE_INIT
#define CONFIG_SYS_BOOTMAPSZ	(PHYS_MEMORY_SIZE)	// Initial Memory map for Linux
#define CONFIG_ANDROID_IMG
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                             Environment variables
// =============================================================================
#define CONFIG_PREBOOT				"run prepare_video; run check_usbburn; print 'Waiting for autoboot...'"
#define CONFIG_BOOTDELAY			3
#define CONFIG_BOOTCOMMAND			"print 'Autobooting...'; run boot_usb; run boot_sd; run boot_emmc; run boot_nand; print 'Failed to boot'; "
#define CONFIG_HOSTNAME				"ws1508"
#define CONFIG_ETHADDR				00:15:18:01:81:31
#define CONFIG_IPADDR				192.168.1.150
#define CONFIG_GATEWAYIP			192.168.1.254
#define CONFIG_NETMASK				255.255.255.0
#define CONFIG_SERVERIP				192.168.1.100
#define CONFIG_BOOTFILE				"uImage"
#if (COLOR_BIT == 16)
	#define ENV_VIDEO_COLOR \
		"display_color_format_index=16\0" \
		"display_bpp=16\0" \
		"display_color_fg=0xffff\0" \
		"display_color_bg=0\0"
#elif (COLOR_BIT == 24)
	#define ENV_VIDEO_COLOR \
		"display_color_format_index=24\0" \
		"display_bpp=24\0" \
		"display_color_fg=0xffffff\0" \
		"display_color_bg=0\0"
#else
	#error "unsupported COLOR_BIT"
#endif
#define CONFIG_EXTRA_ENV_SETTINGS \
	"outputmode=1080p\0" \
	"video_dev=tvout\0" \
	"display_width=1920\0" \
	"display_height=1080\0" \
	"display_layer=osd2\0" \
	ENV_VIDEO_COLOR \
	"fb_addr=0x15100000\0" \
	"fb_width=1280\0" \
	"fb_height=720\0" \
	"loadaddr_logo=0x13000000\0" \
	"prepare_video=" \
		"video open; " \
		"video clear; " \
		"video dev open ${outputmode}; " \
		"imgread pic resource bootup ${loadaddr_logo}; " \
		"bmp display ${bootup_offset}; " \
		"bmp scale; " \
		"set_fontsize 24; " \
		"setenv print_color 0xFFFFFF; " \
		"print 'U-Boot'; " \
		"\0" \
	\
	/* Give the Amlogic USB Burning Tool a 1s window on every boot. This */ \
	/* is the unbrick path: connect the USB cable and power on, no need  */ \
	/* to open the case and short the flash pins.                        */ \
	"check_usbburn=" \
		"print -n 'Checking USBBurn...'; " \
		"update 1000; " \
		"print 'Fail'; " \
		"\0" \
	\
	"loadaddr=0x12000000\0" \
	\
	/* Seeded so the detected storage type becomes readable from   */ \
	/* Linux. set_storage_device_flag() (common/partition_table.c) */ \
	/* runs before bootcmd and rewrites this with the runtime      */ \
	/* device_boot_flag -- but ONLY if "store" already exists in   */ \
	/* the environment; with no seed it returns early and the      */ \
	/* result is visible nowhere but the serial console.           */ \
	/* 0=SPI 1=NAND 2=eMMC 3=nothing detected.                     */ \
	"store=3\0" \
	\
	/* Load and run /boot.scr from whatever ${bootdev} currently is.  */ \
	/* Armbian's boot script reads ${bootdev} back to find the rest   */ \
	/* of /boot, so it must stay set to the device we booted from.    */ \
	"boot_scr=" \
		"fatload ${bootdev} ${loadaddr} boot.scr && autoscr ${loadaddr}; " \
		"\0" \
	\
	"boot_usb=" \
		"print -n 'Try to boot from USB...'; " \
		"usb start; " \
		"setenv bootdev 'usb 0'; run boot_scr; " \
		"setenv bootdev 'usb 1'; run boot_scr; " \
		"print 'Fail'; " \
		"\0" \
	\
	"boot_sd=" \
		"print -n 'Try to boot from SD...'; " \
		"mmc rescan 0; " \
		"setenv bootdev 'mmc 0'; run boot_scr; " \
		"print 'Fail'; " \
		"\0" \
	\
	"boot_emmc=" \
		"print -n 'Try to boot from eMMC...'; " \
		"mmc rescan 1; " \
		"setenv bootdev 'mmc 1'; run boot_scr; " \
		"print 'Fail'; " \
		"\0" \
	\
	/* Kernel command line for a root filesystem on internal NAND.    */ \
	/* Separate from the boot_nand logic so it can be edited with     */ \
	/* setenv + saveenv on a unit that needs a different root, which  */ \
	/* is the only way to change it: a NAND boot never reads          */ \
	/* armbianEnv.txt, because there is no filesystem to read it from.*/ \
	/*                                                                */ \
	/* ubi.mtd names the partition rather than numbering it. UBI's    */ \
	/* open_mtd_device() tries the argument as an integer first and   */ \
	/* falls back to get_mtd_device_nm() (drivers/mtd/ubi/build.c),   */ \
	/* so "ubi" resolves by label. Worth the two extra characters:    */ \
	/* with a number, anything that shifts MTD numbering -- turning   */ \
	/* CONFIG_MTD_PARTITIONED_MASTER on, adding a partition ahead of  */ \
	/* it -- would silently attach UBI to the VENDOR region instead.  */ \
	/* meson_nand.allow_write=1 is required or the MTD comes up       */ \
	/* read-only and UBI attaches read-only with it rather than       */ \
	/* failing, which looks like a working boot until the first write.*/ \
	"nandargs=" \
		"root=ubi0:rootfs rootfstype=ubifs ubi.mtd=ubi " \
		"meson_nand.allow_write=1 rootwait rw " \
		"console=tty1 console=ttyAML0,115200n8 " \
		"no_console_suspend consoleblank=0" \
		"\0" \
	\
	"loadaddr_kernel=0x16000000\0" \
	\
	/* Last resort, after USB, SD and eMMC have all failed to produce */ \
	/* a boot.scr. This is the only path that can boot a raw-NAND     */ \
	/* unit from its internal flash, and it deliberately does NOT go  */ \
	/* through boot.scr: boot.scr is itself fatload'ed from a         */ \
	/* filesystem, and CONFIG_NEXT_NAND leaves this bootloader with   */ \
	/* no filesystem layer over NAND at all. So the whole NAND boot   */ \
	/* lives here in the environment.                                 */ \
	/*                                                                */ \
	/* "imgread kernel boot ${addr}" reads an Android boot.img out of */ \
	/* the "boot" NFTL partition, sizing the read from the header     */ \
	/* (common/cmd_imgread.c:328). bootm then boots all three pieces  */ \
	/* out of that one image: the kernel is a legacy uImage at        */ \
	/* +0x800, the ramdisk comes from ramdisk_size, and the device    */ \
	/* tree comes from second_size (common/cmd_bootm.c:294-320). So   */ \
	/* one read and one bootm, with no offsets hard-coded here.       */ \
	/*                                                                */ \
	/* Gated on ${store} = 1 (raw NAND), written "test x${store} = x1" */ \
	/* rather than with quotes: hush consumes quote characters when it */ \
	/* re-parses a variable's value, so a quoted comparison against an */ \
	/* UNSET ${store} would collapse to "test = 1" -- a 3-argument     */ \
	/* test that do_test does not reject (it only refuses argc < 3).   */ \
	/* The x prefix keeps both operands non-empty whatever happens.    */ \
	/* ${store} can genuinely be unset: set_storage_device_flag()      */ \
	/* returns early when getenv("store") is NULL                      */ \
	/* (common/partition_table.c), so a saved environment without it   */ \
	/* is never repaired. On an eMMC unit "store read"                 */ \
	/* silently becomes "mmc read" against the FAT boot partition and */ \
	/* imgread would reject the result -- harmless, but there is no   */ \
	/* reason to try. Nothing here writes or erases: "store init",    */ \
	/* "store write" and "store erase" are all destructive on an eMMC */ \
	/* unit and must never appear in a boot path.                     */ \
	"boot_nand=" \
		"print -n 'Try to boot from NAND...'; " \
		"test x${store} = x1 && " \
			"setenv bootdev nand && " \
			"setenv bootargs ${nandargs} ws1508.store=${store} && " \
			"imgread kernel boot ${loadaddr_kernel} && " \
			"bootm ${loadaddr_kernel}; " \
		"print 'Fail'; " \
		"\0" \
	""
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                        Environment variables Storages
// =============================================================================
#define CONFIG_ENV_SIZE						(64*1024)
#define CONFIG_CMD_SAVEENV
#define CONFIG_ENV_OVERWRITE

#ifndef CONFIG_STORE_COMPATIBLE
	#define CONFIG_ENV_IS_IN_MMC
	#define CONFIG_SYS_MMC_ENV_DEV			(1)
	#define CONFIG_ENV_OFFSET				(0x800000)
#endif
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                      CPU
// =============================================================================
// CPU clock (unit: MHz)
// #define M8_CPU_CLK		(600)
#define M8_CPU_CLK			(792)
// #define M8_CPU_CLK		(996)
// #define M8_CPU_CLK		(1200)
#define CONFIG_SYS_CPU_CLK	(M8_CPU_CLK)

// Enable L1 cache
// to speed up uboot decompression
#define CONFIG_AML_SPL_L1_CACHE_ON	1

// Disable L2 cache
#define CONFIG_L2_OFF
// =============================================================================



// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//                                      DDR
// =============================================================================
// Memory size. The WS1508 ships with 512MB; the auto-detect below still
// probes 256MB/512MB/1GB at runtime and that result is what is handed to
// Linux, so this constant only bounds CONFIG_SYS_BOOTMAPSZ and the
// optional memory test.
#define PHYS_MEMORY_START		(0x00000000)
#define PHYS_MEMORY_SIZE		(0x20000000)
#define CONFIG_DDR3_ROW_SIZE	(3)
#define CONFIG_DDR3_COL_SIZE	(2)
#define CONFIG_DDR_ROW_BITS		(15)

// Auto detect memory
#ifdef CONFIG_ACS
	#define CONFIG_DDR_MODE_AUTO_DETECT		// Auto detect DDR bus-width
	#define CONFIG_DDR_SIZE_AUTO_DETECT		// Auto detect DDR size
#endif

// Dump ddr info
#define CONFIG_DUMP_DDR_INFO

// DDR test
#define CONFIG_ENABLE_MEM_DEVICE_TEST
#define CONFIG_SYS_MEMTEST_START		0x10000000	// 256MB
#define CONFIG_SYS_MEMTEST_END			0x18000000	// 384MB

// DDR clock: 408~804MHz with fixed step 12MHz
// #define CFG_DDR_CLK		(636)
#define CFG_DDR_CLK			(696)
// #define CFG_DDR_CLK		(768)
// #define CFG_DDR_CLK		(792)

// Starting point only: CONFIG_DDR_MODE_AUTO_DETECT above makes
// ddr_mode_auto_detect() ignore this and walk 32-bit, then 16-bit
// lane0+2, then 16-bit lane0+1 until one initialises.
//
// A real WS1508 serial capture ends up at the last of those:
//     DDR mode: 16 bit mode lane0+1
//     DDR size: 512MB (auto)
//     DDR check: Pass!
//     DRAM:  512 MiB
// which matches the board photos - one populated NANYA x16 DDR3 chip and
// one bare twin footprint, i.e. a 16-bit bus carrying 512MB.
//
// Defining CONFIG_DDR_MODE_AUTO_DETECT_SKIP_32BIT would skip the one
// attempt we know must fail and shave a little off boot time. It is
// deliberately NOT set: the saving is small, and if any WS1508 batch ever
// did populate both DRAM sites, skipping 32-bit would leave it unable to
// boot at all. Probing costs a moment; guessing wrong costs the board.
#define CFG_DDR_MODE		(CFG_DDR_32BIT)

// DDR features
// #define CONFIG_GATEACDDRCLK_DISABLE				// Disable DDR clock gating
// #define CONFIG_DDR_LOW_POWER_DISABLE				// Disable DDR low power feature
#define CONFIG_NO_DDR_PUB_VT_CHECK					// Not check the VT done flag when DDR PUB training
// #define CONFIG_PUB_WLWDRDRGLVTWDRDBVT_DISABLE	// Disable DDR PUB WL/WD/RD/RG-LVT, WD/RD-BVT
#define CONFIG_ENABLE_WRITE_LEVELING
// =============================================================================



#endif // __CONFIG_M8B_WS1508_H__
