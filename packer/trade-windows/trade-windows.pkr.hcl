// trade-windows.pkr.hcl -- the Windows Server 2019 golden image for the
// ledger settlement host (ledger-settle-01, trade-windows lineage).
// Vendors the same Contoso monitoring agent bundle as trade-base, at the
// Windows-path equivalents the combined-backlog generator hardcodes.
//
// Windows bakes run 30-60 min; AMIs persist between shoots per the
// cross-cutting AWS conventions (rebake only when bundle contents change).

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large" // bake-time only; the fleet runs its own type
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "trade_windows" {
  region        = var.region
  instance_type = var.instance_type

  source_ami_filter {
    filters = {
      name                = "Windows_Server-2019-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_use_ssl  = false
  winrm_insecure = true
  user_data_file = "${path.root}/../scripts/winrm-userdata.ps1"

  // The sysprep provisioner shuts the instance down itself; Packer must not
  // race it with its own StopInstances call.
  disable_stop_instance = true

  ami_name        = "fabrikam-trade-windows-${local.timestamp}"
  ami_description = "Fabrikam trade-windows golden image (Windows Server 2019 + Contoso agent bundle, ledger settlement host)"

  tags = {
    project   = "burndown"
    scenario  = "fabrikam"
    ephemeral = "false" // AMIs persist between shoots per demo-env conventions
    team      = "finance-eng"
    service   = "ledger-settlement"
    env       = "shared"
  }
}

build {
  sources = ["source.amazon-ebs.trade_windows"]

  // No trailing slash on source -> Packer creates <basename> INSIDE
  // destination, so upload to C:\Windows\Temp yields \Agent and \scripts.
  provisioner "file" {
    source      = "${path.root}/../../vendor/agent-windows/Program Files/Contoso/Agent"
    destination = "C:\\Windows\\Temp"
  }

  provisioner "file" {
    source      = "${path.root}/../scripts"
    destination = "C:\\Windows\\Temp"
  }

  // The inventory-scan tool itself (../../scripts, not packer/scripts) --
  // the golden image carries its own scan capability, same as the Linux
  // trade-base image does.
  provisioner "file" {
    source      = "${path.root}/../../scripts"
    destination = "C:\\Windows\\Temp\\agent-tools"
  }

  provisioner "powershell" {
    inline = [
      "Write-Host 'installing AWS CLI v2'",
      "Invoke-WebRequest -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile C:\\Windows\\Temp\\AWSCLIV2.msi",
      "Start-Process msiexec.exe -ArgumentList '/i','C:\\Windows\\Temp\\AWSCLIV2.msi','/qn' -Wait",
      "& 'C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe' --version",
    ]
  }

  provisioner "powershell" {
    inline = [
      "Write-Host 'installing Python 3 (needed to run the shared agent-inventory-scan.py tool)'",
      "Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe -OutFile C:\\Windows\\Temp\\python-installer.exe",
      "Start-Process C:\\Windows\\Temp\\python-installer.exe -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1','Include_test=0' -Wait",
    ]
  }

  // No trailing slash on the agent-tools source either, so the scan tool
  // lands at agent-tools\scripts\. A missed copy here must fail the bake --
  // Copy-Item errors are non-terminating by default and would otherwise
  // ship an AMI silently missing the scan tool.
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "& C:\\Windows\\Temp\\scripts\\install-agent-bundle.ps1 -Source C:\\Windows\\Temp\\Agent -Dest 'C:\\Program Files\\Contoso\\Agent'",
      "New-Item -ItemType Directory -Force -Path C:\\ProgramData\\Contoso | Out-Null",
      "Copy-Item C:\\Windows\\Temp\\scripts\\bootstrap.ps1 C:\\ProgramData\\Contoso\\bootstrap.ps1 -Force",
      "Copy-Item C:\\Windows\\Temp\\agent-tools\\scripts\\agent-inventory-scan.py C:\\ProgramData\\Contoso\\agent-inventory-scan.py -Force",
    ]
  }

  provisioner "powershell" {
    inline = [
      "Remove-Item -Recurse -Force C:\\Windows\\Temp\\Agent, C:\\Windows\\Temp\\scripts, C:\\Windows\\Temp\\agent-tools, C:\\Windows\\Temp\\AWSCLIV2.msi, C:\\Windows\\Temp\\python-installer.exe",
    ]
  }

  // Windows Server 2019 ships EC2Launch v1 (v2's ec2launch.exe only exists
  // on Server 2022+ or where v2 is retrofitted). InitializeInstance -Schedule
  // re-arms first-boot init; SysprepInstance runs sysprep and shuts down
  // (disable_stop_instance on the source), Packer waits for stopped.
  provisioner "powershell" {
    inline = [
      "C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Scripts\\InitializeInstance.ps1 -Schedule",
      "C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Scripts\\SysprepInstance.ps1",
    ]
    valid_exit_codes = [0, 1]
  }
}
