#!/usr/bin/env bash
# install-databricks-cli.sh - install a pinned Databricks CLI release for linux/amd64
# and verify its SHA-256 against the value recorded here (taken from the upstream
# databricks_cli_<version>_SHA256SUMS file) before placing it on PATH.
#
# Used by the Azure DevOps pipelines; GitHub Actions uses databricks/setup-cli.
#
# Usage: scripts/ci/install-databricks-cli.sh [INSTALL_DIR]
#   DATABRICKS_CLI_VERSION  override the version (requires DATABRICKS_CLI_SHA256 as well)
#   DATABRICKS_CLI_SHA256   expected sha256 of databricks_cli_<version>_linux_amd64.zip
set -euo pipefail

DEFAULT_VERSION="0.299.0"
DEFAULT_SHA256="ea7dd5fe7869489377010d00efed53778c882f112bbb31cfcfeb8d0e97ec0f52"

VERSION="${DATABRICKS_CLI_VERSION:-$DEFAULT_VERSION}"
SHA256="${DATABRICKS_CLI_SHA256:-}"
if [ -z "$SHA256" ]; then
  if [ "$VERSION" != "$DEFAULT_VERSION" ]; then
    echo "DATABRICKS_CLI_SHA256 must be set when overriding DATABRICKS_CLI_VERSION (${VERSION})." >&2
    exit 1
  fi
  SHA256="$DEFAULT_SHA256"
fi

INSTALL_DIR="${1:-/usr/local/bin}"
ARCHIVE="databricks_cli_${VERSION}_linux_amd64.zip"
URL="https://github.com/databricks/cli/releases/download/v${VERSION}/${ARCHIVE}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Databricks CLI v${VERSION} from ${URL}"
curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${ARCHIVE}" "$URL"
echo "${SHA256}  ${tmp}/${ARCHIVE}" | sha256sum --check --strict -

unzip -q -o "${tmp}/${ARCHIVE}" databricks -d "$tmp"
if [ -w "$INSTALL_DIR" ]; then
  install -m 0755 "${tmp}/databricks" "${INSTALL_DIR}/databricks"
else
  sudo install -m 0755 "${tmp}/databricks" "${INSTALL_DIR}/databricks"
fi

"${INSTALL_DIR}/databricks" --version
