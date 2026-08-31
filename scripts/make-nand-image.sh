#!/usr/bin/env bash
#
# Pack the kernel side of a NAND boot for the Xunlei WS1508.
#
# Produces, in $OUTDIR/nand/:
#   ws1508-nand-boot.andr   an Android boot.img holding uImage + initrd + dtb.
#                           This is what goes into the vendor "boot" partition
#                           and what "imgread kernel boot" reads at boot time.
#   ws1508-nand.burn.img    a burn package = bootloader + that boot.img, for
#                           installing the kernel side with the USB Burning
#                           Tool in one shot.
#
# It does NOT produce a root filesystem. That is not an omission; a UBIFS
# image can only be built for a known page size, erase block size and LEB
# size, and the fitted die is a Xunlei house-marked part whose geometry is
# not published anywhere. The rootfs is therefore created on the box by
# ws1508-install-to-nand: ubiformat, ubiattach and ubimkvol on the MTD
# partition labelled "ubi", then "mount -t ubifs" (which formats an empty
# volume on a read-write mount, fs/ubifs/super.c:1283) and rsync of the
# running system into it. UBI and UBIFS take the geometry from the device
# itself, which is the whole reason no image can be built here.
#
# WHY AN ANDROID BOOT.IMG, of all things:
#
# This bootloader has no filesystem layer over NAND at all -- CONFIG_NEXT_NAND
# drops libmtd.o and libnand.o from LIBS (the top-level Makefile:216-220, and
# 228-232 substitutes the amlnf libraries) -- so there is nothing to fatload
# from. What it does have is "imgread kernel <part> <addr>", which reads an
# Android boot.img out of a vendor partition: a fixed IMG_PRELOAD_SZ of 1MiB
# first (common/cmd_imgread.c:20, :321), then the rest sized from the header
# at :342-345 -- header page + page-aligned kernel + page-aligned ramdisk +
# second_size. And it has a bootm that understands the format, which takes
# all three pieces out of that single image:
#
#   kernel   a legacy uImage at +0x800   (cmd_bootm.c:1108-1110)
#   ramdisk  at align(0x800 + kernel_size, page_size), length ramdisk_size,
#            handed to Linux as raw bytes -- so this slot holds the BARE
#            initrd.img, not the mkimage-wrapped uInitrd (cmd_bootm.c:302-305)
#   dtb      at align(rd_end, page_size), length second_size, passed through
#            get_multi_dt_entry() which returns a plain dtb unchanged
#            (cmd_bootm.c:307-318, common/aml_dt.c:29-32)
#
# So one "imgread" plus one "bootm", and no offsets hard-coded in the boot
# environment. The header is written here rather than shelled out to
# mkbootimg so the build gains no host dependency and the result is
# byte-reproducible.
#
# NOTE the page size must be exactly 2048: bootm finds the kernel with a
# hard-coded "+ 0x800" rather than by reading page_size out of the header.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BURN_BASE="${OUTDIR}/uboot/burn-base"
IMAGES="${OUTDIR}/images"
NANDOUT="${OUTDIR}/nand"
TOOLS="${WORKDIR}/tools"

DTB_NAME="meson8b-ws1508-nand.dtb"
PAGE_SIZE=2048

DISKIMG="${1:-}"
if [[ -z "${DISKIMG}" ]]; then
	DISKIMG="$(ls "${IMAGES}"/*.img 2>/dev/null | grep -v '\.burn\.img$' | head -1 || true)"
fi
[[ -n "${DISKIMG}" && -f "${DISKIMG}" ]] \
	|| die "No Armbian .img found in ${IMAGES}. Run scripts/build-armbian.sh first."
[[ "$(id -u)" -eq 0 ]] || die "This script needs root (it uses losetup and mount)."

mkdir -p "${NANDOUT}"
STAGE="${WORKDIR}/nand-stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"

# ---------------------------------------------------------------------------
# Pull the three pieces out of the built image's FAT boot partition.
# ---------------------------------------------------------------------------
declare -a LOOPS=()
MNT=""
cleanup() {
	[[ -n "${MNT}" ]] && mountpoint -q "${MNT}" && umount "${MNT}" || true
	release_loops
}
trap cleanup EXIT

log "Extracting boot files from $(basename "${DISKIMG}")"
attach_part "${DISKIMG}" 1
MNT="${STAGE}/boot"
mkdir -p "${MNT}"
mount -o ro "${ATTACHED_LOOP}" "${MNT}"

