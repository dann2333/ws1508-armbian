#!/usr/bin/env bash
#
# Build the WS1508 bootloader and pack it into an Amlogic burn package.
#
# Produces, in $OUTDIR/uboot/:
#   ws1508-uboot.burn.img   bootloader-only burn package. Flash this with the
#                           USB Burning Tool on ANY WS1508 (NAND or eMMC) to
#                           replace the stock Xunlei bootloader. Afterwards
#                           the box boots from USB/SD, and on eMMC units it
#                           will also boot from eMMC.
#   burn-base/              unpacked form of the above, which
#                           make-burn-image.sh extends with the Armbian
#                           boot+rootfs partitions to build the full
#                           direct-flash image.
#   u-boot.bin, u-boot-comp.bin, ddr_init.bin, resource.img
#
# Requires i386 multiarch: the vendor toolchain shipped with the u-boot tree
# is a 32-bit x86 binary.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

UBOOT_SRC="${WORKDIR}/uboot"
UBOOT_OUT="${OUTDIR}/uboot"
TOOLS="${WORKDIR}/tools"

mkdir -p "${WORKDIR}" "${UBOOT_OUT}" "${TOOLS}"

clone_pinned "${UBOOT_REPO}" "${UBOOT_COMMIT}" "${UBOOT_SRC}"

log "Applying the m8b_ws1508 board overlay"
rm -rf "${UBOOT_SRC}/board/amlogic/m8b_ws1508"
cp -r "${REPO_ROOT}/uboot/m8b_ws1508" "${UBOOT_SRC}/board/amlogic/"
cp "${REPO_ROOT}/uboot/configs/m8b_ws1508.h" "${UBOOT_SRC}/board/amlogic/configs/"

# Register the board with u-boot's board list (idempotent).
if ! grep -q '^m8b_ws1508[[:space:]]' "${UBOOT_SRC}/board/amlogic/boards.cfg"; then
	cat "${REPO_ROOT}/uboot/boards.cfg.append" >> "${UBOOT_SRC}/board/amlogic/boards.cfg"
fi

log "Unpacking the vendor toolchain"
TOOLCHAIN_DIR="${UBOOT_SRC}/gcc-linaro-arm-none-eabi-4.8-2014.04_linux"
if [[ ! -x "${TOOLCHAIN_DIR}/bin/arm-none-eabi-gcc" ]]; then
	tar -xf "${UBOOT_SRC}/gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz" -C "${UBOOT_SRC}"
fi
export PATH="${PATH}:${TOOLCHAIN_DIR}/bin"

if ! arm-none-eabi-gcc --version >/dev/null 2>&1; then
	die "The vendor ARM toolchain will not run. It is a 32-bit x86 binary; enable i386 multiarch first:
  sudo dpkg --add-architecture i386
  sudo apt-get update
  sudo apt-get install -y libc6:i386 zlib1g:i386 libstdc++6:i386"
fi

log "Building u-boot for m8b_ws1508"
make -C "${UBOOT_SRC}" distclean >/dev/null 2>&1 || true
make -C "${UBOOT_SRC}" m8b_ws1508_config
make -C "${UBOOT_SRC}" -j"$(nproc)"

BUILD="${UBOOT_SRC}/build"
for f in ddr_init.bin u-boot-comp.bin u-boot.bin; do
	[[ -f "${BUILD}/${f}" ]] || die "u-boot build did not produce ${f}"
done

log "Packing the bootloader burn package"
fetch_amlimg "${TOOLS}"
AMLIMG="${TOOLS}/AmlImg"

# resource.img carries the boot logo shown on HDMI.
"${AMLIMG}" res_pack "${BUILD}/resource.img" "${UBOOT_SRC}/resource/"

PACK="${WORKDIR}/pack"
rm -rf "${PACK}"
cp -r "${UBOOT_SRC}/pack" "${PACK}"

cp "${BUILD}/ddr_init.bin"     "${PACK}/DDR.USB"
cp "${BUILD}/u-boot-comp.bin"  "${PACK}/UBOOT_COMP.USB"
cp "${BUILD}/u-boot.bin"       "${PACK}/bootloader.img"
cp "${BUILD}/resource.img"     "${PACK}/resource.img"

printf 'sha1sum %s' "$(sha1sum "${PACK}/bootloader.img" | awk '{print $1}')" > "${PACK}/bootloader.VERIFY"
printf 'sha1sum %s' "$(sha1sum "${PACK}/resource.img"   | awk '{print $1}')" > "${PACK}/resource.VERIFY"

"${AMLIMG}" pack "${UBOOT_OUT}/ws1508-uboot.burn.img" "${PACK}/"

# Unpack it again to give make-burn-image.sh a clean base to extend. This
# round-trip is also a self-check that the package we just wrote is valid.
rm -rf "${UBOOT_OUT}/burn-base"
"${AMLIMG}" unpack "${UBOOT_OUT}/ws1508-uboot.burn.img" "${UBOOT_OUT}/burn-base/"

cp "${BUILD}/ddr_init.bin" "${BUILD}/u-boot.bin" "${BUILD}/u-boot-comp.bin" \
   "${BUILD}/resource.img" "${UBOOT_OUT}/"

log "Bootloader built:"
ls -la "${UBOOT_OUT}"

# Sanity check: the whole point of this port over the stock OneCloud
# bootloader is that it probes for raw NAND as well as eMMC. If that string
# is missing, CONFIG_CMD_NAND did not take effect and NAND units will not
# boot, so fail loudly rather than shipping a bootloader that bricks them.
# Note: grep -c rather than grep -q. Under `set -o pipefail`, grep -q exits
# as soon as it matches, the upstream `strings` dies of SIGPIPE, and the
# pipeline reports failure even though the string was found.
probe_count() { strings "${BUILD}/u-boot-orig.bin" | grep -c "$1" || true; }

if [[ "$(probe_count 'try nand boot')" -eq 0 ]]; then
	die "Built bootloader has no NAND probe - CONFIG_CMD_NAND did not take effect. Refusing to publish."
fi
if [[ "$(probe_count 'try emmc boot')" -eq 0 ]]; then
	die "Built bootloader has no eMMC probe. Refusing to publish."
fi
log "Verified: bootloader probes both NAND and eMMC"
