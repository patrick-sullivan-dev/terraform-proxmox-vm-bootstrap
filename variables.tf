# ===================================================
# General VM Settings
# ===================================================
variable "vm_id" {
  description = "The ID of the VM to be created"
  type        = number
}

variable "name" {
  description = "The name of the VM within Proxmox"
  type        = string
}

variable "description" {
  description = "The description of the VM within Proxmox"
  type        = string
  default     = "Managed by Terraform"
  nullable    = false
}

variable "tags" {
  description = "List of tags to add to the VM within Proxmox"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "node_name" {
  description = "Proxmox node to create the VM on"
  type        = string
}

variable "pool_id" {
  description = "Proxmox pool to add the VM to"
  type        = string
  default     = null
  nullable    = true
}

# ===================================================
# System / OS Settings
# ===================================================
variable "system" {
  description = <<-EOT
    System configuration

    In image mode, an EFI disk is automatically created when bios is "ovmf";
    datastore_id for EFI and TPM state defaults to local-lvm. Clone mode
    inherits those storage devices, ignores efi_disk, and requires tpm_state
    to remain null. Keep bios and machine compatible with the source VM.

    Defaults to q35 / ovmf / l26 with a 4m EFI disk and no TPM.
  EOT

  type = object({
    machine = optional(string, "q35")
    bios    = optional(string, "ovmf")
    os_type = optional(string, "l26")
    efi_disk = optional(object({
      datastore_id      = optional(string)
      file_format       = optional(string)
      type              = optional(string, "4m")
      pre_enrolled_keys = optional(bool)
    }), {})
    tpm_state = optional(object({
      datastore_id = optional(string)
      version      = optional(string)
    }))
  })
  default  = {}
  nullable = false
}

# ===================================================
# CPU & Memory Settings
# ===================================================

variable "cpu" {
  description = "CPU configuration, defaults to 2 x86-64-v2-AES cores"

  type = object({
    architecture = optional(string)
    cores        = optional(number, 2)
    flags        = optional(list(string))
    hotplugged   = optional(number)
    limit        = optional(number)
    numa         = optional(bool)
    sockets      = optional(number)
    type         = optional(string, "x86-64-v2-AES")
    units        = optional(number)
    affinity     = optional(string)
  })

  default  = {}
  nullable = false
}

variable "memory" {
  description = "Memory configuration (1GB = 1024), defaults to 2GB with ballooning enabled"
  type = object({
    dedicated         = optional(number, 2048)
    ballooning_device = optional(bool, true)
    shared            = optional(number)
    hugepages         = optional(string)
    keep_hugepages    = optional(bool)
  })
  default  = {}
  nullable = false
}

# ===================================================
# Disk Settings
# ===================================================
variable "disks" {
  description = <<-EOT
    Disk specifications.

    Specify only the disk interface type: scsi, sata, or virtio.
    Do not include an index such as scsi0; indexes are assigned automatically.

    In image mode, the first disk is the boot disk. Its import_from and file_id
    values fall back to the matching cloud_image value. Exactly one of file_id,
    import_from, or path_in_datastore must resolve for that disk.

    Image mode requires at least one disk; clone mode requires this list to be
    empty so inherited disks are not modified. Each entry defaults to the
    local-lvm datastore, scsi interface, and raw format; disk size is
    provider-defined when omitted.
  EOT

  type = list(object({
    aio               = optional(string)
    backup            = optional(bool)
    cache             = optional(string)
    datastore_id      = optional(string, "local-lvm")
    discard           = optional(string)
    file_format       = optional(string, "raw")
    file_id           = optional(string)
    import_from       = optional(string)
    interface         = optional(string, "scsi")
    iothread          = optional(bool)
    path_in_datastore = optional(string)
    queues            = optional(number)
    replicate         = optional(bool)
    serial            = optional(string)
    size              = optional(number)
    ssd               = optional(bool)
    speed = optional(object({
      iops_read            = optional(number)
      iops_read_burstable  = optional(number)
      iops_write           = optional(number)
      iops_write_burstable = optional(number)
      read                 = optional(number)
      read_burstable       = optional(number)
      write                = optional(number)
      write_burstable      = optional(number)
    }))
  }))

  validation {
    condition     = alltrue([for disk in var.disks : contains(["scsi", "sata", "virtio"], disk.interface)])
    error_message = "Interface must be one of scsi, sata, virtio. Do not append index."
  }

  default  = []
  nullable = false
}

variable "cloud_image" {
  description = <<-EOT
    Cloud image used to initialize the VM.

    Provide either import_from or file_id using a Proxmox file identifier.

    This object may be omitted only when the first disks entry supplies its
    own image source. Use one of the following; prefer import_from unless
    using an ISO or compressed image.
    import_from: "<datastore_id>:import/<file_name>"
    file_id: "<datastore_id>:<content_type>/<file_name>"

    A proxmox_download_file resource id can also be used instead.

    Leave this object empty in clone mode.
  EOT

  type = object({
    import_from = optional(string)
    file_id     = optional(string)
  })

  validation {
    condition = !(
      var.cloud_image.import_from != null &&
      var.cloud_image.file_id != null
    )

    error_message = "Only one of cloud_image.import_from or cloud_image.file_id may be provided."
  }

  validation {
    condition = alltrue([
      for value in [
        var.cloud_image.import_from,
        var.cloud_image.file_id,
      ] : value == null || trimspace(value) != ""
    ])

    error_message = "cloud_image values must not be empty strings."
  }

  default  = {}
  nullable = false
}

variable "clone" {
  description = <<-EOT
    Configuration for cloning an existing VM or template.

    vm_id identifies the source and must differ from the target VM ID. full
    defaults to true. Clone mode requires empty disks and cloud_image values;
    inherited disk, EFI, and TPM devices are not managed by the module.
  EOT

  type = object({
    vm_id        = number
    node_name    = optional(string)
    datastore_id = optional(string)
    full         = optional(bool, true)
    retries      = optional(number)
  })

  default  = null
  nullable = true
}

variable "scsi_hardware" {
  description = "SCSI controller type"
  type        = string
  default     = "virtio-scsi-single"
}

# ===================================================
# Network Settings
# ===================================================
variable "network_devices" {
  description = "Network interface configurations, defaults to one virtio interface on vmbr0 with firewall enabled."
  type = list(object({
    model        = optional(string, "virtio")
    bridge       = optional(string, "vmbr0")
    vlan_id      = optional(number)
    rate_limit   = optional(number)
    firewall     = optional(bool, true)
    disconnected = optional(bool)
    mtu          = optional(number)
    multi_queue  = optional(number)
    mac_address  = optional(string)
    trunks       = optional(string)
  }))

  default  = [{}]
  nullable = false
}

# ===================================================
# Cloud-Init
# ===================================================

variable "cloud_init" {
  description = <<-EOT
    Cloud-init configuration.

    datastore_id must allow the snippets content type. disk_datastore_id must
    allow VM disk images. user_data and network_data default to one entry each;
    network_data must contain the same number of entries as network_devices.

    User passwords must be Cloud-init-compatible password hashes. Prefer
    authorized_keys or ssh_import_ids instead.
  EOT
  type = object({
    datastore_id        = optional(string, "local")
    node_name           = optional(string)
    disk_datastore_id   = optional(string, "local-lvm")
    interface           = optional(string)
    file_format         = optional(string)
    vendor_data_file_id = optional(string)
    meta_data_file_id   = optional(string)

    hostname = optional(string, null)
    fqdn     = optional(string, null)

    user_data = optional(list(object({
      username        = optional(string, "ubuntu")
      password        = optional(string, null)
      groups          = optional(list(string), ["sudo"])
      shell           = optional(string, "/bin/bash")
      sudoers         = optional(string, "ALL=(ALL) NOPASSWD:ALL")
      ssh_import_ids  = optional(list(string), [])
      authorized_keys = optional(list(string), [])
    })), [{}])

    network_data = optional(list(object({
      interface_name = optional(string, "eth0")
      addresses      = optional(list(string), [])
      dhcp4          = optional(bool, null)
      dhcp6          = optional(bool, false)
      default_route  = optional(string, null)
      routes = optional(list(object({
        to  = string
        via = string
      })), [])
      dns_servers = optional(list(string), [])
      dns_domains = optional(list(string), [])
      mac_prefix  = optional(list(number), [2])
    })), [{}])

    packages = optional(list(string), [])
  })

  validation {
    condition = alltrue(flatten([
      for network in var.cloud_init.network_data : [
        for address in network.addresses : can(cidrhost(address, 0))
      ]
    ]))

    error_message = "cloud_init.network_data addresses must use valid IPv4 or IPv6 CIDR notation."
  }

  validation {
    condition = alltrue([
      for network in var.cloud_init.network_data :
      network.default_route == null ? true : can(cidrhost(
        "${network.default_route}/${strcontains(network.default_route, ":") ? 128 : 32}",
        0,
      ))
    ])

    error_message = "cloud_init.network_data default_route values must be valid IPv4 or IPv6 addresses without a CIDR prefix."
  }

  validation {
    condition = alltrue(flatten([
      for network in var.cloud_init.network_data : [
        for route in network.routes :
        can(cidrhost(route.to, 0)) &&
        can(cidrhost("${route.via}/${strcontains(route.via, ":") ? 128 : 32}", 0)) &&
        strcontains(route.to, ":") == strcontains(route.via, ":")
      ]
    ]))

    error_message = "cloud_init.network_data routes must use a valid CIDR destination and a same-family IPv4 or IPv6 gateway."
  }

  nullable = false
}

# ===================================================
# Advanced Features
# ===================================================

variable "acpi" {
  description = "Whether to enable ACPI"
  type        = bool
  default     = true
  nullable    = false
}

variable "agent" {
  description = "QEMU Guest Agent configuration"
  type = object({
    enabled = optional(bool, true)
    timeout = optional(string)
    trim    = optional(bool)
    type    = optional(string)
    wait_for_ip = optional(object({
      disabled = optional(bool)
      ipv4     = optional(bool)
      ipv6     = optional(bool)
    }))
  })
  default  = {}
  nullable = false
}

variable "amd_sev" {
  description = "AMD SEV configuration"
  type = object({
    type           = optional(string, "std")
    allow_smt      = optional(bool, true)
    kernel_hashes  = optional(bool, false)
    no_debug       = optional(bool, false)
    no_key_sharing = optional(bool, false)
  })
  default = null
}

variable "audio_device" {
  description = "Audio device configuration"
  type = object({
    device  = optional(string, "intel-hda")
    driver  = optional(string, "spice")
    enabled = optional(bool, true)
  })
  default = null
}

variable "boot_order" {
  description = "Boot order configuration"
  type        = list(string)
  default     = null
}

variable "cdrom" {
  description = "CD-ROM configuration"
  type = object({
    enabled   = optional(bool, false)
    file_id   = optional(string, "none")
    interface = optional(string, "ide3")
  })
  default = null
}

variable "hostpci" {
  description = "Host PCI passthrough configuration"
  type = list(object({
    device   = string
    id       = optional(string)
    mapping  = optional(string)
    mdev     = optional(string)
    pcie     = optional(bool)
    rombar   = optional(bool)
    rom_file = optional(string)
    xvga     = optional(bool)
  }))
  default = null
}

variable "hotplug" {
  description = "Hotplug configuration, accepts 0 to disable, 1 to enable all, or a comma-separated list of cpu, disk, memory, network, and usb"
  type        = string
  default     = null

  validation {
    condition = var.hotplug == null ? true : (
      contains(["0", "1"], var.hotplug) || (
        length(split(",", var.hotplug)) > 0 &&
        length(distinct(split(",", var.hotplug))) == length(split(",", var.hotplug)) &&
        alltrue([
          for feature in split(",", var.hotplug) :
          contains(["cpu", "disk", "memory", "network", "usb"], feature)
        ])
      )
    )

    error_message = "Hotplug must be 0, 1, or a comma-separated list containing cpu, disk, memory, network, and usb without duplicates."
  }
}

variable "usb" {
  description = "USB device configuration"
  type = list(object({
    host    = optional(string)
    mapping = optional(string)
    usb3    = optional(bool)
  }))
  default = null
}

variable "keyboard_layout" {
  description = "Keyboard layout within Proxmox"
  type        = string
  default     = null
}

variable "kvm_arguments" {
  description = "Additional KVM arguments"
  type        = string
  default     = null
}

variable "numa" {
  description = "The NUMA configuration"
  type = list(object({
    device    = string
    cpus      = string
    memory    = number
    hostnodes = optional(list(string))
    policy    = optional(string)
  }))
  default = null
}

variable "migrate" {
  description = "Whether to migrate (true) or recreate (false) the VM on node change"
  type        = bool
  default     = false
  nullable    = false
}

variable "on_boot" {
  description = "Whether to start the VM on system boot"
  type        = bool
  default     = true
}

variable "protection" {
  description = "Sets the protection flag of the VM"
  type        = bool
  default     = false
}

variable "reboot" {
  description = "Whether to reboot the VM after creation"
  type        = bool
  default     = false
}

variable "reboot_after_update" {
  description = "Whether the provider may reboot or stop the VM when required to apply configuration updates"
  type        = bool
  default     = true
}

variable "rng" {
  description = "RNG device configuration"
  type = object({
    source    = optional(string, "/dev/urandom")
    max_bytes = optional(number)
    period    = optional(number)
  })
  default = null
}

variable "serial_device" {
  description = "Serial device configuration, defaults to one socket device, set to null for no serial device"
  type = list(object({
    device = optional(string, "socket")
  }))
  default = [{}]
}

variable "started" {
  description = "Whether to start the VM after creation"
  type        = bool
  default     = true
}

variable "startup" {
  description = "Startup configuration, time measured in seconds"
  type = object({
    order      = optional(number)
    up_delay   = optional(number)
    down_delay = optional(number)
  })
  default = null
}

variable "stop_on_destroy" {
  description = "Whether to stop rather than shutdown VM before destroy"
  type        = bool
  default     = false
}

variable "tablet_device" {
  description = "Whether to enable the USB tablet device"
  type        = bool
  default     = true
}

variable "timeout_create" {
  description = "Timeout for VM creation in seconds"
  type        = number
  default     = 1800
}

variable "timeout_migrate" {
  description = "Timeout for VM migration in seconds"
  type        = number
  default     = 1800
}

variable "timeout_reboot" {
  description = "Timeout for VM reboot in seconds"
  type        = number
  default     = 1800
}

variable "timeout_shutdown_vm" {
  description = "Timeout for VM shutdown in seconds"
  type        = number
  default     = 1800
}

variable "timeout_start_vm" {
  description = "Timeout for VM startup in seconds"
  type        = number
  default     = 1800
}

variable "timeout_stop_vm" {
  description = "Timeout for stopping the VM in seconds"
  type        = number
  default     = 300
}

variable "purge_on_destroy" {
  description = "Whether to purge backup configs of the VM on destroy"
  type        = bool
  default     = true
}

variable "delete_unreferenced_disks_on_destroy" {
  description = "Whether to delete unreferenced disks when the VM is destroyed"
  type        = bool
  default     = true
}

variable "vga" {
  description = "VGA device configuration"
  type = object({
    memory    = optional(number)
    type      = optional(string)
    clipboard = optional(string)
  })
  default = null
}

variable "virtiofs" {
  description = "Virtiofs share configuration"
  type = list(object({
    mapping      = string
    cache        = optional(string)
    direct_io    = optional(bool)
    expose_acl   = optional(bool)
    expose_xattr = optional(bool)
  }))
  default = null
}

variable "hook_script_file_id" {
  description = "Proxmox file ID for the hook script to be used with the VM"
  type        = string
  default     = null
}

variable "smbios" {
  description = "SMBIOS type 1 configuration"
  type = object({
    family       = optional(string)
    manufacturer = optional(string)
    product      = optional(string)
    serial       = optional(string)
    sku          = optional(string)
    uuid         = optional(string)
    version      = optional(string)
  })
  default = null
}

variable "template" {
  description = "Whether to convert the VM into a template"
  type        = bool
  default     = false
}

variable "watchdog" {
  description = "Watchdog device configuration"
  type = object({
    enabled = optional(bool)
    model   = optional(string)
    action  = optional(string)
  })
  default = null
}

# ===================================================
# Misc
# ===================================================
variable "debug_files" {
  description = "Write rendered Cloud-init user-data and network-data to private files for debugging. Files may contain secrets."
  type        = bool
  default     = false
  nullable    = false
}

variable "debug_directory" {
  description = "Directory for debug files when debug_files is true. Defaults to the calling root module directory; use an absolute custom path for predictable placement."
  type        = string
  default     = null

  validation {
    condition     = var.debug_directory == null ? true : trimspace(var.debug_directory) != ""
    error_message = "debug_directory must be a non-empty path when set."
  }
}
