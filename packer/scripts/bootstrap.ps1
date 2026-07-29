<#
    bootstrap.ps1 -- boot-time provisioning for the trade-windows golden
    image (the ledger settlement host, ledger-settle-01).

    Invoked by user_data on every instance launch. Fetches the agent tier
    from SSM Parameter Store via the AWS CLI, verifies the Contoso
    monitoring agent bundle is present at every path the collector
    expects, and writes a status file scripts/agent-inventory-scan.py
    reads before it walks the bundle for real.

    Boot chain:
        user_data -> bootstrap.ps1 -> aws ssm get-parameter (agent tier)
                  -> verify bundle paths -> status file
    A missing bundle path fails loudly and exits 1, same shape as the
    Linux bootstrap.sh and as burndown-demo-infra's boot-chain scenario.
#>
[CmdletBinding()]
param(
    [string] $AgentRoot = 'C:\Program Files\Contoso\Agent',
    [string] $StateDir  = 'C:\ProgramData\Contoso',
    [string] $SsmParam  = '/fabrikam/agent/tier'
)

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$log = Join-Path $StateDir 'bootstrap.log'

function Write-Log([string] $Message) {
    $line = '{0:s}Z  {1}' -f (Get-Date).ToUniversalTime(), $Message
    Add-Content -Path $log -Value $line
    Write-Host $line
}

Write-Log "boot: fetching agent tier from SSM parameter '$SsmParam'"
try {
    $tier = & aws ssm get-parameter --name $SsmParam --query 'Parameter.Value' --output text 2>>$log
    if ($LASTEXITCODE -ne 0) { throw "aws exited $LASTEXITCODE" }
}
catch {
    Write-Log "boot: SSM lookup failed ($($_.Exception.Message)), defaulting tier to 'standard' (non-fatal)"
    $tier = 'standard'
}
Write-Log "boot: agent tier = $tier"

$requiredPaths = @(
    (Join-Path $AgentRoot 'lib\log4net.dll'),
    (Join-Path $AgentRoot 'lib\ssleay32.dll'),
    (Join-Path $AgentRoot 'collector\vendor\yaml\__init__.py')
)

$missing = $false
foreach ($p in $requiredPaths) {
    if (-not (Test-Path $p)) {
        Write-Log "boot FAILED: expected agent bundle file missing: $p"
        $missing = $true
    }
}

if ($missing) {
    Write-Log 'boot: agent bundle incomplete; inventory scan will not run on this host'
    exit 1
}

Write-Log "boot: agent bundle present, all $($requiredPaths.Count) paths verified"
Set-Content -Path (Join-Path $StateDir 'agent-status.txt') -Value "ok tier=$tier"
Write-Log "boot: wrote $(Join-Path $StateDir 'agent-status.txt')"
