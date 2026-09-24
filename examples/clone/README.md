# Clone a Cloud-init VM

This example clones an existing Cloud-init-capable VM or template. It uses the published module with a constraint for compatible 0.1.x releases starting at 0.1.1. The source VM must already exist; this example does not create or modify it.

## main.tf

Copy this configuration into an empty directory as `main.tf`, or use **View Source** above to download the example. The Registry’s **Provision Instructions** box calls this entire example as a module; the code below shows the VM configuration you can customize.

```hcl
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
  source  = "patrick-sullivan-dev/vm-bootstrap/proxmox"
  version = "~> 0.1.1"

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
```

## Run the example

Set the [Proxmox provider credentials](https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication) in environment variables, including SSH access for snippet uploads. The `local` datastore must allow snippets and `local-lvm` must allow VM disks. Choose an unused target VM ID.

```shell
export TF_VAR_node_name='pve'
export TF_VAR_source_vm_id='9000'
export TF_VAR_target_vm_id='201'
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
terraform init
terraform plan
terraform apply
```

Set `clone.node_name` and `clone.datastore_id` in `main.tf` if cloning from another node or into another datastore. The source and target VM IDs must differ. Destroying this configuration should remove only the clone and its generated snippets. Make sure to review the plan before applying or destroying.
