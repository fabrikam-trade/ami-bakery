#!/usr/bin/env bash
# Scan the vendored Contoso agent bundle the way CI (and local verification)
# does it: grype against the assembled Linux payload directory, asserting
# the real log4net finding comes back.
#
# The Critical hit is GHSA-2cwj-8chv-9pp9 (CVE-2018-1285): XXE in log4net
# 1.2.10, detected from the DLL's own .NET assembly metadata -- no manifest
# needed. (PyYAML 3.13 also comes back real via its egg-info metadata --
# GHSA-rprw-h62v-c2w7 / CVE-2017-18342 -- and is asserted here too. OpenSSL
# does NOT come back from this scan: see README.md's "why grype doesn't
# find OpenSSL" note -- that component is detected by
# scripts/agent-inventory-scan.py instead, not by grype/syft.)
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="vendor/agent-linux/opt/contoso/agent"

OUT="$(grype "dir:${BUNDLE}" -o table 2>/dev/null)"
echo "$OUT"

echo
echo "-- flagged file --------------------------------------------------"
FLAGGED="$(find "${BUNDLE}" -name 'log4net.dll' | sed "s|^${BUNDLE}/||")"
echo "${FLAGGED:-(none -- bundle is clean)}"

echo
if echo "$OUT" | grep -q 'GHSA-2cwj-8chv-9pp9'; then
  echo 'CI check ok: log4net 1.2.10 flagged Critical (GHSA-2cwj-8chv-9pp9)'
else
  echo 'CI check FAILED: expected the log4net Critical finding' >&2
  exit 1
fi

if echo "$OUT" | grep -q 'GHSA-rprw-h62v-c2w7'; then
  echo 'CI check ok: PyYAML 3.13 flagged (GHSA-rprw-h62v-c2w7 / CVE-2017-18342)'
else
  echo 'CI check FAILED: expected the PyYAML finding' >&2
  exit 1
fi
