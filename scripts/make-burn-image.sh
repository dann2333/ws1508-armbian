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
# NOTE: writing boot+rootfs to internal storage only produces a bootable
# system on eMMC units. Nothing here can root a raw-NAND unit off its
# internal flash: the partitions this writes are the vendor bootloader's,
# in a layout only its own NFTL understands, and neither u-boot nor Linux
# has a filesystem on top of it. (Not a hardware limit - see README - but
# it is not something this packer can paper over.) NAND users should flash
# the bootloader-only package, ws1508-uboot.burn.img, and boot from USB.

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

# Read the partition table and attach each partition as its own loop device
# with an explicit offset and size, instead of relying on `losetup
# --partscan` to spawn /dev/loopNpM nodes. Those nodes are created by udev,
# which is frequently absent inside build containers -- and when it is, a
# --partscan loop silently yields no partition devices at all.
#
# The table is parsed here rather than shelled out to sfdisk/parted so the
# script has no dependency beyond losetup and python3. Armbian writes a
# plain MBR for this board.
part_geometry() { # -> "<start_lba> <sectors>" for partition $1 (1-based)
	python3 - "${DISKIMG}" "$1" <<-'PY'
		import struct, sys
		img, want = sys.argv[1], int(sys.argv[2])
		with open(img, 'rb') as f:
		    mbr = f.read(512)
		if len(mbr) < 512 or mbr[510:512] != b'\x55\xaa':
		    sys.exit("not an MBR-partitioned image")
		entries = []
		for i in range(4):
		    e = mbr[446 + i * 16: 446 + (i + 1) * 16]
		    ptype = e[4]
		    start, sectors = struct.unpack_from('<II', e, 8)
		    if ptype != 0 and sectors:
		        entries.append((start, sectors))
		if len(entries) < want:
		    sys.exit(f"image has {len(entries)} partition(s); wanted #{want}")
		print("%d %d" % entries[want - 1])
	PY
}

SECTOR=512
declare -a LOOPS=()
cleanup() { for l in "${LOOPS[@]:-}"; do [[ -n "${l}" ]] && losetup -d "${l}" 2>/dev/null || true; done; }
trap cleanup EXIT

# Sets ATTACHED_LOOP. Deliberately NOT "echo the device and capture it with
# $(...)": command substitution runs in a subshell, so the LOOPS+=() inside
# would be lost and the cleanup trap would have nothing to release -- the
# loop devices would leak on every failure until the host runs out of them.
ATTACHED_LOOP=""
attach_part() { # $1 = partition number
	local n="$1" geom start size
	geom="$(part_geometry "${n}")" || die "Cannot read partition ${n} of ${DISKIMG}: ${geom}"
	start="${geom% *}"
	size="${geom#* }"
	ATTACHED_LOOP="$(losetup --find --show --offset "$((start * SECTOR))" --sizelimit "$((size * SECTOR))" "${DISKIMG}")"
	LOOPS+=("${ATTACHED_LOOP}")
}

attach_part 1; BOOT_LOOP="${ATTACHED_LOOP}"
attach_part 2; ROOT_LOOP="${ATTACHED_LOOP}"
log "boot partition -> ${BOOT_LOOP}, root partition -> ${ROOT_LOOP}"

img2simg "${BOOT_LOOP}" "${BURN}/boot.simg"
img2simg "${ROOT_LOOP}" "${BURN}/rootfs.simg"

cleanup
LOOPS=()
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
