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
  name      = "debug-test"
  node_name = "pve"

  clone = {
    vm_id = 9000
  }

  network_devices = [{
    mac_address = "02:00:00:00:00:01"
  }]

  cloud_init = {}
}

run "debug_files_disabled_by_default" {
  command = plan

  assert {
    condition = (
      length(local_sensitive_file.rendered_network_config_debug) == 0 &&
      length(local_sensitive_file.rendered_user_config_debug) == 0
    )
    error_message = "Debug files must remain opt-in."
  }
}

run "debug_files_use_root_and_private_permissions" {
  command = plan

  variables {
    debug_files = true
  }

  assert {
    condition = (
      local_sensitive_file.rendered_network_config_debug[0].filename == "${path.root}/debug-999-network-cloud-config.yaml" &&
      local_sensitive_file.rendered_user_config_debug[0].filename == "${path.root}/debug-999-user-cloud-config.yaml" &&
      local_sensitive_file.rendered_network_config_debug[0].file_permission == "0600" &&
      local_sensitive_file.rendered_user_config_debug[0].file_permission == "0600"
    )
    error_message = "Debug files must use distinct VM ID names in the caller's root directory with private permissions."
  }
}

run "debug_files_use_custom_directory" {
  command = plan

  variables {
    debug_files     = true
    debug_directory = "artifacts"
  }

  assert {
    condition = (
      local_sensitive_file.rendered_network_config_debug[0].filename == "artifacts/debug-999-network-cloud-config.yaml" &&
      local_sensitive_file.rendered_user_config_debug[0].filename == "artifacts/debug-999-user-cloud-config.yaml"
    )
    error_message = "Debug files must honor debug_directory."
  }
}

run "rejects_empty_debug_directory" {
  command = plan

  variables {
    debug_directory = "   "
  }

  expect_failures = [var.debug_directory]
}
