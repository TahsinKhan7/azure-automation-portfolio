#!/usr/bin/env bash
# install-kubeconform.sh - install a pinned kubeconform release for linux/amd64 and
# verify its SHA-256 against the value recorded here (taken from the upstream
# CHECKSUMS file for that release) before placing it on PATH.
#
# Usage: scripts/ci/install-kubeconform.sh [INSTALL_DIR]
#   KUBECONFORM_VERSION  override the version (requires KUBECONFORM_SHA256 as well)
#   KUBECONFORM_SHA256   expected sha256 of kubeconform-linux-amd64.tar.gz
set -euo pipefail

DEFAULT_VERSION="0.7.0"
DEFAULT_SHA256="c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3"

VERSION="${KUBECONFORM_VERSION:-$DEFAULT_VERSION}"
SHA256="${KUBECONFORM_SHA256:-}"
if [ -z "$SHA256" ]; then
  if [ "$VERSION" != "$DEFAULT_VERSION" ]; then
    echo "KUBECONFORM_SHA256 must be set when overriding KUBECONFORM_VERSION (${VERSION})." >&2
    exit 1
  fi
  SHA256="$DEFAULT_SHA256"
fi

INSTALL_DIR="${1:-/usr/local/bin}"
ARCHIVE="kubeconform-linux-amd64.tar.gz"
URL="https://github.com/yannh/kubeconform/releases/download/v${VERSION}/${ARCHIVE}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading kubeconform v${VERSION} from ${URL}"
curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${ARCHIVE}" "$URL"
echo "${SHA256}  ${tmp}/${ARCHIVE}" | sha256sum --check --strict -

tar -xzf "${tmp}/${ARCHIVE}" -C "$tmp" kubeconform
if [ -w "$INSTALL_DIR" ]; then
  install -m 0755 "${tmp}/kubeconform" "${INSTALL_DIR}/kubeconform"
else
  sudo install -m 0755 "${tmp}/kubeconform" "${INSTALL_DIR}/kubeconform"
fi

"${INSTALL_DIR}/kubeconform" -v
