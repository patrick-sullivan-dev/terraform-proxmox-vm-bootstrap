# Proxmox Cloud-Init VM

[![Terraform Quality](https://github.com/patrick-sullivan-dev/proxmox-cloudinit-vm/actions/workflows/_tf-lint.yml/badge.svg)](https://github.com/patrick-sullivan-dev/proxmox-cloudinit-vm/actions/workflows/_tf-lint.yml)
[![Documentation](https://github.com/patrick-sullivan-dev/proxmox-cloudinit-vm/actions/workflows/documentation.yml/badge.svg)](https://github.com/patrick-sullivan-dev/proxmox-cloudinit-vm/actions/workflows/documentation.yml)

A Terraform module for bootstrapping Proxmox VE virtual machines from cloud images. Cloud-init configuration is rendered from module variables. 

The goal is to end up with a fully bootstrapped VM thats ready for provisioning by some other tool like Ansible. No need to manage Cloud-init configuration separately.

## Features

- Multiple cloud-init users with password hashes, groups, login shells, sudo rules, authorized keys, and SSH import IDs.
- Hostname and FQDN configuration.
- Additional package installation, with package updates and upgrades during the initial boot.
- DHCPv4, DHCPv6, or static addressing, including multiple addresses per interface.
- IPv4 and IPv6 routes, DNS servers, and DNS search domains.
- Multiple network interfaces with indiviual configuration and provided or generated MAC addresses.
- Automatic installation and startup of the QEMU guest agent.
- All bgp/proxmox provider variables are exposed.

Defaults are opinionated for a modern Linux guest: Q35, OVMF/UEFI, two CPU cores, 2GB of memory, 25GB disk space, DHCPv4, VirtIO networking on `vmbr0`, and an enabled QEMU guest agent.

## Quick start

> [!IMPORTANT]
>
> - Terraform `>= 1.13.5`
> - Proxmox VE 8.x or later
> - The snippet datastore (default: `local`) allows the **Snippets** content type.
> - The cloud-image datastore (`local` in this example) allows the **Import** content type.
> - The VM datastore (default: `local-lvm`) allows **Disk image** content and has at least 25 GB of space.
> - The target bridge (default: `vmbr0`) exists and can reach a network with DHCP.
> - SSH access is required to upload snippets. Configure an SSH username and an agent, private key, or password.
> - API authentication is preferred for other operations and is used in the examples below.

In the Proxmox web UI, storage content types are set under **Datacenter → Storage → select a datastore → Edit**. See the provider's [authentication documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication) and [cloud-image guide](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/guides/cloud-image) for details.

### 2. Configure provider credentials

Keep credentials out of Terraform files and state by using the provider's environment variables:

```shell
export PROXMOX_VE_ENDPOINT='https://pve.example.com:8006/'
export PROXMOX_VE_API_TOKEN='terraform@pve!provider=replace-with-token-secret'
export PROXMOX_VE_SSH_USERNAME='root'
export PROXMOX_VE_SSH_AGENT='true'
ssh-add ~/.ssh/id_ed25519
```

If Proxmox uses a self-signed certificate, `PROXMOX_VE_INSECURE=true` is convenient for testing. Use a trusted certificate instead of disabling TLS verification in production environments.

### 3. Create a VM

The configuration below downloads an Ubuntu 24.04 cloud image to Proxmox, creates a VM, and grants access through your existing SSH public key.

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

resource "proxmox_download_file" "ubuntu" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pve"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}

module "vm" {
  source = "git::https://github.com/patrick-sullivan-dev/proxmox-cloudinit-vm.git"

  vm_id     = 200
  name      = "ubuntu-demo"
  node_name = "pve"
  tags      = ["terraform", "ubuntu"]

  cpu = {
    cores = 4
  }

  memory = {
    dedicated = 4096
  }

  cloud_image = {
    import_from = proxmox_download_file.ubuntu.id
  }

  disks = [{
    datastore_id = "local-lvm"
    interface    = "scsi"
    size         = 25
    discard      = "on"
    iothread     = true
    ssd          = true
  }]

  cloud_init = {
    datastore_id      = "local"
    disk_datastore_id = "local-lvm"
    hostname          = "ubuntu-demo"
    packages          = ["curl", "jq"]

    user_data = [{
      username = "ubuntu"
      authorized_keys = [
        trimspace(file(pathexpand("~/.ssh/id_ed25519.pub"))),
      ]
    }]

    network_data = [{
      dhcp4 = true
    }]
  }
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses reported by the QEMU guest agent"
  value       = module.vm.proxmox_virtual_environment_vm_ipv4_addresses
  sensitive   = true
}
```

Outside of testing, you should pin `source` to a release tag or full commit SHA before using the module. New commits/releases may contain breaking changes 

### 4. Apply and connect

```shell
terraform init
terraform plan
terraform apply
terraform output -json vm_ipv4_addresses
ssh ubuntu@<guest-ip>
```

The first boot can take several minutes while Cloud-init updates packages and installs the QEMU guest agent. Check the Proxmox console or run `cloud-init status --wait` inside the guest if SSH is not available yet. For me with a SATA SSD and 1gig networking, it takes about 2min for Terraform to download the image and set up the VM completetly. 

## Usage examples

### Use an existing cloud image

Provide exactly one source for the first disk. The simplest choices are:

```hcl
# An uncompressed image in an Import-enabled datastore.
cloud_image = {
  import_from = "local:import/noble-server-cloudimg-amd64.qcow2"
}
```

```hcl
# An ISO or supported compressed image already in Proxmox.
cloud_image = {
  file_id = "local:iso/example-cloud-image.img"
}
```

You can place `file_id`, `import_from`, or `path_in_datastore` directly on the first `disks` entry instead. The module rejects a configuration unless exactly one of those values resolves for the boot disk. `import_from` is preferred for uncompressed cloud images; consult the provider's [cloud-image guide](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/guides/cloud-image) for compressed images.

### Configure a static address

Addresses use CIDR notation. `default_route` is a single next-hop address without a CIDR prefix, aka your routers address. 

```hcl
cloud_init = {
  hostname = "app-01"

  user_data = [{
    username        = "ansible"
    authorized_keys = [trimspace(file("./admin.pub"))]
  }]

  network_data = [{
    interface_name = "eth0"
    addresses      = ["192.0.2.20/24"]
    dhcp4          = false
    default_route  = "192.0.2.1"
    dns_servers    = ["192.0.2.1"]
    dns_domains    = ["example.test"]
  }]
}
```

When `dhcp4` is omitted, the module enables DHCPv4 if `addresses` is empty and disables it if a static address is present.

### Configure IPv6 or dual stack

For DHCPv6-only networking, disable DHCPv4 and tell the guest-agent wait logic
to wait for IPv6:

```hcl
agent = {
  wait_for_ip = {
    ipv6 = true
  }
}

cloud_init = {
  network_data = [{
    dhcp4 = false
    dhcp6 = true
  }]
}
```

Static IPv4 and IPv6 addresses can share an interface. Use `routes` when more
than one default route is needed:

```hcl
agent = {
  wait_for_ip = {
    ipv4 = true
    ipv6 = true
  }
}

cloud_init = {
  network_data = [{
    interface_name = "eth0"
    addresses = [
      "192.0.2.20/24",
      "2001:db8::20/64",
    ]
    dhcp4 = false
    dhcp6 = false
    routes = [
      { to = "0.0.0.0/0", via = "192.0.2.1" },
      { to = "::/0", via = "2001:db8::1" },
    ]
    dns_servers = ["192.0.2.53", "2001:db8::53"]
  }]
}
```

Route destinations use CIDR notation and `via` is a same-family gateway
address without a prefix. `default_route` remains a shortcut when only one
default route is required. If neither guest-agent address-family flag is set,
the provider waits for any global IPv4 or IPv6 address; set one or both flags
when a particular family must be available before apply completes.

### Configure multiple network interfaces

`network_devices` and `cloud_init.network_data` are positional pairs and must have the same number of entries. The module assigns or preserves each NIC's MAC address, then uses it in Cloud-init to match and rename the guest interface.

```hcl
network_devices = [
  { bridge = "vmbr0", vlan_id = 10 },
  { bridge = "vmbr1", firewall = false },
]

cloud_init = {
  user_data = [{
    username        = "ubuntu"
    authorized_keys = [trimspace(file("./admin.pub"))]
  }]

  network_data = [
    {
      interface_name = "eth0"
      addresses      = ["192.0.2.20/24"]
      default_route  = "192.0.2.1"
      dns_servers    = ["192.0.2.53"]
    },
    {
      interface_name = "eth1"
      addresses      = ["198.51.100.20/24"]
    },
  ]
}
```

### Add users and packages

`cloud_init.user_data` accepts multiple users. Use only SSH keys whenever possible, but if `password` is needed, use a password hash supported by Cloud-init (run: openssl password_here -6)

```hcl
cloud_init = {
  fqdn     = "worker-01.example.test"
  packages = ["curl", "jq"]

  user_data = [
    {
      username        = "operator"
      groups          = ["sudo", "adm"]
      authorized_keys = [trimspace(file("./operator.pub"))]
    },
    {
      username       = "automation"
      ssh_import_ids = ["gh:example-user"]
    },
  ]

  network_data = [{}]
}
```

The rendered user data always enables package updates and upgrades and installs `qemu-guest-agent` and `ssh-import-id` in addition to `packages`.

## Important behavior

| Area | Behavior |
| --- | --- |
| Boot disk | `disks` must contain at least one entry. Interfaces are supplied without an index (`scsi`, `sata`, or `virtio`); the module assigns indexes in list order. |
| Cloud image | Exactly one of `file_id`, `import_from`, or `path_in_datastore` must resolve on the first disk, either supply directly to the first disk or use the cloud_image variable |
| Networking | The network-device and Cloud-init network lists must have equal lengths. Missing MAC addresses are generated with a locally administered prefix. Addresses and route destinations require CIDR notation; route gateways do not. |
| Firmware | The default is Q35 with OVMF. An EFI disk is created automatically when `system.bios` is `ovmf`. |
| Guest agent | Enabled by default. Cloud-init installs and starts it; reported IP outputs may remain empty until first-boot provisioning finishes. |
| Guest access | The default `ubuntu` user has no password or authorized key. Supply `authorized_keys`, `ssh_import_ids`, or a password hash before relying on guest access. |
| Destruction | By default, unreferenced disks and backup configuration are purged. Review `delete_unreferenced_disks_on_destroy`, `purge_on_destroy`, `protection`, and `stop_on_destroy` for critical workloads. |
| Debug files | Setting `debug_files = true` writes rendered Cloud-init YAML beside the module. Those files can contain secrets and are ignored by this repository's `.gitignore`. |

## Troubleshooting

### View Cloud-init output

The module automatically adds a socket serial device to the VM. This allows you to see all of the boot logs and Cloud-init logs that are usally hidden from the standard noVNC console. To view the serial output on the Proxmox web UI, use the xterm.js console by selecting it from the `console` dropdown in the top right, or run the command: `qm terminal VM_ID` in the shell of the Proxmox node. 

### Snippet upload fails over SSH

API access alone is not sufficient for the Cloud-init snippet uploads. Confirm that the provider's SSH user, key or agent, node address, and host key settings are correct. API-token authentication does not automatically provide an SSH password.

### Proxmox rejects the datastore content type

Enable **Snippets** on `cloud_init.datastore_id` and **Import** on the datastore used by an uncompressed downloaded cloud image.

### The VM starts but has no reported IP address

Wait for Cloud-init and the QEMU guest agent, confirm the image supports Cloud-init, and verify DHCP or static routes from the Proxmox console. For IPv6, confirm that router advertisements or DHCPv6 are available when used and that `agent.wait_for_ip` requests the intended address family. Also check that each `network_data` entry corresponds to the same-position `network_devices` entry.

### Cloud-init did not apply a later change

Cloud-init is primarily a first-boot system. Inspect `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`, and `cloud-init status --long` in the guest. Some changes require recreating the VM or explicitly cleaning Cloud-init state in the image.

## Security and state

Cloud-init content is stored in Terraform state and in the Proxmox snippets datastore. Treat both as sensitive and ideally:

- Use an encrypted remote state backend.
- Keep API tokens, SSH private keys, and passwords out of `.tf` and `.tfvars` files committed to version control.
- Prefer SSH public keys over passwords.
- Restrict access to the snippets datastore and remove generated debug files after use.
- Review a destroy plan carefully because the module's disk and backup purge options default to `true`.

All module outputs are marked sensitive to reduce accidental display. `terraform output -json` or `terraform output -raw` still reveals requested values to an authorized operator.

<!-- BEGIN_TF_DOCS -->
## Module reference

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.5 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.4.0 |
| <a name="requirement_macaddress"></a> [macaddress](#requirement\_macaddress) | >= 0.3.2 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.111.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | >= 2.4.0 |
| <a name="provider_macaddress"></a> [macaddress](#provider\_macaddress) | >= 0.3.2 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | >= 0.111.1 |

## Resources

| Name | Type |
|------|------|
| [local_file.rendered_network_config_debug](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.rendered_user_config_debug](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [macaddress_macaddress.this](https://registry.terraform.io/providers/ivoronin/macaddress/latest/docs/resources/macaddress) | resource |
| [proxmox_virtual_environment_file.network_data_cloud_config](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_file.user_data_cloud_config](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.this](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_init"></a> [cloud\_init](#input\_cloud\_init) | Cloud-init configuration.<br/><br/>datastore\_id must allow the snippets content type. disk\_datastore\_id must<br/>allow VM disk images. user\_data and network\_data default to one entry each;<br/>network\_data must contain the same number of entries as network\_devices.<br/><br/>User passwords must be Cloud-init-compatible password hashes. Prefer<br/>authorized\_keys or ssh\_import\_ids instead. | <pre>object({<br/>    datastore_id        = optional(string, "local")<br/>    node_name           = optional(string)<br/>    disk_datastore_id   = optional(string, "local-lvm")<br/>    interface           = optional(string)<br/>    file_format         = optional(string)<br/>    vendor_data_file_id = optional(string)<br/>    meta_data_file_id   = optional(string)<br/><br/>    hostname = optional(string, null)<br/>    fqdn     = optional(string, null)<br/><br/>    user_data = optional(list(object({<br/>      username        = optional(string, "ubuntu")<br/>      password        = optional(string, null)<br/>      groups          = optional(list(string), ["sudo"])<br/>      shell           = optional(string, "/bin/bash")<br/>      sudoers         = optional(string, "ALL=(ALL) NOPASSWD:ALL")<br/>      ssh_import_ids  = optional(list(string), [])<br/>      authorized_keys = optional(list(string), [])<br/>    })), [{}])<br/><br/>    network_data = optional(list(object({<br/>      interface_name = optional(string, "eth0")<br/>      addresses      = optional(list(string), [])<br/>      dhcp4          = optional(bool, null)<br/>      dhcp6          = optional(bool, false)<br/>      default_route  = optional(string, null)<br/>      routes = optional(list(object({<br/>        to  = string<br/>        via = string<br/>      })), [])<br/>      dns_servers = optional(list(string), [])<br/>      dns_domains = optional(list(string), [])<br/>      mac_prefix  = optional(list(number), [2])<br/>    })), [{}])<br/><br/>    packages = optional(list(string), [])<br/>  })</pre> | n/a | yes |
| <a name="input_disks"></a> [disks](#input\_disks) | Disk specifications.<br/><br/>Specify only the disk interface type: scsi, sata, or virtio.<br/>Do not include an index such as scsi0; indexes are assigned automatically.<br/><br/>The first disk is the boot disk. Its import\_from and file\_id values fall<br/>back to the matching cloud\_image value. Exactly one of file\_id,<br/>import\_from, or path\_in\_datastore must resolve for that disk.<br/><br/>At least one disk is required. Each entry defaults to the local-lvm<br/>datastore, scsi interface, and raw format; disk size is provider-defined<br/>when omitted. | <pre>list(object({<br/>    aio               = optional(string)<br/>    backup            = optional(bool)<br/>    cache             = optional(string)<br/>    datastore_id      = optional(string, "local-lvm")<br/>    discard           = optional(string)<br/>    file_format       = optional(string, "raw")<br/>    file_id           = optional(string)<br/>    import_from       = optional(string)<br/>    interface         = optional(string, "scsi")<br/>    iothread          = optional(bool)<br/>    path_in_datastore = optional(string)<br/>    queues            = optional(number)<br/>    replicate         = optional(bool)<br/>    serial            = optional(string)<br/>    size              = optional(number)<br/>    ssd               = optional(bool)<br/>    speed = optional(object({<br/>      iops_read            = optional(number)<br/>      iops_read_burstable  = optional(number)<br/>      iops_write           = optional(number)<br/>      iops_write_burstable = optional(number)<br/>      read                 = optional(number)<br/>      read_burstable       = optional(number)<br/>      write                = optional(number)<br/>      write_burstable      = optional(number)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the VM within Proxmox | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox node to create the VM on | `string` | n/a | yes |
| <a name="input_vm_id"></a> [vm\_id](#input\_vm\_id) | The ID of the VM to be created | `number` | n/a | yes |
| <a name="input_acpi"></a> [acpi](#input\_acpi) | Whether to enable ACPI | `bool` | `true` | no |
| <a name="input_agent"></a> [agent](#input\_agent) | QEMU Guest Agent configuration | <pre>object({<br/>    enabled = optional(bool, true)<br/>    timeout = optional(string)<br/>    trim    = optional(bool)<br/>    type    = optional(string)<br/>    wait_for_ip = optional(object({<br/>      disabled = optional(bool)<br/>      ipv4     = optional(bool)<br/>      ipv6     = optional(bool)<br/>    }))<br/>  })</pre> | `{}` | no |
| <a name="input_amd_sev"></a> [amd\_sev](#input\_amd\_sev) | AMD SEV configuration | <pre>object({<br/>    type           = optional(string, "std")<br/>    allow_smt      = optional(bool, true)<br/>    kernel_hashes  = optional(bool, false)<br/>    no_debug       = optional(bool, false)<br/>    no_key_sharing = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_audio_device"></a> [audio\_device](#input\_audio\_device) | Audio device configuration | <pre>object({<br/>    device  = optional(string, "intel-hda")<br/>    driver  = optional(string, "spice")<br/>    enabled = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_boot_order"></a> [boot\_order](#input\_boot\_order) | Boot order configuration | `list(string)` | `null` | no |
| <a name="input_cdrom"></a> [cdrom](#input\_cdrom) | CD-ROM configuration | <pre>object({<br/>    enabled   = optional(bool, false)<br/>    file_id   = optional(string, "none")<br/>    interface = optional(string, "ide3")<br/>  })</pre> | `null` | no |
| <a name="input_cloud_image"></a> [cloud\_image](#input\_cloud\_image) | Cloud image used to initialize the VM.<br/><br/>Provide either import\_from or file\_id using a Proxmox file identifier.<br/><br/>This object may be omitted only when the first disks entry supplies its<br/>own image source. Use one of the following; prefer import\_from unless<br/>using an ISO or compressed image.<br/>import\_from: "<datastore\_id>:import/<file\_name>"<br/>file\_id: "<datastore\_id>:<content\_type>/<file\_name>"<br/><br/>A proxmox\_download\_file resource id can also be used instead. | <pre>object({<br/>    import_from = optional(string)<br/>    file_id     = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU configuration, defaults to 2 x86-64-v2-AES cores | <pre>object({<br/>    architecture = optional(string)<br/>    cores        = optional(number, 2)<br/>    flags        = optional(list(string))<br/>    hotplugged   = optional(number)<br/>    limit        = optional(number)<br/>    numa         = optional(bool)<br/>    sockets      = optional(number)<br/>    type         = optional(string, "x86-64-v2-AES")<br/>    units        = optional(number)<br/>    affinity     = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_debug_files"></a> [debug\_files](#input\_debug\_files) | Whether to output debug files (e.g., cloud-init user-data and network-data files) | `bool` | `false` | no |
| <a name="input_delete_unreferenced_disks_on_destroy"></a> [delete\_unreferenced\_disks\_on\_destroy](#input\_delete\_unreferenced\_disks\_on\_destroy) | Whether to delete unreferenced disks when the VM is destroyed | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | The description of the VM within Proxmox | `string` | `"Managed by Terraform"` | no |
| <a name="input_hook_script_file_id"></a> [hook\_script\_file\_id](#input\_hook\_script\_file\_id) | Proxmox file ID for the hook script to be used with the VM | `string` | `null` | no |
| <a name="input_hostpci"></a> [hostpci](#input\_hostpci) | Host PCI passthrough configuration | <pre>list(object({<br/>    device   = string<br/>    id       = optional(string)<br/>    mapping  = optional(string)<br/>    mdev     = optional(string)<br/>    pcie     = optional(bool)<br/>    rombar   = optional(bool)<br/>    rom_file = optional(string)<br/>    xvga     = optional(bool)<br/>  }))</pre> | `null` | no |
| <a name="input_hotplug"></a> [hotplug](#input\_hotplug) | Hotplug configuration, accepts 0 to disable, 1 to enable all, or a comma-separated list of cpu, disk, memory, network, and usb | `string` | `null` | no |
| <a name="input_keyboard_layout"></a> [keyboard\_layout](#input\_keyboard\_layout) | Keyboard layout within Proxmox | `string` | `null` | no |
| <a name="input_kvm_arguments"></a> [kvm\_arguments](#input\_kvm\_arguments) | Additional KVM arguments | `string` | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory configuration (1GB = 1024), defaults to 2GB with ballooning enabled | <pre>object({<br/>    dedicated         = optional(number, 2048)<br/>    ballooning_device = optional(bool, true)<br/>    shared            = optional(number)<br/>    hugepages         = optional(string)<br/>    keep_hugepages    = optional(bool)<br/>  })</pre> | `{}` | no |
| <a name="input_migrate"></a> [migrate](#input\_migrate) | Whether to migrate (true) or recreate (false) the VM on node change | `bool` | `false` | no |
| <a name="input_network_devices"></a> [network\_devices](#input\_network\_devices) | Network interface configurations, defaults to one virtio interface on vmbr0 with firewall enabled. | <pre>list(object({<br/>    model        = optional(string, "virtio")<br/>    bridge       = optional(string, "vmbr0")<br/>    vlan_id      = optional(number)<br/>    rate_limit   = optional(number)<br/>    firewall     = optional(bool, true)<br/>    disconnected = optional(bool)<br/>    mtu          = optional(number)<br/>    multi_queue  = optional(number)<br/>    mac_address  = optional(string)<br/>    trunks       = optional(string)<br/>  }))</pre> | <pre>[<br/>  {}<br/>]</pre> | no |
| <a name="input_numa"></a> [numa](#input\_numa) | The NUMA configuration | <pre>list(object({<br/>    device    = string<br/>    cpus      = string<br/>    memory    = number<br/>    hostnodes = optional(list(string))<br/>    policy    = optional(string)<br/>  }))</pre> | `null` | no |
| <a name="input_on_boot"></a> [on\_boot](#input\_on\_boot) | Whether to start the VM on system boot | `bool` | `true` | no |
| <a name="input_pool_id"></a> [pool\_id](#input\_pool\_id) | Proxmox pool to add the VM to | `string` | `null` | no |
| <a name="input_protection"></a> [protection](#input\_protection) | Sets the protection flag of the VM | `bool` | `false` | no |
| <a name="input_purge_on_destroy"></a> [purge\_on\_destroy](#input\_purge\_on\_destroy) | Whether to purge backup configs of the VM on destroy | `bool` | `true` | no |
| <a name="input_reboot"></a> [reboot](#input\_reboot) | Whether to reboot the VM after creation | `bool` | `false` | no |
| <a name="input_reboot_after_update"></a> [reboot\_after\_update](#input\_reboot\_after\_update) | Whether the provider may reboot or stop the VM when required to apply configuration updates | `bool` | `true` | no |
| <a name="input_rng"></a> [rng](#input\_rng) | RNG device configuration | <pre>object({<br/>    source    = optional(string, "/dev/urandom")<br/>    max_bytes = optional(number)<br/>    period    = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_scsi_hardware"></a> [scsi\_hardware](#input\_scsi\_hardware) | SCSI controller type | `string` | `"virtio-scsi-single"` | no |
| <a name="input_serial_device"></a> [serial\_device](#input\_serial\_device) | Serial device configuration, defaults to one socket device, set to null for no serial device | <pre>list(object({<br/>    device = optional(string, "socket")<br/>  }))</pre> | <pre>[<br/>  {}<br/>]</pre> | no |
| <a name="input_smbios"></a> [smbios](#input\_smbios) | SMBIOS type 1 configuration | <pre>object({<br/>    family       = optional(string)<br/>    manufacturer = optional(string)<br/>    product      = optional(string)<br/>    serial       = optional(string)<br/>    sku          = optional(string)<br/>    uuid         = optional(string)<br/>    version      = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_started"></a> [started](#input\_started) | Whether to start the VM after creation | `bool` | `true` | no |
| <a name="input_startup"></a> [startup](#input\_startup) | Startup configuration, time measured in seconds | <pre>object({<br/>    order      = optional(number)<br/>    up_delay   = optional(number)<br/>    down_delay = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_stop_on_destroy"></a> [stop\_on\_destroy](#input\_stop\_on\_destroy) | Whether to stop rather than shutdown VM before destroy | `bool` | `false` | no |
| <a name="input_system"></a> [system](#input\_system) | System configuration<br/><br/>EFI disk automatically created when bios is set to "ovmf". <br/>datastore\_id for EFI and TPM state default to local-lvm.<br/><br/>Defaults to q35 / ovmf / l26 with a 4m EFI disk and no TPM. | <pre>object({<br/>    machine = optional(string, "q35")<br/>    bios    = optional(string, "ovmf")<br/>    os_type = optional(string, "l26")<br/>    efi_disk = optional(object({<br/>      datastore_id      = optional(string)<br/>      file_format       = optional(string)<br/>      type              = optional(string, "4m")<br/>      pre_enrolled_keys = optional(bool)<br/>    }), {})<br/>    tpm_state = optional(object({<br/>      datastore_id = optional(string)<br/>      version      = optional(string)<br/>    }))<br/>  })</pre> | `{}` | no |
| <a name="input_tablet_device"></a> [tablet\_device](#input\_tablet\_device) | Whether to enable the USB tablet device | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | List of tags to add to the VM within Proxmox | `list(string)` | `[]` | no |
| <a name="input_template"></a> [template](#input\_template) | Whether to convert the VM into a template | `bool` | `false` | no |
| <a name="input_timeout_create"></a> [timeout\_create](#input\_timeout\_create) | Timeout for VM creation in seconds | `number` | `1800` | no |
| <a name="input_timeout_migrate"></a> [timeout\_migrate](#input\_timeout\_migrate) | Timeout for VM migration in seconds | `number` | `1800` | no |
| <a name="input_timeout_reboot"></a> [timeout\_reboot](#input\_timeout\_reboot) | Timeout for VM reboot in seconds | `number` | `1800` | no |
| <a name="input_timeout_shutdown_vm"></a> [timeout\_shutdown\_vm](#input\_timeout\_shutdown\_vm) | Timeout for VM shutdown in seconds | `number` | `1800` | no |
| <a name="input_timeout_start_vm"></a> [timeout\_start\_vm](#input\_timeout\_start\_vm) | Timeout for VM startup in seconds | `number` | `1800` | no |
| <a name="input_timeout_stop_vm"></a> [timeout\_stop\_vm](#input\_timeout\_stop\_vm) | Timeout for stopping the VM in seconds | `number` | `300` | no |
| <a name="input_usb"></a> [usb](#input\_usb) | USB device configuration | <pre>list(object({<br/>    host    = optional(string)<br/>    mapping = optional(string)<br/>    usb3    = optional(bool)<br/>  }))</pre> | `null` | no |
| <a name="input_vga"></a> [vga](#input\_vga) | VGA device configuration | <pre>object({<br/>    memory    = optional(number)<br/>    type      = optional(string)<br/>    clipboard = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_virtiofs"></a> [virtiofs](#input\_virtiofs) | Virtiofs share configuration | <pre>list(object({<br/>    mapping      = string<br/>    cache        = optional(string)<br/>    direct_io    = optional(bool)<br/>    expose_acl   = optional(bool)<br/>    expose_xattr = optional(bool)<br/>  }))</pre> | `null` | no |
| <a name="input_watchdog"></a> [watchdog](#input\_watchdog) | Watchdog device configuration | <pre>object({<br/>    enabled = optional(bool)<br/>    model   = optional(string)<br/>    action  = optional(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the VM in Proxmox VE |
| <a name="output_name"></a> [name](#output\_name) | The name of the VM in Proxmox VE |
| <a name="output_node_name"></a> [node\_name](#output\_node\_name) | The Proxmox VE node name where the VM exists |
| <a name="output_proxmox_virtual_environment_vm"></a> [proxmox\_virtual\_environment\_vm](#output\_proxmox\_virtual\_environment\_vm) | The Proxmox VE VM resource |
| <a name="output_proxmox_virtual_environment_vm_ipv4_addresses"></a> [proxmox\_virtual\_environment\_vm\_ipv4\_addresses](#output\_proxmox\_virtual\_environment\_vm\_ipv4\_addresses) | The IPv4 addresses of the VM |
| <a name="output_proxmox_virtual_environment_vm_ipv6_addresses"></a> [proxmox\_virtual\_environment\_vm\_ipv6\_addresses](#output\_proxmox\_virtual\_environment\_vm\_ipv6\_addresses) | The IPv6 addresses of the VM |
| <a name="output_proxmox_virtual_environment_vm_mac_addresses"></a> [proxmox\_virtual\_environment\_vm\_mac\_addresses](#output\_proxmox\_virtual\_environment\_vm\_mac\_addresses) | The MAC addresses of the VM |
| <a name="output_proxmox_virtual_environment_vm_network_interface_names"></a> [proxmox\_virtual\_environment\_vm\_network\_interface\_names](#output\_proxmox\_virtual\_environment\_vm\_network\_interface\_names) | The network interface names of the VM |
| <a name="output_user_data"></a> [user\_data](#output\_user\_data) | The user data used for cloud-init |
| <a name="output_vm_hostname"></a> [vm\_hostname](#output\_vm\_hostname) | The hostname of the VM |
<!-- END_TF_DOCS -->

## Development

Run the repository checks from its root:

```shell
terraform fmt -check -recursive -diff
tflint --format=compact --no-color
terraform init -backend=false -input=false
terraform validate
terraform test
bash -n tests/template-validation/validate.sh
shellcheck tests/template-validation/validate.sh
tests/template-validation/validate.sh
terraform-docs .
```

The template validation script uses placeholder cloud-init values and renders the files into a temporary directory, validates it with `cloud-init schema`, and deletes it on exit. It does **not** read or use caller variables/credentials. It simply serves to check that the .tftpl templates produce valid Cloud-init snippets, not to check if callers cloud_init values are valid. 

The `Module reference` section is controlled by `.terraform-docs.yml`, edit Terraform descriptions or that configuration file instead of changing the generated block by hand.

## Contributing

Issues and pull requests are welcome. Include any relavent information such as a sanitized reproduction, Terraform and provider versions, the Proxmox VE version, and the cloud image used.

## Future work

- Fully test/document cloning from a template instead of making a new VM from a cloud image
- Come up with a better way to refer to disk images that doesnt take away any features (like ability to use compressed images) or make assumptions that could be wrong.
