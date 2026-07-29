#!/usr/bin/env python3
"""agent-inventory-scan.py -- stand-in for the Contoso monitoring agent's
own vendor-bundle inventory scan ("vendor-bundle file-hash + version
match" per the combined-backlog generator's detection_method field).

This is NOT grype/syft: syft's binary classifiers only recognize a
library named exactly `openssl` (see ami-bakery/README.md's "why grype
doesn't find OpenSSL" note), so the OpenSSL component in this bundle is
only detectable by the same mechanism the real Contoso agent would use --
reading the component's own version banner off disk and matching it
against a small local advisory table. That's what this script does, for
all three vendored components, so the host-agent findings can be produced
by *something real* rather than only asserted in JSON.

Usage:
    # Local verification against the vendored payload (no AWS needed):
    python3 scripts/agent-inventory-scan.py \\
        --root vendor/agent-linux/opt/contoso/agent --os linux \\
        --asset-id ami-0f4b2a91cd8e7f103 --asset-name trade-base-golden \\
        --asset-role "golden-image (pre-launch AMI scan, ami-bakery trade-base)"

    # Live use (once step-3 AWS lands): invoked on-instance via
    # `aws ssm send-command --document-name AWS-RunShellScript`, pointed at
    # the real /opt/contoso/agent root, output captured and fed into
    # _backlog-generator/scripts/merge_findings.py in place of the
    # SYNTHESIZED host_agent_findings block.

Output: JSON array of records in the exact schema
_backlog-generator/scripts/merge_findings.py::build_host_agent_findings()
produces, EXCEPT source says "contoso-agent-inventory-v1.0" (a real scan)
instead of the synthesized marker, and there is no "_synthesized" field.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# Advisory table: same real, correctly-paired CVE/GHSA ids as
# _backlog-generator/scripts/merge_findings.py::VENDOR_COMPONENTS. Kept as
# a separate literal table (not imported) because this script runs
# standalone on a host with no access to the Burndown-side generator repo.
ADVISORY_TABLE = {
    "log4net": {
        "cve_ref": "GHSA-2cwj-8chv-9pp9",
        "risk_level": "CRITICAL",
        "risk_score": 9.8,
        "expected_version": "1.2.10",
    },
    "openssl": {
        "cve_ref": "CVE-2014-0160",
        "risk_level": "Critical",
        "risk_score": 9.4,
        "expected_version": "1.0.1e",
    },
    "pyyaml": {
        "cve_ref": "CVE-2017-18342",
        "risk_level": "High",
        "risk_score": 7.5,
        "expected_version": "3.13",
    },
}

REL_PATHS = {
    "linux": {
        "log4net": "lib/log4net.dll",
        "openssl": "lib/libssl.so.1.0.0",
        "pyyaml": "collector/vendor/yaml/__init__.py",
    },
    "windows": {
        "log4net": "lib\\log4net.dll",
        "openssl": "lib\\ssleay32.dll",
        "pyyaml": "collector\\vendor\\yaml\\__init__.py",
    },
}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def detect_log4net_version(data: bytes) -> str | None:
    """.NET assembly version metadata is stored as UTF-16LE strings in the
    DLL; the real log4net 1.2.10 build carries '1.2.10.0' in its metadata
    stream (the same string grype's dotnet cataloger reads)."""
    m = re.search(rb"1\.2\.10\.0", data)
    return "1.2.10" if m else None


def detect_openssl_version(data: bytes) -> str | None:
    """Real OpenSSL binaries (and this bundle's version-metadata stub)
    embed the SSLeay_version() banner: 'OpenSSL 1.0.1e 11 Feb 2013'."""
    m = re.search(rb"OpenSSL (\d+\.\d+\.\d+[a-z]?)", data)
    return m.group(1).decode("ascii") if m else None


def detect_pyyaml_version(data: bytes) -> str | None:
    """Real PyYAML __init__.py declares __version__ = '3.13' directly."""
    m = re.search(rb"__version__\s*=\s*['\"]([0-9.]+)['\"]", data)
    return m.group(1).decode("ascii") if m else None


DETECTORS = {
    "log4net": detect_log4net_version,
    "openssl": detect_openssl_version,
    "pyyaml": detect_pyyaml_version,
}


def scan(root: Path, os_name: str, asset_id: str, asset_name: str, asset_role: str, scan_date: str):
    records = []
    seq = 0
    for component, rel in REL_PATHS[os_name].items():
        path = root / rel.replace("\\", "/")
        advisory = ADVISORY_TABLE[component]
        if not path.exists():
            print(f"[warn] {component}: expected path missing: {path}", file=sys.stderr)
            continue

        data = path.read_bytes()
        detected_version = DETECTORS[component](data)
        if detected_version is None:
            print(f"[warn] {component}: version banner not found in {path}, skipping (no match, no finding)", file=sys.stderr)
            continue
        if detected_version != advisory["expected_version"]:
            print(f"[warn] {component}: detected version {detected_version} != known-vulnerable {advisory['expected_version']}, skipping", file=sys.stderr)
            continue

        seq += 1
        component_path = str(rel) if os_name == "linux" else rel
        # Present the path the way each OS's own tooling would show it.
        full_path = ("/" + rel) if os_name == "linux" else (f"C:\\Program Files\\Contoso\\Agent\\{rel}")
        records.append({
            "signature_id": f"CTSO-EDR-{seq:04d}",
            "asset_id": asset_id,
            "asset_name": asset_name,
            "asset_role": asset_role,
            "component_path": full_path,
            "component_name": component if component != "openssl" else "OpenSSL",
            "component_version": detected_version,
            "cve_ref": advisory["cve_ref"],
            "risk_level": advisory["risk_level"],
            "risk_score": advisory["risk_score"],
            "detection_method": "vendor-bundle file-hash + version match",
            "file_sha256": sha256_of(path),
            "source": "contoso-agent-inventory-v1.0",
            "scan_date": scan_date,
        })
    return records


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", required=True, type=Path, help="agent bundle root (e.g. /opt/contoso/agent, or the vendor/agent-linux/... payload dir for local verification)")
    ap.add_argument("--os", required=True, choices=["linux", "windows"])
    ap.add_argument("--asset-id", required=True)
    ap.add_argument("--asset-name", required=True)
    ap.add_argument("--asset-role", required=True)
    ap.add_argument("--scan-date", default=datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    ap.add_argument("-o", "--output", type=Path, default=None, help="write JSON here instead of stdout")
    args = ap.parse_args()

    if not args.root.is_dir():
        print(f"error: --root {args.root} is not a directory", file=sys.stderr)
        sys.exit(2)

    records = scan(args.root, args.os, args.asset_id, args.asset_name, args.asset_role, args.scan_date)
    out = json.dumps(records, indent=2)
    if args.output:
        args.output.write_text(out + "\n")
        print(f"wrote {len(records)} record(s) to {args.output}", file=sys.stderr)
    else:
        print(out)

    if not records:
        sys.exit(1)


if __name__ == "__main__":
    main()