[[ -f "${MNT}/uImage" ]] || die "No /uImage in the boot partition."
[[ -f "${MNT}/dtb/${DTB_NAME}" ]] \
	|| die "No /dtb/${DTB_NAME} in the boot partition. Did the NAND dts get built?"

# The BARE initrd, not uInitrd: bootm hands these bytes straight to Linux
# without unwrapping a mkimage header. Armbian's initramfs hook leaves both
# in /boot, so pick the versioned one and refuse to guess if there is more
# than one kernel installed.
mapfile -t INITRDS < <(find "${MNT}" -maxdepth 1 -name 'initrd.img-*' -printf '%f\n' | sort)
case "${#INITRDS[@]}" in
	0) die "No /initrd.img-* in the boot partition." ;;
	1) : ;;
	*) die "Found ${#INITRDS[@]} initrd.img-* files (${INITRDS[*]}); expected exactly one." ;;
esac

cp "${MNT}/uImage"                "${STAGE}/kernel"
cp "${MNT}/${INITRDS[0]}"         "${STAGE}/ramdisk"
cp "${MNT}/dtb/${DTB_NAME}"       "${STAGE}/second"
umount "${MNT}"; MNT=""
release_loops
trap - EXIT

log "kernel=$(stat -c%s "${STAGE}/kernel") ramdisk=$(stat -c%s "${STAGE}/ramdisk") dtb=$(stat -c%s "${STAGE}/second") bytes"

# ---------------------------------------------------------------------------
# Assemble the Android boot.img.
# ---------------------------------------------------------------------------
ANDR="${NANDOUT}/ws1508-nand-boot.andr"
python3 - "${STAGE}/kernel" "${STAGE}/ramdisk" "${STAGE}/second" "${ANDR}" "${PAGE_SIZE}" <<'PY'
import struct, sys

kernel_p, ramdisk_p, second_p, out_p, page = sys.argv[1:5] + [int(sys.argv[5])]
blobs = [open(p, 'rb').read() for p in (kernel_p, ramdisk_p, second_p)]
kernel, ramdisk, second = blobs

# bootm locates the kernel with a hard-coded "+ 0x800" (cmd_bootm.c:1110),
# so a header page of any other size would put the uImage where it does not
# look. Refuse rather than produce an image that fails on the box.
if page != 0x800:
    sys.exit("page size must be 2048: bootm hard-codes +0x800 to reach the kernel")

# The kernel slot must be a legacy uImage. bootm shifts past the Android
# header and calls image_get_kernel() on what it finds; a bad magic there
# prints "Bad Magic Number" (cmd_bootm.c:967) and then "ERROR: can't get
# kernel image!" (cmd_bootm.c:246). Fail here instead, where the file is.
if kernel[:4] != b'\x27\x05\x19\x56':
    sys.exit("kernel is not a legacy uImage (bad magic); bootm cannot find an entry point")

# The dtb goes in the "second" slot and reaches Linux through
# get_multi_dt_entry(), which returns a plain dtb unchanged only if it starts
# with the flattened-devicetree magic (common/aml_dt.c:29-32).
if second[:4] != b'\xd0\x0d\xfe\xed':
    sys.exit("second stage is not a flattened device tree (bad magic)")

# A mkimage-wrapped uInitrd here would be handed to Linux with its 64-byte
# u-boot header still on the front, and the kernel would reject the cpio.
if ramdisk[:4] == b'\x27\x05\x19\x56':
    sys.exit("ramdisk is a uInitrd; bootm does not unwrap it -- use the bare initrd.img")

def pad(b):
    return b + b'\x00' * (-len(b) % page)

# struct boot_img_hdr, header version 0. The load addresses are recorded
# because the format has the fields, but nothing reads them: bootm takes the
# load address and entry point from the uImage header instead.
hdr = b'ANDROID!'
hdr += struct.pack('<10I',
                   len(kernel),  0x00208000,          # kernel size, addr
                   len(ramdisk), 0x02000000,          # ramdisk size, addr
                   len(second),  0x00f00000,          # second (dtb) size, addr
                   0x00000100,                        # tags addr
                   page,
                   0, 0)                              # header_version, os_version
hdr += b'ws1508'.ljust(16, b'\x00')                   # name
hdr += b''.ljust(512, b'\x00')                        # cmdline: unused, bootargs
                                                      # come from the u-boot env
