#!/usr/bin/env bash
# Build .deb packages for the IT-DW Caddy binaries.
#
# Usage:
#   scripts/build-deb.sh <version> <out-dir>
#
# Expects in the current working directory (repo root after build):
#   caddy-linux-amd64, caddy-linux-arm64
#   cert-sanity-amd64, cert-sanity-arm64
#
# Version should be a Debian-legal version string without architecture,
# e.g. 2.11.2+itdw.42
set -euo pipefail

VERSION="${1:?version required}"
OUT_DIR="${2:?output directory required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_SRC="${ROOT}/packaging"

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

# Caddy stores certs under ${XDG_DATA_HOME}/caddy/certificates when
# XDG_DATA_HOME=/var/lib/caddy — that is /var/lib/caddy/caddy/certificates.
build_one() {
	local arch="$1"
	local caddy_bin="caddy-linux-${arch}"
	local sanity_bin="cert-sanity-${arch}"

	if [[ ! -f ${caddy_bin} ]]; then
		echo "missing ${caddy_bin}" >&2
		return 1
	fi
	if [[ ! -f ${sanity_bin} ]]; then
		echo "missing ${sanity_bin}" >&2
		return 1
	fi

	local work root deb
	work="$(mktemp -d)"
	root="${work}/pkg"
	mkdir -p \
		"${root}/DEBIAN" \
		"${root}/usr/bin" \
		"${root}/lib/systemd/system" \
		"${root}/etc/caddy/sites-enabled" \
		"${root}/var/lib/caddy" \
		"${root}/var/log/caddy" \
		"${root}/usr/share/doc/caddy"

	install -m 0755 "${caddy_bin}" "${root}/usr/bin/caddy"
	install -m 0755 "${sanity_bin}" "${root}/usr/bin/cert-sanity"
	install -m 0644 "${PKG_SRC}/caddy.service" "${root}/lib/systemd/system/caddy.service"
	install -m 0644 "${PKG_SRC}/caddy-api.service" "${root}/lib/systemd/system/caddy-api.service"
	install -m 0644 "${PKG_SRC}/Caddyfile" "${root}/etc/caddy/Caddyfile"
	install -m 0644 "${ROOT}/LICENSE" "${root}/usr/share/doc/caddy/copyright"

	sed -e "s/{{VERSION}}/${VERSION}/g" \
		-e "s/{{ARCH}}/${arch}/g" \
		"${PKG_SRC}/debian/control" >"${root}/DEBIAN/control"

	install -m 0644 "${PKG_SRC}/debian/conffiles" "${root}/DEBIAN/conffiles"
	install -m 0755 "${PKG_SRC}/debian/postinst" "${root}/DEBIAN/postinst"
	install -m 0755 "${PKG_SRC}/debian/prerm" "${root}/DEBIAN/prerm"
	install -m 0755 "${PKG_SRC}/debian/postrm" "${root}/DEBIAN/postrm"

	# postinst chowns /var/lib/caddy and /var/log/caddy to the caddy user.

	deb="caddy_${VERSION}_${arch}.deb"
	dpkg-deb --root-owner-group --build "${root}" "${OUT_DIR}/${deb}"
	rm -rf "${work}"
	echo "built ${OUT_DIR}/${deb}"
}

for arch in amd64 arm64; do
	build_one "${arch}"
done
