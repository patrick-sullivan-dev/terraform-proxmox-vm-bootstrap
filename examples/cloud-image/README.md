# Create an Ubuntu VM from a cloud image

This example downloads an Ubuntu 24.04 cloud image and creates a VM with a 25 GB disk and DHCPv4 networking. It uses the published module with a constraint for compatible 0.1.x releases starting at 0.1.1.

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

Cloud-init installs and starts the QEMU guest agent on first boot, so the IP address can take a few minutes to appear. To use an image already stored in Proxmox, remove `proxmox_download_file.ubuntu` and set `cloud_image.import_from` to its `<datastore>:import/<filename>` identifier.
