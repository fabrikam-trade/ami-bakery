<#
    trade-base-boot.Tests.ps1 -- proves the trade-base (Amazon Linux 2) boot
    chain and the agent inventory scan without AWS: a stubbed `aws` CLI
    stands in for SSM Parameter Store.

    bundle present -> bootstrap succeeds, agent-status.txt written,
                       inventory scan produces 3 CTSO-EDR records
    bundle missing -> bootstrap fails loudly at the path check, no status
                       file, no scan possible

    Runs on ubuntu-latest in CI (ships pwsh + bash by default). Requires
    Pester 5. Mirrors burndown-demo-infra/tests/boot.Tests.ps1's shape
    (stubbed AWS CLI, present/missing bundle cases) for the Linux side of
    this scenario.
#>

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $scripts  = Join-Path $repoRoot 'packer/scripts'
    $payload  = Join-Path $repoRoot 'vendor/agent-linux/opt/contoso/agent'
    $scanTool = Join-Path $repoRoot 'scripts/agent-inventory-scan.py'

    # Stub `aws`: answers `ssm get-parameter` with a fixed tier, exit 0.
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
    @(
        '#!/usr/bin/env bash'
        'echo "standard"'
        'exit 0'
    ) -join "`n" | Set-Content -Path (Join-Path $stubDir 'aws') -NoNewline
    bash -c "chmod +x '$stubDir/aws'"
    $env:PATH = "${stubDir}:$($env:PATH)"

    function Install-Bundle {
        param([bool] $Complete = $true)
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $dest = Join-Path $root 'opt/contoso/agent'
        if ($Complete) {
            bash (Join-Path $scripts 'install-agent-bundle.sh') $payload $dest | Out-Null
        } else {
            New-Item -ItemType Directory -Force -Path (Join-Path $dest 'lib') | Out-Null
            # Deliberately incomplete: no log4net.dll, no libssl, no yaml module.
        }
        $dest
    }

    function Invoke-Boot {
        param([string] $BundleRoot, [string] $StateDir)
        bash (Join-Path $scripts 'bootstrap.sh') $BundleRoot $StateDir '/fabrikam/agent/tier' *> $null
        $LASTEXITCODE
    }
}

Describe 'trade-base boot chain (bundle present)' {
    BeforeAll {
        $bundle = Install-Bundle -Complete $true
        $state  = Join-Path $TestDrive 'state-present'
        $exit   = Invoke-Boot -BundleRoot $bundle -StateDir $state
    }

    It 'boots successfully' {
        $exit | Should -Be 0
    }

    It 'writes the agent-status file with the tier from SSM' {
        $status = Join-Path $state 'agent-status.txt'
        $status | Should -Exist
        Get-Content $status | Should -Match 'ok tier=standard'
    }

    It 'ships all three vendored components' {
        Join-Path $bundle 'lib/log4net.dll' | Should -Exist
        Join-Path $bundle 'lib/libssl.so.1.0.0' | Should -Exist
        Join-Path $bundle 'collector/vendor/yaml/__init__.py' | Should -Exist
    }

    It 'the inventory scan produces 3 real host-agent findings' {
        $out = python3 $scanTool --root $bundle --os linux `
            --asset-id ami-test --asset-name trade-base-test --asset-role test | ConvertFrom-Json
        $out.Count | Should -Be 3
        ($out | Where-Object { $_.cve_ref -eq 'GHSA-2cwj-8chv-9pp9' }).risk_level | Should -Be 'CRITICAL'
        ($out.source | Select-Object -Unique) | Should -Be 'contoso-agent-inventory-v1.0'
    }
}

Describe 'trade-base boot chain (bundle missing -- the confident delete)' {
    BeforeAll {
        $bundle = Install-Bundle -Complete $false
        $state  = Join-Path $TestDrive 'state-missing'
        $exit   = Invoke-Boot -BundleRoot $bundle -StateDir $state
    }

    It 'fails the boot chain' {
        $exit | Should -Be 1
    }

    It 'never writes an agent-status file' {
        Join-Path $state 'agent-status.txt' | Should -Not -Exist
    }

    It 'says exactly why in the boot log' {
        $log = Get-Content (Join-Path $state 'bootstrap.log') -Raw
        $log | Should -Match 'boot FAILED: expected agent bundle file missing'
        $log | Should -Match 'agent bundle incomplete'
    }
}
