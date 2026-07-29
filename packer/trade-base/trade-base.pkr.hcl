// trade-base.pkr.hcl -- the Amazon Linux 2 golden image for the Fabrikam
// host-agent fleet (trade-base). Vendors the Contoso monitoring agent
// bundle (log4net 1.2.10, OpenSSL 1.0.1e, PyYAML 3.13 -- see
// ../README.md for the lore) at the exact filesystem paths the
// combined-backlog generator's host-agent findings reference.
//
// Bake ahead of a shoot; AMIs persist between shoots per the cross-cutting
// AWS conventions (rebake only when bundle contents change).

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
  default = "t3.micro" // bake-time only; the fleet runs its own type
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "trade_base" {
  region        = var.region
  instance_type = var.instance_type

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username = "ec2-user"

  ami_name        = "fabrikam-trade-base-${local.timestamp}"
  ami_description = "Fabrikam trade-base golden image (Amazon Linux 2 + Contoso agent bundle)"

  tags = {
    project   = "burndown"
    scenario  = "fabrikam"
    ephemeral = "false" // AMIs persist between shoots per demo-env conventions
    team      = "platform-eng"
    service   = "trade-base"
    env       = "shared"
  }
}

build {
  sources = ["source.amazon-ebs.trade_base"]

  provisioner "file" {
    source      = "${path.root}/../../vendor/agent-linux/opt/contoso/agent"
    destination = "/tmp/agent"
  }

  provisioner "file" {
    source      = "${path.root}/../scripts"
    destination = "/tmp/scripts"
  }

  // The inventory-scan tool itself (../../scripts, not packer/scripts) --
  // the golden image carries its own scan capability, same as a real
  // host-based agent would.
  provisioner "file" {
    source      = "${path.root}/../../scripts"
    destination = "/tmp/agent-tools"
  }

  provisioner "shell" {
    inline = [
      "sudo yum install -y python3",
      "chmod +x /tmp/scripts/install-agent-bundle.sh /tmp/scripts/bootstrap.sh",
      "sudo /tmp/scripts/install-agent-bundle.sh /tmp/agent /opt/contoso/agent",
      "sudo mkdir -p /opt/contoso/bin",
      "sudo cp /tmp/scripts/bootstrap.sh /opt/contoso/bin/bootstrap.sh",
      "sudo cp /tmp/agent-tools/agent-inventory-scan.py /opt/contoso/bin/agent-inventory-scan.py",
      "sudo chmod +x /opt/contoso/bin/bootstrap.sh /opt/contoso/bin/agent-inventory-scan.py",
      "rm -rf /tmp/agent /tmp/scripts /tmp/agent-tools",
    ]
  }
}
