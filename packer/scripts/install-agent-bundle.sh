#!/usr/bin/env bash
# install-agent-bundle.sh -- image-bake step that lays down the Contoso
# monitoring agent bundle on trade-base (Amazon Linux 2).
#
# Run by Packer; also runs standalone in CI and local tests against any
# target root. Mirrors the layout scripts/agent-inventory-scan.py and the
# Fabrikam combined-backlog generator both hardcode:
#
#   /opt/contoso/agent/lib/log4net.dll
#   /opt/contoso/agent/lib/libssl.so.1.0.0
#   /opt/contoso/agent/collector/vendor/yaml/__init__.py
#
# Usage: install-agent-bundle.sh <source-dir> <dest-root>
#   source-dir  vendor/agent-linux/opt/contoso/agent (the payload tree)
#   dest-root   /opt/contoso/agent (or a test root's equivalent)
set -euo pipefail

SOURCE="${1:?usage: install-agent-bundle.sh <source-dir> <dest-root>}"
DEST="${2:?usage: install-agent-bundle.sh <source-dir> <dest-root>}"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
chmod -R go-w "$DEST"

echo "installed Contoso agent bundle to $DEST"
find "$DEST" -type f | sed "s|^$DEST|  |"
