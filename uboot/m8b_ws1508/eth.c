/*
 * Ethernet setup for the Xunlei WS1508.
 *
 * The WS1508 has a 100Mbit PHY on RMII -- this is the main board-level
 * difference from the OneCloud/WS1608, which uses a gigabit PHY on RGMII.
 * The register programming below follows the Amlogic m8b reference boards
 * (board/amlogic/m8b_m201_v1), which are RMII and share the GPIOH_4 PHY
 * reset line with this board.
 *
 * Note this only affects u-boot's own networking (tftp/dhcp). Linux
 * reprograms PREG_ETHERNET_ADDR0 itself from the phy-mode in the device
 * tree, so a wrong setting here cannot break the booted system.
 */

#include <common.h>

#include <asm/arch/aml_eth_reg.h>
#include <asm/arch/aml_eth_pinmux.h>
#include <asm/arch/io.h>

#ifdef CONFIG_CMD_NET

static void ws1508_eth_init(void)
{
	eth_aml_reg0_t eth_reg0;

	/*
	 * RMII pinmux: TXD0/TXD1/TX_EN, RXD0/RXD1/RX_DV, REF_CLK, MDC/MDIO.
	 * The RGMII-only lines (TXD2/3, RXD2/3, TX_CLK) are left unmuxed.
	 */
	SET_CBUS_REG_MASK(PERIPHS_PIN_MUX_6, 0xff7f);
	SET_CBUS_REG_MASK(PERIPHS_PIN_MUX_7, 0xf00000);

	eth_reg0.d32 = 0;
	eth_reg0.b.phy_intf_sel = 0;		/* 0 = RMII */
	eth_reg0.b.data_endian = 0;
	eth_reg0.b.desc_endian = 0;
	eth_reg0.b.rx_clk_rmii_invert = 0;
	eth_reg0.b.rgmii_tx_clk_src = 0;
	eth_reg0.b.rgmii_tx_clk_phase = 0;
	eth_reg0.b.rgmii_tx_clk_ratio = 1;
	eth_reg0.b.phy_ref_clk_enable = 1;	/* generate the 50MHz RMII ref clk */
	eth_reg0.b.clk_rmii_i_invert = 1;
	eth_reg0.b.clk_en = 1;
	eth_reg0.b.adj_enable = 1;
	eth_reg0.b.adj_setup = 0;
	eth_reg0.b.adj_delay = 18;
	eth_reg0.b.adj_skew = 0;
	eth_reg0.b.cali_start = 0;
	eth_reg0.b.cali_rise = 0;
	eth_reg0.b.cali_sel = 0;
	eth_reg0.b.rgmii_rx_reuse = 0;
	eth_reg0.b.eth_urgent = 0;
	WRITE_CBUS_REG(PREG_ETHERNET_ADDR0, eth_reg0.d32);
	WRITE_CBUS_REG(0x2050, 0x1000);

	/*
	 * Ethernet memory power domain: bits [3:2] of HHI_MEM_PD_REG0,
	 * 0x3 = powered off, 0x0 = normal operation.
	 */
	CLEAR_CBUS_REG_MASK(HHI_MEM_PD_REG0, (0x3 << 2));

	/* Hardware-reset the PHY. GPIOH_4 drives PHY nRST. */
	CLEAR_CBUS_REG_MASK(PREG_PAD_GPIO3_EN_N, 1 << 23);
	CLEAR_CBUS_REG_MASK(PREG_PAD_GPIO3_O, 1 << 23);
	udelay(2000);
	SET_CBUS_REG_MASK(PREG_PAD_GPIO3_O, 1 << 23);
}

int board_eth_init(bd_t *bis)
{
	ws1508_eth_init();
	udelay(1000);

	extern int aml_eth_init(bd_t *bis);
	aml_eth_init(bis);

	return 0;
}

#endif /* CONFIG_CMD_NET */
