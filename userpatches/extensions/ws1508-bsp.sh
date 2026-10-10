#!/usr/bin/env bash
#
# Put the WS1508's own tools into its board-support package, and give every
# image an update channel.
#
# The point of both is that a box already in the field can be brought up to
# date with apt instead of a reflash. Everything apt can replace lives in a
# package: the kernel and device trees in Armbian's linux-image/linux-dtb
# debs, the boot script and the ws1508-* tools in armbian-bsp-cli-ws1508.
# Things installed straight into the rootfs by customize-image.sh, as the
# tools used to be, are frozen at whatever the image shipped with.
#
# The channel itself is a flat apt repository attached to every GitHub
# release (scripts/make-apt-repo.sh). ws1508-apt-setup, shipped here, is the
# single place that knows what the pin and the source look like; this file
# only decides when each of them is written:
#
#   the pin      from the BSP postinst, on every install and upgrade, and so
#                also inside the image build. It stops Armbian's own
#                same-named kernel packages, which carry no WS1508 device
#                tree, from ever replacing ours.
#   the source   at the very end of the image build, after Armbian's last
#                "apt-get update" inside it. Any earlier and those updates
#                would fetch from our releases in the middle of building one
#                -- and fail outright while the newest release predates the
#                channel and has no index.
#
# Enabled from userpatches/config/boards/ws1508.conf via enable_extension.

function post_family_tweaks_bsp__ws1508_tools_and_update_channel() {
	display_alert "Adding ws1508-* tools and the update channel to the BSP" "${BOARD}" "info"

	local overlay="${USERPATCHES_PATH}/overlay"
	local tool
	install -d -m 0755 "${destination}/usr/sbin"
	for tool in ws1508-info ws1508-install-to-emmc ws1508-install-to-nand ws1508-nand-probe ws1508-apt-setup; do
		[[ -f "${overlay}/${tool}" ]] || exit_with_error "WS1508 BSP: missing ${overlay}/${tool}"
		install -m 0755 "${overlay}/${tool}" "${destination}/usr/sbin/${tool}"
	done

	postinst_functions+=(ws1508_bsp_postinst)
}

# The body of this function is copied verbatim into the BSP's postinst (see
# artifact_package_hook_helper_board_side_functions): it runs on the box, at
# the postinst's top level and under "set +e". Hence no "local", no heredocs,
# and nothing from the build environment.
function ws1508_bsp_postinst() {
	# The pin first. Without it the first Armbian release numbered above
	# this build would replace the kernel and device trees on a plain
	# "apt upgrade", and the box would not boot.
	if [ -x /usr/sbin/ws1508-apt-setup ]; then
		/usr/sbin/ws1508-apt-setup pin > /dev/null || echo "ws1508: could not write the apt pin; run 'ws1508-apt-setup pin'" >&2
		/usr/sbin/ws1508-apt-setup refresh > /dev/null || true
	fi

	# Images from before the update channel installed these by hand into
	# /usr/local/sbin, which comes ahead of /usr/sbin in root's PATH and
	# would keep shadowing the packaged copies with the old ones. Remove
	# only files no package owns and that are recognisably ours.
	for ws1508_tool in ws1508-info ws1508-install-to-emmc ws1508-install-to-nand ws1508-nand-probe; do
		ws1508_old="/usr/local/sbin/${ws1508_tool}"
		if [ -f "${ws1508_old}" ] && ! dpkg -S "${ws1508_old}" > /dev/null 2>&1 &&
			grep -q "WS1508" "${ws1508_old}" 2> /dev/null; then
			rm -f "${ws1508_old}"
		fi
	done
	unset ws1508_tool ws1508_old
}

function post_post_debootstrap_tweaks__ws1508_enable_update_channel() {
	display_alert "Enabling the WS1508 update channel in the image" "${BOARD}" "info"
	install -d -m 0755 "${SDCARD}/etc/apt/sources.list.d"
	bash "${USERPATCHES_PATH}/overlay/ws1508-apt-setup" print-source > "${SDCARD}/etc/apt/sources.list.d/ws1508.sources"
	chmod 0644 "${SDCARD}/etc/apt/sources.list.d/ws1508.sources"
}
