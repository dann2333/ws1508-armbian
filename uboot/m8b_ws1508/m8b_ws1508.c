#include <common.h>

#include <asm/arch/memory.h>
#include <asm/mach-types.h>

DECLARE_GLOBAL_DATA_PTR;

u32 get_board_rev(void)
{
	return 0x10;
}

int board_init(void)
{
	gd->bd->bi_arch_number = MACH_TYPE_MESON6_SKT;
	gd->bd->bi_boot_params = BOOT_PARAMS_OFFSET;

	extern void ws1508_led_init(void);
	ws1508_led_init();

#ifdef CONFIG_USB_DWC_OTG_HCD
	extern int ws1508_usb_init(void);
	ws1508_usb_init();
#endif /*CONFIG_USB_DWC_OTG_HCD*/

	return 0;
}
