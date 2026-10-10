#!/usr/bin/env bash
#
# Lay the WS1508 board packages out as a flat apt repository, ready to be
# attached to a GitHub release.
#
# Input:   $OUTDIR/debs/*.deb    copied out of Armbian by build-armbian.sh
# Output:  $OUTDIR/apt/          the packages below, Packages, Packages.gz,
#                                Release, and ws1508-apt-setup.sh
#
# Boxes in the field point apt at
#
#   https://github.com/dann2333/ws1508-armbian/releases/latest/download/
#
# (ws1508-apt-setup writes that source). GitHub answers any name under that
# path with a redirect to the same name in the newest release, so every
# release is a complete repository snapshot and "latest" moves with it.
# Missing names come back 404, which is what apt expects for the InRelease
# and Release.gpg it asks for first: the repository is unsigned, and the
# source says Trusted: yes.
#
# Only what is specific to this board goes in -- the kernel, its device
# trees and headers, and the board-support package. Everything else on the
# box keeps coming from Debian/Ubuntu and Armbian's own repository. The
# kernel packages share their names with Armbian's builds for the same
# family, which lack the WS1508 device trees; the pin ws1508-apt-setup
# installs keeps those off.
#
# For apt to see a release as an upgrade, each one has to carry a higher
# version than the last. build-armbian.sh takes care of that by appending a
# build stamp to REVISION; this script refuses packages that still carry
# Armbian's bare VERSION, so a build that bypassed it cannot publish a
# repository that silently offers nothing new.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEBS="${OUTDIR}/debs"
APTDIR="${OUTDIR}/apt"

command -v apt-ftparchive >/dev/null 2>&1 || die "apt-ftparchive not found (apt-get install -y apt-utils)."
command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found."
[[ -d "${DEBS}" ]] || die "No ${DEBS}. Run scripts/build-armbian.sh first."

rm -rf "${APTDIR}"
mkdir -p "${APTDIR}"

declare -A seen=()
shopt -s nullglob
for deb in "${DEBS}"/*.deb; do
	pkg="$(dpkg-deb -f "${deb}" Package)"
	case "${pkg}" in
		linux-image-*-meson | linux-dtb-*-meson | linux-headers-*-meson | armbian-bsp-cli-ws1508*) ;;
		*) continue ;;
	esac
	ver="$(dpkg-deb -f "${deb}" Version)"
	arch="$(dpkg-deb -f "${deb}" Architecture)"

	[[ -z "${seen[${pkg}]:-}" ]] || die "Two builds of ${pkg} in ${DEBS} (${seen[${pkg}]} and ${ver}); refusing to guess."
	seen[${pkg}]="${ver}"

	case "${ver}" in
		*.ws1508.*) ;;
		*) die "${pkg} has version '${ver}', without the per-build stamp build-armbian.sh adds.
Installed boxes would not see it as an upgrade. Rebuild through scripts/build-armbian.sh." ;;
	esac

	# GitHub rewrites release-asset names outside this set, and the index
	# has to name exactly what gets uploaded.
	name="${pkg}_${ver}_${arch}.deb"
	[[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || die "'${name}' would be renamed by GitHub on upload."

	cp -a "${deb}" "${APTDIR}/${name}"
	log "  ${name}"
done
shopt -u nullglob

for want in linux-image linux-dtb armbian-bsp-cli-ws1508; do
	found=no
	for pkg in "${!seen[@]}"; do
		[[ "${pkg}" == "${want}"* ]] && found=yes
	done
	[[ "${found}" == yes ]] || die "No ${want} package in ${DEBS}; the repository would be incomplete."
done

cd "${APTDIR}"

# apt resolves Filename against the source URI. apt-ftparchive writes it
# as "./name"; strip that so every request is a plain name under the
# release's download path.
apt-ftparchive packages . > Packages
sed -i 's|^Filename: \./|Filename: |' Packages
gzip -9nk Packages

# No Suite or Codename: apt does not need them for a flat repository, and
# leaving them out means nothing can disagree with the "./" in the source.
# Origin is what the pin's counterpart would key on, and it must not be
# "Armbian".
apt-ftparchive \
	-o APT::FTPArchive::Release::Origin="ws1508-armbian" \
	-o APT::FTPArchive::Release::Label="ws1508-armbian" \
	-o APT::FTPArchive::Release::Description="Xunlei WS1508 kernel, device trees and board support (github.com/dann2333/ws1508-armbian)" \
	release . > "${WORKDIR}/Release.ws1508.tmp"
mv "${WORKDIR}/Release.ws1508.tmp" Release

install -m 0755 "${REPO_ROOT}/userpatches/overlay/ws1508-apt-setup" ws1508-apt-setup.sh

log "apt repository in ${APTDIR}:"
ls -la
grep -E '^(Package|Version|Filename):' Packages | paste - - -
