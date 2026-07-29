#!/usr/bin/env bash
# Bake the Fabrikam golden image AMI(s).
#
#   ./build.sh trade-base       # Amazon Linux 2, host-agent fleet
#   ./build.sh trade-windows    # Windows Server 2019, ledger settlement host
#   ./build.sh all              # both
#
# Windows bakes run 30-60 min; Linux bakes run a few minutes. AMIs persist
# between shoots -- rebake only when the vendored bundle changes.
#
# Requires: `aws sts get-caller-identity` succeeding against the demo
# account first (see ../README.md). Publishes each AMI id to SSM under
# /fabrikam/ami/<image> so infra-terraform's launch templates pick it up.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:?usage: ./build.sh <trade-base|trade-windows|all>}"

bake() {
  local name="$1"
  echo "==> baking ${name}"
  (cd "${name}" && packer init . && packer build .)

  # ami_name is "fabrikam-<name>-<timestamp>" (see the template); match on
  # that instead of tags so a fresh bake is unambiguous even before the
  # describe-images eventual-consistency window settles.
  local ami_id
  ami_id="$(aws ec2 describe-images --owners self \
    --filters "Name=name,Values=fabrikam-${name}-*" "Name=tag:scenario,Values=fabrikam" \
    --query 'reverse(sort_by(Images,&CreationDate))[0].ImageId' --output text)"
  if [[ "$ami_id" != "None" && -n "$ami_id" ]]; then
    echo "==> publishing ${ami_id} to /fabrikam/ami/${name}"
    aws ssm put-parameter --name "/fabrikam/ami/${name}" --value "$ami_id" \
      --type String --data-type "aws:ec2:image" --overwrite >/dev/null
  fi
}

case "$MODE" in
  trade-base)    bake "trade-base" ;;
  trade-windows) bake "trade-windows" ;;
  all)
    bake "trade-base"
    bake "trade-windows"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

echo "==> done. AMI ids for this scenario:"
aws ec2 describe-images --owners self \
  --filters "Name=tag:scenario,Values=fabrikam" \
  --query 'reverse(sort_by(Images,&CreationDate))[].[ImageId,Name]' --output table
