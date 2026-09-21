terraform {
  required_version = ">= 1.13.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111.1"
    }
  }
}

provider "proxmox" {}

variable "node_name" {
  description = "Proxmox node on which to create the VM"
  type        = string
}

variable "vm_id" {
  description = "Unused VM ID for the new guest"
  type        = number
}

variable "ssh_public_key" {
  description = "SSH public key to authorize in the guest"
  type        = string
}

resource "proxmox_download_file" "ubuntu" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}

module "vm" {
  source  = "patrick-sullivan-dev/vm-bootstrap/proxmox"
  version = "~> 0.1.1"

  vm_id     = var.vm_id
  name      = "ubuntu-demo"
  node_name = var.node_name

  cloud_image = {
    import_from = proxmox_download_file.ubuntu.id
  }

  disks = [{
    datastore_id = "local-lvm"
    size         = 25
  }]

  cloud_init = {
    hostname = "ubuntu-demo"

    user_data = [{
      username        = "ubuntu"
      authorized_keys = [var.ssh_public_key]
    }]
  }
}

output "ipv4_addresses" {
  description = "IPv4 addresses reported by the QEMU guest agent"
  value       = module.vm.proxmox_virtual_environment_vm_ipv4_addresses
  sensitive   = true
}
