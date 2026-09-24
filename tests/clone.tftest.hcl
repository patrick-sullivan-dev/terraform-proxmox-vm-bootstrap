mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-cloud-config.yaml"
    }
  }
}

mock_provider "macaddress" {}
mock_provider "local" {}

variables {
  vm_id     = 999
  name      = "clone-test"
  node_name = "pve-b"

  network_devices = [{
    mac_address = "02:00:00:00:00:01"
  }]

  cloud_init = {}
}

run "configures_clone" {
  command = apply

  variables {
    clone = {
      vm_id        = 9000
      node_name    = "pve-a"
      datastore_id = "ceph-vm"
      full         = false
      retries      = 3
    }
  }

  assert {
    condition = alltrue([
      proxmox_virtual_environment_vm.this.clone[0].vm_id == 9000,
      proxmox_virtual_environment_vm.this.clone[0].node_name == "pve-a",
      proxmox_virtual_environment_vm.this.clone[0].datastore_id == "ceph-vm",
      proxmox_virtual_environment_vm.this.clone[0].full == false,
      proxmox_virtual_environment_vm.this.clone[0].retries == 3,
    ])
    error_message = "Clone settings were not passed to the VM resource."
  }

  assert {
    condition = alltrue([
      length(proxmox_virtual_environment_vm.this.disk) == 0,
      length(proxmox_virtual_environment_vm.this.efi_disk) == 0,
      length(proxmox_virtual_environment_vm.this.tpm_state) == 0,
    ])
    error_message = "Clone mode must inherit disk, EFI, and TPM devices from the source VM."
  }
}

run "uses_full_clone_by_default" {
  command = plan

  variables {
    clone = {
      vm_id = 9000
    }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.clone[0].full == true
    error_message = "Clone mode must preserve the provider's full-clone default."
  }
}

run "rejects_clone_with_disks" {
  command = plan

  variables {
    clone = {
      vm_id = 9000
    }

    disks = [{
      import_from = "local:import/test.qcow2"
    }]
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_clone_with_cloud_image" {
  command = plan

  variables {
    clone = {
      vm_id = 9000
    }

    cloud_image = {
      import_from = "local:import/test.qcow2"
    }
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_equal_source_and_target_ids" {
  command = plan

  variables {
    clone = {
      vm_id = 999
    }
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_tpm_configuration_in_clone_mode" {
  command = plan

  variables {
    clone = {
      vm_id = 9000
    }

    system = {
      tpm_state = {
        version = "v2.0"
      }
    }
  }

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "rejects_missing_vm_source" {
  command = plan

  expect_failures = [proxmox_virtual_environment_vm.this]
}

run "preserves_cloud_image_mode" {
  command = plan

  variables {
    disks = [{
      import_from = "local:import/test.qcow2"
    }]
  }

  assert {
    condition = alltrue([
      length(proxmox_virtual_environment_vm.this.clone) == 0,
      length(proxmox_virtual_environment_vm.this.disk) == 1,
      length(proxmox_virtual_environment_vm.this.efi_disk) == 1,
    ])
    error_message = "Cloud-image mode must retain its managed disk and EFI behavior."
  }
}