hdr += struct.pack('<8I', *([0] * 8))                 # id: unused by this bootm

with open(out_p, 'wb') as f:
    f.write(pad(hdr))
    f.write(pad(kernel))
    f.write(pad(ramdisk))
    f.write(pad(second))
PY

log "Wrote $(basename "${ANDR}") ($(stat -c%s "${ANDR}") bytes)"

# Two ceilings, and the lower one is RAM, not flash. The vendor "boot"
# partition is 256MiB (uboot/m8b_ws1508/firmware/storage.c) less the NFTL
# spare, but "imgread kernel boot" loads the whole image at 0x16000000 and
# this board has 512MiB of DRAM starting at 0, so only 0x20000000-0x16000000
# = 160MiB is addressable above the load address. Past that the read walks
# off the end of the mapping -- and update_ddr_mmu_table() zeroes the
# descriptors beyond the detected size, so it faults rather than wrapping.
# 128MiB leaves a margin under that.
ANDR_MAX=$((128 * 1024 * 1024))
ANDR_SIZE="$(stat -c%s "${ANDR}")"
if (( ANDR_SIZE > ANDR_MAX )); then
	die "${ANDR} is ${ANDR_SIZE} bytes, over the ${ANDR_MAX}-byte limit. That limit is
DRAM above the 0x16000000 load address, not the size of the vendor partition."
fi

# ---------------------------------------------------------------------------
# Wrap it in a burn package so the USB Burning Tool can install it.
# ---------------------------------------------------------------------------
if [[ -d "${BURN_BASE}" ]]; then
	fetch_amlimg "${TOOLS}"
	AMLIMG="${TOOLS}/AmlImg"

	BURN="${WORKDIR}/burn-nand"
	rm -rf "${BURN}"
	cp -r "${BURN_BASE}" "${BURN}"
	cp "${ANDR}" "${BURN}/boot.andr"
	printf 'sha1sum %s' "$(sha1sum "${BURN}/boot.andr" | awk '{print $1}')" > "${BURN}/boot.VERIFY"

	# "normal", not "sparse": this is a flat image, not a filesystem.
	# The burning tool writes PARTITION items by name through store_write_ops,
	# which on a NAND unit is the same NFTL path "imgread kernel boot" reads
	# back (drivers/usb/gadget/v2_burning/v2_common/optimus_download.c:274).
	#
	# Note there is deliberately NO rootfs item here. Writing one would send
	# an ext4 image through NFTL, where Linux could never read it back, and
	# it would land on the physical tail of the chip that the UBI rootfs
	# owns.
	cat >> "${BURN}/commands.txt" <<-EOF
		PARTITION:boot:normal:boot.andr
		VERIFY:boot:normal:boot.VERIFY
	EOF

	NAND_BURN="${NANDOUT}/ws1508-nand.burn.img"
	log "Packing $(basename "${NAND_BURN}")"
	"${AMLIMG}" pack "${NAND_BURN}" "${BURN}/"

	# Round-trip the result, exactly as make-burn-image.sh does. This package
	# carries the bootloader, and a half-written bootloader on a NAND unit is
	# the one failure mode a user cannot recover from without a serial cable.
	# It also catches a truncated burn-base, which on CI arrives over
	# actions/download-artifact and is not otherwise checked here.
	VERIFY_DIR="${WORKDIR}/burn-nand-verify"
	rm -rf "${VERIFY_DIR}"
	"${AMLIMG}" unpack "${NAND_BURN}" "${VERIFY_DIR}/" >/dev/null

	# AmlImg names extracted members "<index>.<name>.<TYPE>", e.g. "0.DDR.USB".
	for want in DDR.USB UBOOT_COMP.USB bootloader.PARTITION boot.PARTITION; do
		if ! compgen -G "${VERIFY_DIR}/*.${want}" > /dev/null \
		   && ! compgen -G "${VERIFY_DIR}/*.${want}.sparse" > /dev/null; then
			die "Packed NAND burn image is missing ${want}"
		fi
	done
	rm -rf "${VERIFY_DIR}"

	log "Wrote ${NAND_BURN}"
else
	warn "No ${BURN_BASE}; skipping the burn package. Run scripts/build-uboot.sh to get one."
fi

log "Done. The root filesystem is created on the box by ws1508-install-to-nand."
