#!/usr/bin/env bash
#
# Shared configuration for the WS1508 Armbian build.
# Sourced by every script in this directory.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Where scratch checkouts and build output live. Override with WORKDIR=...
WORKDIR="${WORKDIR:-${REPO_ROOT}/work}"
OUTDIR="${OUTDIR:-${REPO_ROOT}/output}"
export WORKDIR OUTDIR

# ---------------------------------------------------------------------------
# Upstream sources. All pinned: an S805 bootloader is the one component a
# user cannot recover from over the network, so it must not drift silently.
# ---------------------------------------------------------------------------

# Amlogic vendor u-boot with the OneCloud (m8b) board support that our
# m8b_ws1508 board is derived from.
UBOOT_REPO="${UBOOT_REPO:-https://github.com/syb999/uboot-onecloud}"
UBOOT_COMMIT="${UBOOT_COMMIT:-04cebf40fb349a2bf7b59b4b6dc695abd5b00dcb}"

# hzyitc/AmlImg: packs and unpacks the Amlogic burn images that the
# USB Burning Tool consumes.
AMLIMG_VERSION="${AMLIMG_VERSION:-v0.3.1}"
AMLIMG_URL="${AMLIMG_URL:-https://github.com/hzyitc/AmlImg/releases/download/${AMLIMG_VERSION}/AmlImg_${AMLIMG_VERSION}_linux_amd64}"

# Armbian build framework.
ARMBIAN_REPO="${ARMBIAN_REPO:-https://github.com/armbian/build}"
ARMBIAN_REF="${ARMBIAN_REF:-main}"

# ---------------------------------------------------------------------------
# Image defaults
# ---------------------------------------------------------------------------
BOARD="${BOARD:-ws1508}"
BRANCH="${BRANCH:-current}"          # Armbian kernel branch (current = 6.12)
RELEASE="${RELEASE:-bookworm}"       # Debian/Ubuntu userland
BUILD_MINIMAL="${BUILD_MINIMAL:-no}"

export UBOOT_REPO UBOOT_COMMIT AMLIMG_VERSION AMLIMG_URL
export ARMBIAN_REPO ARMBIAN_REF BOARD BRANCH RELEASE BUILD_MINIMAL

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Fetch the AmlImg helper into $1 (a directory) if not already there.
fetch_amlimg() {
	local dest="${1}/AmlImg"
	if [[ -x "${dest}" ]]; then
		return 0
	fi
	mkdir -p "$(dirname "${dest}")"
	log "Fetching AmlImg ${AMLIMG_VERSION}"
	curl -fL --retry 3 --retry-delay 2 -o "${dest}" "${AMLIMG_URL}"
	chmod +x "${dest}"
}

# Shallow-clone $1 at commit $2 into directory $3, reusing an existing
# checkout when it is already at the right commit.
clone_pinned() {
	local url="$1" commit="$2" dir="$3"
	if [[ -d "${dir}/.git" ]] && [[ "$(git -C "${dir}" rev-parse HEAD 2>/dev/null || true)" == "${commit}" ]]; then
		log "Reusing ${dir} (already at ${commit:0:12})"
		return 0
	fi
	rm -rf "${dir}"
	mkdir -p "${dir}"
	log "Cloning ${url} @ ${commit:0:12}"
	git -C "${dir}" init -q
	git -C "${dir}" remote add origin "${url}"
	# Try to fetch just the pinned commit; fall back to a full fetch for
	# servers that do not allow fetching an arbitrary SHA.
	#
	# The two cases need different checkouts. After a single-commit fetch
	# FETCH_HEAD *is* the commit. After a bare "git fetch origin" it is the
	# remote's default-branch tip, which is emphatically not what we pinned
	# -- checking that out would silently build whatever upstream happens to
	# be at today, which for a bootloader is exactly the drift the pin
	# exists to prevent.
	if git -C "${dir}" fetch -q --depth 1 origin "${commit}" 2>/dev/null; then
		git -C "${dir}" checkout -q FETCH_HEAD
	else
		warn "Server refused single-commit fetch, falling back to a full fetch"
		git -C "${dir}" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
		git -C "${dir}" checkout -q "${commit}"
	fi

	local got
	got="$(git -C "${dir}" rev-parse HEAD)"
	[[ "${got}" == "${commit}" ]] \
		|| die "Checked out ${got} but expected the pinned ${commit} in ${dir}"
}

# ---------------------------------------------------------------------------
# Reading partitions out of a built Armbian .img
#
# Factored out of make-burn-image.sh so make-nand-image.sh can reuse it.
# ---------------------------------------------------------------------------

SECTOR=512

# "<start_lba> <sectors>" for partition $2 (1-based) of the image $1.
#
# The table is parsed here rather than shelled out to sfdisk/parted so the
# scripts have no dependency beyond losetup and python3. Armbian writes a
# plain MBR for this board.
part_geometry() {
	python3 - "$1" "$2" <<-'PY'
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

# Every loop device attached by attach_part, so a trap can release them.
declare -a LOOPS=()
release_loops() {
	local l
	for l in "${LOOPS[@]:-}"; do
		[[ -n "${l}" ]] && losetup -d "${l}" 2>/dev/null || true
	done
	LOOPS=()
}

# Attach partition $2 of image $1 and set ATTACHED_LOOP to the device.
#
# Deliberately NOT "echo the device and capture it with $(...)": command
# substitution runs in a subshell, so the LOOPS+=() inside would be lost and
# the cleanup trap would have nothing to release -- the loop devices would
# leak on every failure until the host runs out of them.
#
# Attaching each partition with an explicit offset and size also avoids
# relying on `losetup --partscan` to spawn /dev/loopNpM nodes. Those nodes
# are created by udev, which is frequently absent inside build containers.
ATTACHED_LOOP=""
attach_part() {
	local img="$1" n="$2" geom start size
	geom="$(part_geometry "${img}" "${n}")" \
		|| die "Cannot read partition ${n} of ${img}: ${geom}"
	start="${geom% *}"
	size="${geom#* }"
	ATTACHED_LOOP="$(losetup --find --show \
		--offset "$((start * SECTOR))" --sizelimit "$((size * SECTOR))" "${img}")"
	LOOPS+=("${ATTACHED_LOOP}")
}
