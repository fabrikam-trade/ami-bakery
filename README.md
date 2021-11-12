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

---

*Fabrikam is a fictional company. This repository is part of a deliberately
vulnerable, synthetic demo environment built for the
[Burndown Security](https://www.youtube.com/@burndownsecurity) YouTube channel.
Nothing here is production software — do not deploy it.*
