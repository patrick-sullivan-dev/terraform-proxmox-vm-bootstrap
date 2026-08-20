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
  description = "Proxmox node on which to create the clone"
  type        = string
}

variable "source_vm_id" {
  description = "ID of the existing Cloud-Init VM or template"
  type        = number
}

variable "target_vm_id" {
  description = "ID to assign to the cloned VM"
  type        = number
}

variable "ssh_public_key" {
  description = "SSH public key to authorize in the cloned guest"
  type        = string
}

module "vm" {
  source = "../.."

  vm_id     = var.target_vm_id
  name      = "ubuntu-clone"
  node_name = var.node_name

  clone = {
    vm_id = var.source_vm_id
  }

  cloud_init = {
    hostname = "ubuntu-clone"

    user_data = [{
      username        = "ubuntu"
      authorized_keys = [var.ssh_public_key]
    }]

    network_data = [{
      dhcp4 = true
    }]
  }
}
