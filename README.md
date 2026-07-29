# ami-bakery

Packer templates for the Trade golden AMIs.

- `trade-base` — Amazon Linux 2 base + hardening baseline + the Contoso monitoring
  agent bundle
- `trade-windows` — Windows Server 2019 for the ledger settlement host

Bake cadence is "when someone remembers" (target: monthly). Output AMIs are shared to
prod and published to SSM under `/fabrikam/ami/`.

The Contoso agent bundle is vendored in `vendor/` at the version Contoso support sent
in 2021. Newer bundles broke the ledger host's export drive mapping, so the vendored
copy is load-bearing — every AMI carries it, and every host inherits whatever is in it.

## Layout

```
vendor/
  agent-linux/opt/contoso/agent/...              payload for trade-base, laid down at /opt/contoso/agent
  agent-windows/Program Files/Contoso/Agent/...   payload for trade-windows, laid down at C:\Program Files\Contoso\Agent
packer/
  trade-base/trade-base.pkr.hcl           Amazon Linux 2 golden image
  trade-windows/trade-windows.pkr.hcl     Windows Server 2019 golden image
  scripts/                                install + boot-time scripts, shared by both templates
  build.sh                                ./build.sh <trade-base|trade-windows|all>
scripts/
  agent-inventory-scan.py                 the scan tool itself (baked onto both AMIs)
  scan-bundle-ci.sh                       local/CI verification (grype against the assembled bundle)
tests/
  trade-base-boot.Tests.ps1               Pester, stubbed AWS CLI, runs on ubuntu-latest
  trade-windows-boot.Tests.ps1            Pester, stubbed AWS CLI, runs on windows-latest
```

## The three vendored components

Same real, correctly-paired CVE/GHSA ids the combined-backlog generator's
`build_host_agent_findings()` hardcodes — this repo is what makes those
records real instead of synthesized.

| component | version | path (Linux) | path (Windows) | advisory |
|---|---|---|---|---|
| log4net | 1.2.10 | `/opt/contoso/agent/lib/log4net.dll` | `C:\Program Files\Contoso\Agent\lib\log4net.dll` | GHSA-2cwj-8chv-9pp9 (Critical) |
| OpenSSL | 1.0.1e | `/opt/contoso/agent/lib/libssl.so.1.0.0` | `C:\Program Files\Contoso\Agent\lib\ssleay32.dll` | CVE-2014-0160 / Heartbleed (Critical) |
| PyYAML | 3.13 | `/opt/contoso/agent/collector/vendor/yaml/__init__.py` | `C:\Program Files\Contoso\Agent\collector\vendor\yaml\__init__.py` | CVE-2017-18342 (High) |

- **log4net.dll** is the *actual* vulnerable binary — the same PE reused from
  `burndown-demo-infra`'s golden-image scenario (same vendor-drop lineage).
  grype flags it Critical from the DLL's own .NET assembly metadata alone,
  no manifest required.
- **PyYAML** is the real upstream 3.13 `__init__.py` (MIT-licensed), plus an
  `egg-info/PKG-INFO` alongside it so syft's Python package cataloger picks
  it up as an installed package, not just a loose file. Confirmed real via
  GHSA alias (`GHSA-rprw-h62v-c2w7` → `CVE-2017-18342`, matching the
  generator's own pairing) — see `scripts/scan-bundle-ci.sh`.
- **libssl.so.1.0.0 / ssleay32.dll are metadata stubs, not compiled OpenSSL.**
  Building a functional OpenSSL 1.0.1e (2013-era) from source on a modern
  toolchain wasn't practical for this environment, so these files carry the
  real SSLeay_version() banner text (`OpenSSL 1.0.1e 11 Feb 2013`) an agent
  would read off disk — the "version metadata a scanner reads," per this
  repo's build spec, when the real binary isn't practical.

### Why grype doesn't find OpenSSL (and why that's fine)

syft's binary classifier for OpenSSL only recognizes a file literally named
`openssl` (`FileGlob: "**/openssl"` in syft's own classifier source) — it
never matches `libssl.so.1.0.0` or `ssleay32.dll` by design, regardless of
content. So a `grype dir:` scan of this bundle finds log4net and PyYAML but
**not** OpenSSL — that's syft's real, documented behavior, not a bug in this
bundle.

The OpenSSL finding instead comes from `scripts/agent-inventory-scan.py`,
which is what a real host-based EDR/inventory agent does anyway: read the
version banner off the file on disk and match it against a known-advisory
table (`detection_method: "vendor-bundle file-hash + version match"`, same
as every `host_agent_findings` record in the combined-backlog export). Run
it locally against `vendor/` to verify all three components without AWS:

```
python3 scripts/agent-inventory-scan.py \
  --root vendor/agent-linux/opt/contoso/agent --os linux \
  --asset-id ami-0f4b2a91cd8e7f103 --asset-name trade-base-golden \
  --asset-role "golden-image (pre-launch AMI scan, ami-bakery trade-base)"
```

## Baking

```
cd packer
./build.sh trade-base       # a few minutes
./build.sh trade-windows    # 30-60 minutes
```

Requires `aws sts get-caller-identity` to succeed against the demo account
first. Publishes each AMI id to `/fabrikam/ami/<image>` in SSM Parameter
Store, which `infra-terraform`'s launch template resolves at instance
launch. AMIs persist between shoots per the cross-cutting AWS conventions —
rebake only when the vendored bundle changes.

## Local verification (no AWS required)

```
cd packer/trade-base && packer init . && packer validate .
cd packer/trade-windows && packer init . && packer validate .
./scripts/scan-bundle-ci.sh                      # grype: log4net + PyYAML real, both asserted
python3 scripts/agent-inventory-scan.py ...      # OpenSSL + the other two, via the agent's own logic
pwsh -c "Invoke-Pester -Path tests -CI"           # boot chain, present + missing-bundle cases
```

All of the above run in CI (`.github/workflows/validate.yml`) with no AWS
credentials.

---

*Fabrikam is a fictional company. This repository is part of a deliberately
vulnerable, synthetic demo environment built for the
[Burndown Security](https://www.youtube.com/@burndownsecurity) YouTube channel.
Nothing here is production software — do not deploy it.*
