<#
    install-agent-bundle.ps1 -- image-bake step that lays down the Contoso
    monitoring agent bundle on trade-windows (the ledger settlement host
    image). Run by Packer; also runs standalone in CI/Pester tests against
    any target directory.

    Mirrors the layout the Fabrikam combined-backlog generator hardcodes:

        C:\Program Files\Contoso\Agent\lib\log4net.dll
        C:\Program Files\Contoso\Agent\lib\ssleay32.dll
        C:\Program Files\Contoso\Agent\collector\vendor\yaml\__init__.py
#>
[CmdletBinding()]
param(
    # Directory containing the vendor-agent payload (i.e. vendor/agent-windows/Program Files/Contoso/Agent).
    [Parameter(Mandatory)]
    [string] $Source,

    [string] $Dest = 'C:\Program Files\Contoso\Agent'
)

$ErrorActionPreference = 'Stop'

if (Test-Path $Dest) {
    Remove-Item -Recurse -Force $Dest
}
New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
Copy-Item -Recurse -Force $Source $Dest

Write-Host "installed Contoso agent bundle to $Dest"
Get-ChildItem -Recurse -File $Dest | ForEach-Object { Write-Host "  $($_.FullName)" }
