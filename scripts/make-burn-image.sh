#!/usr/bin/env bash
#
# Combine the WS1508 bootloader with a built Armbian image into a single
# Amlogic burn package that the USB Burning Tool can write straight to the
# device's internal storage.
#
# Input:
#   $OUTDIR/uboot/burn-base/     produced by build-uboot.sh
#   $OUTDIR/images/*.img         produced by build-armbian.sh
#
# Output:
#   $OUTDIR/images/<name>.burn.img
#
# The Armbian image is a normal two-partition disk image: p1 is the FAT
# boot partition (kernel, initrd, dtb, boot.scr) and p2 is the ext4 root.
# Those two partitions are converted to Android sparse images and appended
# to the bootloader package as the "boot" and "rootfs" partitions, which
# are exactly the names the bootloader's partition table declares (see
# uboot/m8b_ws1508/firmware/storage.c).
#
# NOTE: this packer is for eMMC units. What it writes is a FAT boot
# partition and an ext4 root partition, and on a raw-NAND unit both would
# go through the vendor NFTL, where Linux could never read them back --
# and the rootfs one would land on the physical tail of the chip that a
# NAND install gives to UBI.
#
# NAND units have their own package: scripts/make-nand-image.sh builds
# ws1508-nand.burn.img (bootloader + an Android boot.img holding the
# kernel), and the root filesystem is created on the box afterwards by
# ws1508-install-to-nand. See docs/flashing.md.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BURN_BASE="${OUTDIR}/uboot/burn-base"
IMAGES="${OUTDIR}/images"
TOOLS="${WORKDIR}/tools"

[[ -d "${BURN_BASE}" ]] || die "Missing ${BURN_BASE}. Run scripts/build-uboot.sh first."

DISKIMG="${1:-}"
if [[ -z "${DISKIMG}" ]]; then
	DISKIMG="$(ls "${IMAGES}"/*.img 2>/dev/null | grep -v '\.burn\.img$' | head -1 || true)"
fi
[[ -n "${DISKIMG}" && -f "${DISKIMG}" ]] || die "No Armbian .img found in ${IMAGES}. Run scripts/build-armbian.sh first."

command -v img2simg >/dev/null 2>&1 || die "img2simg not found. Install it: apt-get install -y android-sdk-libsparse-utils img2simg"
[[ "$(id -u)" -eq 0 ]] || die "This script needs root (it uses losetup)."

fetch_amlimg "${TOOLS}"
AMLIMG="${TOOLS}/AmlImg"

BURN="${WORKDIR}/burn"
rm -rf "${BURN}"
cp -r "${BURN_BASE}" "${BURN}"

log "Extracting partitions from $(basename "${DISKIMG}")"

# Attach each partition as its own loop device. The MBR parser and the
# loop-device helpers live in common.sh, which documents why they avoid
# `losetup --partscan`; make-nand-image.sh needs the same two.
declare -a LOOPS=()
trap release_loops EXIT

attach_part "${DISKIMG}" 1; BOOT_LOOP="${ATTACHED_LOOP}"
attach_part "${DISKIMG}" 2; ROOT_LOOP="${ATTACHED_LOOP}"
log "boot partition -> ${BOOT_LOOP}, root partition -> ${ROOT_LOOP}"

img2simg "${BOOT_LOOP}" "${BURN}/boot.simg"
img2simg "${ROOT_LOOP}" "${BURN}/rootfs.simg"

release_loops
trap - EXIT

printf 'sha1sum %s' "$(sha1sum "${BURN}/boot.simg"   | awk '{print $1}')" > "${BURN}/boot.VERIFY"
printf 'sha1sum %s' "$(sha1sum "${BURN}/rootfs.simg" | awk '{print $1}')" > "${BURN}/rootfs.VERIFY"

# AmlImg unpack writes a commands.txt describing the bootloader package;
# append our two partitions so the burning tool writes them too.
cat >> "${BURN}/commands.txt" <<-EOF
	PARTITION:boot:sparse:boot.simg
	VERIFY:boot:normal:boot.VERIFY
	PARTITION:rootfs:sparse:rootfs.simg
	VERIFY:rootfs:normal:rootfs.VERIFY
EOF

OUT="${DISKIMG%.img}.burn.img"
log "Packing ${OUT}"
"${AMLIMG}" pack "${OUT}" "${BURN}/"

# Round-trip the result: if it does not unpack cleanly it will not flash
# cleanly either, and a half-written bootloader is the one failure mode
# users cannot recover from without a serial cable.
VERIFY_DIR="${WORKDIR}/burn-verify"
rm -rf "${VERIFY_DIR}"
"${AMLIMG}" unpack "${OUT}" "${VERIFY_DIR}/" >/dev/null

# AmlImg names extracted members "<index>.<name>.<TYPE>", e.g. "0.DDR.USB";
# sparse partitions get a further ".sparse" suffix, so match either form.
for want in DDR.USB UBOOT_COMP.USB bootloader.PARTITION boot.PARTITION rootfs.PARTITION; do
	if ! compgen -G "${VERIFY_DIR}/*.${want}" > /dev/null \
	   && ! compgen -G "${VERIFY_DIR}/*.${want}.sparse" > /dev/null; then
		die "Packed burn image is missing ${want}"
	fi
done
rm -rf "${VERIFY_DIR}"

log "Burn image ready:"
ls -la "${OUT}"
