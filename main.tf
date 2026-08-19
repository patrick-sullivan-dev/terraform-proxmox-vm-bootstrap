resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.cloud_init.datastore_id
  node_name    = coalesce(var.cloud_init.node_name, var.node_name)

  source_raw {
    data = templatefile("${path.module}/templates/user-data-cloud-config.tftpl", {
      fqdn      = var.cloud_init.fqdn
      hostname  = var.cloud_init.hostname
      packages  = var.cloud_init.packages
      user_data = var.cloud_init.user_data
    })
    file_name = "${var.vm_id}-user-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "network_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.cloud_init.datastore_id
  node_name    = coalesce(var.cloud_init.node_name, var.node_name)

  source_raw {
    data = templatefile("${path.module}/templates/network-data-cloud-config.tftpl", {
      network_data = local.network_data
    })
    file_name = "${var.vm_id}-network-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  acpi                                 = var.acpi
  bios                                 = var.system.bios
  boot_order                           = var.boot_order
  delete_unreferenced_disks_on_destroy = var.delete_unreferenced_disks_on_destroy
  description                          = var.description
  hook_script_file_id                  = var.hook_script_file_id
  hotplug                              = var.hotplug
  keyboard_layout                      = var.keyboard_layout
  kvm_arguments                        = var.kvm_arguments
  machine                              = var.system.machine
  migrate                              = var.migrate
  name                                 = var.name
  node_name                            = var.node_name
  on_boot                              = var.on_boot
  pool_id                              = var.pool_id
  protection                           = var.protection
  purge_on_destroy                     = var.purge_on_destroy
  reboot                               = var.reboot
  reboot_after_update                  = var.reboot_after_update
  scsi_hardware                        = var.scsi_hardware
  started                              = var.started
  stop_on_destroy                      = var.stop_on_destroy
  tablet_device                        = var.tablet_device
  tags                                 = sort(var.tags)
  template                             = var.template
  timeout_create                       = var.timeout_create
  timeout_migrate                      = var.timeout_migrate
  timeout_reboot                       = var.timeout_reboot
  timeout_shutdown_vm                  = var.timeout_shutdown_vm
  timeout_start_vm                     = var.timeout_start_vm
  timeout_stop_vm                      = var.timeout_stop_vm
  vm_id                                = var.vm_id

  agent {
    enabled = var.agent.enabled
    timeout = var.agent.timeout
    trim    = var.agent.trim
    type    = var.agent.type

    dynamic "wait_for_ip" {
      for_each = var.agent.wait_for_ip == null ? [] : [var.agent.wait_for_ip]

      content {
        disabled = wait_for_ip.value.disabled
        ipv4     = wait_for_ip.value.ipv4
        ipv6     = wait_for_ip.value.ipv6
      }
    }
  }

  dynamic "amd_sev" {
    for_each = var.amd_sev == null ? [] : [var.amd_sev]

    content {
      allow_smt      = amd_sev.value.allow_smt
      kernel_hashes  = amd_sev.value.kernel_hashes
      no_debug       = amd_sev.value.no_debug
      no_key_sharing = amd_sev.value.no_key_sharing
      type           = amd_sev.value.type
    }
  }

  dynamic "audio_device" {
    for_each = var.audio_device == null ? [] : [var.audio_device]

    content {
      device  = audio_device.value.device
      driver  = audio_device.value.driver
      enabled = audio_device.value.enabled
    }
  }

  dynamic "cdrom" {
    for_each = var.cdrom == null ? [] : [var.cdrom]

    content {
      enabled   = cdrom.value.enabled
      file_id   = cdrom.value.file_id
      interface = cdrom.value.interface
    }
  }

  dynamic "clone" {
    for_each = local.using_clone ? [var.clone] : []

    content {
      datastore_id = clone.value.datastore_id
      full         = clone.value.full
      node_name    = clone.value.node_name
      retries      = clone.value.retries
      vm_id        = clone.value.vm_id
    }
  }

  cpu {
    affinity     = var.cpu.affinity
    architecture = var.cpu.architecture
    cores        = var.cpu.cores
    flags        = var.cpu.flags
    hotplugged   = var.cpu.hotplugged
    limit        = var.cpu.limit
    numa         = var.cpu.numa
    sockets      = var.cpu.sockets
    type         = var.cpu.type
    units        = var.cpu.units
  }

  dynamic "disk" {
    for_each = local.using_clone ? [] : local.disks

    content {
      aio               = disk.value.aio
      backup            = disk.value.backup
      cache             = disk.value.cache
      datastore_id      = disk.value.datastore_id
      discard           = disk.value.discard
      file_format       = disk.value.file_format
      file_id           = disk.value.file_id
      import_from       = disk.value.import_from
      interface         = disk.value.interface
      iothread          = disk.value.iothread
      path_in_datastore = disk.value.path_in_datastore
      queues            = disk.value.queues
      replicate         = disk.value.replicate
      serial            = disk.value.serial
      size              = disk.value.size
      ssd               = disk.value.ssd

      dynamic "speed" {
        for_each = disk.value.speed == null ? [] : [disk.value.speed]

        content {
          iops_read            = speed.value.iops_read
          iops_read_burstable  = speed.value.iops_read_burstable
          iops_write           = speed.value.iops_write
          iops_write_burstable = speed.value.iops_write_burstable
          read                 = speed.value.read
          read_burstable       = speed.value.read_burstable
          write                = speed.value.write
          write_burstable      = speed.value.write_burstable
        }
      }
    }
  }

  dynamic "efi_disk" {
    for_each = !local.using_clone && var.system.bios == "ovmf" ? [var.system.efi_disk] : []

    content {
      datastore_id      = efi_disk.value.datastore_id
      file_format       = efi_disk.value.file_format
      pre_enrolled_keys = efi_disk.value.pre_enrolled_keys
      type              = efi_disk.value.type
    }
  }

  dynamic "hostpci" {
    for_each = var.hostpci == null ? [] : var.hostpci

    content {
      device   = hostpci.value.device
      id       = hostpci.value.id
      mapping  = hostpci.value.mapping
      mdev     = hostpci.value.mdev
      pcie     = hostpci.value.pcie
      rom_file = hostpci.value.rom_file
      rombar   = hostpci.value.rombar
      xvga     = hostpci.value.xvga
    }
  }

  initialization {
    datastore_id         = var.cloud_init.disk_datastore_id
    file_format          = var.cloud_init.file_format
    interface            = var.cloud_init.interface
    meta_data_file_id    = var.cloud_init.meta_data_file_id
    network_data_file_id = proxmox_virtual_environment_file.network_data_cloud_config.id
    user_data_file_id    = proxmox_virtual_environment_file.user_data_cloud_config.id
    vendor_data_file_id  = var.cloud_init.vendor_data_file_id
  }

  memory {
    dedicated      = var.memory.dedicated
    floating       = var.memory.ballooning_device ? var.memory.dedicated : 0
    hugepages      = var.memory.hugepages
    keep_hugepages = var.memory.keep_hugepages
    shared         = var.memory.shared
  }

  dynamic "network_device" {
    for_each = local.network_devices

    content {
      bridge       = network_device.value.bridge
      disconnected = network_device.value.disconnected
      firewall     = network_device.value.firewall
      mac_address  = network_device.value.mac_address
      model        = network_device.value.model
      mtu          = network_device.value.mtu
      queues       = network_device.value.multi_queue
      rate_limit   = network_device.value.rate_limit
      trunks       = network_device.value.trunks
      vlan_id      = network_device.value.vlan_id
    }
  }

  dynamic "numa" {
    for_each = var.numa == null ? [] : var.numa

    content {
      cpus      = numa.value.cpus
      device    = numa.value.device
      hostnodes = numa.value.hostnodes
      memory    = numa.value.memory
      policy    = numa.value.policy
    }
  }

  operating_system {
    type = var.system.os_type
  }

  dynamic "rng" {
    for_each = var.rng == null ? [] : [var.rng]

    content {
      max_bytes = rng.value.max_bytes
      period    = rng.value.period
      source    = rng.value.source
    }
  }

  dynamic "serial_device" {
    for_each = var.serial_device == null ? [] : var.serial_device

    content {
      device = serial_device.value.device
    }
  }

  dynamic "smbios" {
    for_each = var.smbios == null ? [] : [var.smbios]

    content {
      family       = smbios.value.family
      manufacturer = smbios.value.manufacturer
      product      = smbios.value.product
      serial       = smbios.value.serial
      sku          = smbios.value.sku
      uuid         = smbios.value.uuid
      version      = smbios.value.version
    }
  }

  dynamic "startup" {
    for_each = var.startup == null ? [] : [var.startup]

    content {
      down_delay = startup.value.down_delay
      order      = startup.value.order
      up_delay   = startup.value.up_delay
    }
  }

  dynamic "tpm_state" {
    for_each = !local.using_clone && var.system.tpm_state != null ? [var.system.tpm_state] : []

    content {
      datastore_id = tpm_state.value.datastore_id
      version      = tpm_state.value.version
    }
  }

  dynamic "usb" {
    for_each = var.usb == null ? [] : var.usb

    content {
      host    = usb.value.host
      mapping = usb.value.mapping
      usb3    = usb.value.usb3
    }
  }

  dynamic "vga" {
    for_each = var.vga == null ? [] : [var.vga]

    content {
      clipboard = vga.value.clipboard
      memory    = vga.value.memory
      type      = vga.value.type
    }
  }

  dynamic "virtiofs" {
    for_each = var.virtiofs == null ? [] : var.virtiofs

    content {
      cache        = virtiofs.value.cache
      direct_io    = virtiofs.value.direct_io
      expose_acl   = virtiofs.value.expose_acl
      expose_xattr = virtiofs.value.expose_xattr
      mapping      = virtiofs.value.mapping
    }
  }

  dynamic "watchdog" {
    for_each = var.watchdog == null ? [] : [var.watchdog]

    content {
      action  = watchdog.value.action
      enabled = watchdog.value.enabled
      model   = watchdog.value.model
    }
  }

  lifecycle {
    precondition {
      condition = !local.using_cloud_image || (
        local.boot_disk != null &&
        length(local.boot_disk_sources) == 1
      )

      error_message = "Configure the first disk with exactly one of file_id, import_from, or path_in_datastore, either directly or through cloud_image."
    }

    precondition {
      condition     = !local.using_clone || length(var.disks) == 0
      error_message = "disks must be empty when clone is configured; cloned disks are inherited from the source VM."
    }

    precondition {
      condition     = !local.using_clone || local.cloud_image_source_count == 0
      error_message = "cloud_image must not be configured when clone is configured."
    }

    precondition {
      condition     = local.using_clone ? var.clone.vm_id != var.vm_id : true
      error_message = "clone.vm_id must differ from the target vm_id."
    }

    precondition {
      condition     = !local.using_clone || var.system.tpm_state == null
      error_message = "system.tpm_state cannot be configured in clone mode; TPM state is inherited from the source VM."
    }

    precondition {
      condition     = length(var.cloud_init.network_data) == length(var.network_devices)
      error_message = "cloud_init.network_data and network_devices must contain the same number of entries."
    }
  }
}

resource "macaddress" "this" {
  for_each = {
    for index, network_device in var.network_devices :
    tostring(index) => index if network_device.mac_address == null
  }

  prefix = try(var.cloud_init.network_data[each.value].mac_prefix, [2])
}

locals {
  using_clone       = var.clone != null
  using_cloud_image = var.clone == null

  network_devices = [
    for index, network_device in var.network_devices : merge(network_device, {
      mac_address = coalesce(
        network_device.mac_address,
        try(macaddress.this[tostring(index)].address, null),
      )
    })
  ]

  network_data = [
    for index, network_data in var.cloud_init.network_data : merge(network_data, {
      mac_address = local.network_devices[index].mac_address
    }) if index < length(local.network_devices)
  ]

  disks = [
    for index, disk in var.disks : merge(disk, {
      file_id = index == 0 ? try(
        coalesce(disk.file_id, var.cloud_image.file_id),
        null,
      ) : disk.file_id
      import_from = index == 0 ? try(
        coalesce(disk.import_from, var.cloud_image.import_from),
        null,
      ) : disk.import_from
      interface = "${disk.interface}${index}"
    })
  ]

  boot_disk = try(local.disks[0], null)

  boot_disk_sources = [
    for value in [
      try(local.boot_disk.file_id, null),
      try(local.boot_disk.import_from, null),
      try(local.boot_disk.path_in_datastore, null),
    ] : value if value != null
  ]

  cloud_image_source_count = length([
    for value in [
      var.cloud_image.file_id,
      var.cloud_image.import_from,
    ] : value if value != null
  ])
}

resource "local_file" "rendered_network_config_debug" {
  count = var.debug_files ? 1 : 0

  content = templatefile("${path.module}/templates/network-data-cloud-config.tftpl", {
    network_data = local.network_data
  })

  filename = "${path.module}/debug-${var.name}-network-cloud-config.yaml"
}

resource "local_file" "rendered_user_config_debug" {
  count = var.debug_files ? 1 : 0

  content = templatefile("${path.module}/templates/user-data-cloud-config.tftpl", {
    fqdn      = var.cloud_init.fqdn
    hostname  = var.cloud_init.hostname
    packages  = var.cloud_init.packages
    user_data = var.cloud_init.user_data
  })

  filename = "${path.module}/debug-${var.name}-user-cloud-config.yaml"
}
