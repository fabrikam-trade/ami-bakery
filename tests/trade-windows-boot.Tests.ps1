<#
    trade-windows-boot.Tests.ps1 -- proves the trade-windows (ledger
    settlement host) boot chain and the agent inventory scan without AWS:
    a stubbed `aws` CLI stands in for SSM Parameter Store.

    bundle present -> bootstrap succeeds, agent-status.txt written,
                       inventory scan produces 3 CTSO-EDR records
    bundle missing -> bootstrap fails loudly at the path check

    Runs on windows-latest in CI. Requires Pester 5. Mirrors
    burndown-demo-infra/tests/boot.Tests.ps1's shape (stubbed AWS CLI,
    present/missing bundle cases).
#>

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $scripts  = Join-Path $repoRoot 'packer\scripts'
    $payload  = Join-Path $repoRoot 'vendor\agent-windows\Program Files\Contoso\Agent'
    $scanTool = Join-Path $repoRoot 'scripts\agent-inventory-scan.py'

    # Stub `aws`: answers `ssm get-parameter` with a fixed tier, exit 0.
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
    @(
        '@echo off'
        'echo standard'
    ) | Set-Content -Path (Join-Path $stubDir 'aws.cmd') -Encoding ascii
    $env:PATH = "$stubDir;$env:PATH"

    function Install-Bundle {
        param([bool] $Complete = $true)
        $dest = Join-Path $TestDrive ([guid]::NewGuid())
        if ($Complete) {
            & (Join-Path $scripts 'install-agent-bundle.ps1') -Source $payload -Dest $dest | Out-Null
        } else {
            New-Item -ItemType Directory -Force -Path (Join-Path $dest 'lib') | Out-Null
            # Deliberately incomplete: no log4net.dll, no ssleay32.dll, no yaml module.
        }
        $dest
    }

    function Invoke-Boot {
        param([string] $BundleRoot, [string] $StateDir)
        & pwsh -NoProfile -File (Join-Path $scripts 'bootstrap.ps1') `
            -AgentRoot $BundleRoot -StateDir $StateDir -SsmParam '/fabrikam/agent/tier' *> $null
        $LASTEXITCODE
    }
}

Describe 'trade-windows boot chain (bundle present)' {
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
        Join-Path $bundle 'lib\log4net.dll' | Should -Exist
        Join-Path $bundle 'lib\ssleay32.dll' | Should -Exist
        Join-Path $bundle 'collector\vendor\yaml\__init__.py' | Should -Exist
    }

    It 'the inventory scan produces 3 real host-agent findings' {
        # `python`, not `python3` -- the python.org Windows installer (see
        # ../packer/trade-windows/trade-windows.pkr.hcl) only registers
        # python.exe, unlike Amazon Linux 2's python3 package.
        $out = python $scanTool --root $bundle --os windows `
            --asset-id i-test --asset-name ledger-settle-test --asset-role test | ConvertFrom-Json
        $out.Count | Should -Be 3
        ($out | Where-Object { $_.cve_ref -eq 'GHSA-2cwj-8chv-9pp9' }).risk_level | Should -Be 'CRITICAL'
        ($out.source | Select-Object -Unique) | Should -Be 'contoso-agent-inventory-v1.0'
    }
}

Describe 'trade-windows boot chain (bundle missing -- the confident delete)' {
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
