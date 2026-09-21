# Create an Ubuntu VM from a cloud image

This example downloads an Ubuntu 24.04 cloud image and creates a VM with a 25 GB disk and DHCPv4 networking. It uses the published module with a constraint for compatible 0.1.x releases starting at 0.1.1.

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
```

## Run the example

Before running it, configure [Proxmox provider credentials](https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication), including SSH access for snippet uploads. The `local` datastore must allow Import and Snippets content, `local-lvm` must allow VM disks, and `vmbr0` must reach a DHCP network. Choose an unused VM ID.

```shell
export TF_VAR_node_name='pve'
export TF_VAR_vm_id='200'
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
terraform init
terraform plan
terraform apply
terraform output -json ipv4_addresses
```

Cloud-init installs and starts the QEMU guest agent on first boot, so the IP address can take a few minutes to appear. To use an image already stored in Proxmox, remove `proxmox_download_file.ubuntu` and set `cloud_image.import_from` to its `<datastore>:import/<filename>` identifier. Make sure to review the plan before applying.
