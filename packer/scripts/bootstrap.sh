#!/usr/bin/env bash
# bootstrap.sh -- boot-time provisioning for the trade-base golden image.
#
# Invoked by the launch template's user_data on every instance launch.
# Fetches this host's agent-tier tag from SSM Parameter Store (via the AWS
# CLI baked into the image), confirms the Contoso monitoring agent bundle
# is present at every path the collector expects, and writes a status file
# the health-agent inventory scan (scripts/agent-inventory-scan.py) reads
# before it walks the bundle for real.
#
# The dependency chain this scenario is about:
#     user_data -> bootstrap.sh -> ssm get-parameter (agent tier config)
#               -> verify bundle paths -> status file
# A missing bundle path fails loudly and exits nonzero, same shape as
# burndown-demo-infra's Windows boot-chain scenario (Import-Module snap).
set -euo pipefail

AGENT_ROOT="${1:-/opt/contoso/agent}"
STATE_DIR="${2:-/var/lib/contoso}"
SSM_PARAM="${3:-/fabrikam/agent/tier}"

mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/bootstrap.log"

log() {
  printf '%sZ  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$1" | tee -a "$LOG"
}

log "boot: fetching agent tier from SSM parameter '$SSM_PARAM'"
if ! TIER="$(aws ssm get-parameter --name "$SSM_PARAM" --query 'Parameter.Value' --output text 2>>"$LOG")"; then
  log "boot: SSM lookup failed, defaulting tier to 'standard' (non-fatal)"
  TIER="standard"
fi
log "boot: agent tier = $TIER"

REQUIRED_PATHS=(
  "$AGENT_ROOT/lib/log4net.dll"
  "$AGENT_ROOT/lib/libssl.so.1.0.0"
  "$AGENT_ROOT/collector/vendor/yaml/__init__.py"
)

MISSING=0
for p in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -f "$p" ]]; then
    log "boot FAILED: expected agent bundle file missing: $p"
    MISSING=1
  fi
done

if [[ "$MISSING" -ne 0 ]]; then
  log "boot: agent bundle incomplete; inventory scan will not run on this host"
  exit 1
fi

log "boot: agent bundle present, all $(printf '%s\n' "${REQUIRED_PATHS[@]}" | wc -l | tr -d ' ') paths verified"
echo "ok tier=$TIER" > "$STATE_DIR/agent-status.txt"
log "boot: wrote $STATE_DIR/agent-status.txt"
