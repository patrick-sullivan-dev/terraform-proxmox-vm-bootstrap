mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-cloud-config.yaml"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      ipv6_addresses = [["2001:db8::10"]]
    }
  }
}

mock_provider "macaddress" {}
mock_provider "local" {}

variables {
  vm_id     = 999
  name      = "ipv6-test"
  node_name = "pve"

  disks = [{
    import_from = "local:import/test.qcow2"
  }]

  network_devices = [{
    mac_address = "02:00:00:00:00:01"
  }]

  cloud_init = {
    network_data = [{
      addresses = [
        "192.0.2.10/24",
        "2001:db8::10/64",
      ]
      dhcp4 = false
      dhcp6 = false
      dns_servers = [
        "192.0.2.53",
        "2001:db8::53",
      ]
      routes = [
        { to = "0.0.0.0/0", via = "192.0.2.1" },
        { to = "::/0", via = "2001:db8::1" },
      ]
    }]
  }
}

run "renders_dual_stack_routes" {
  command = apply

  assert {
    condition = alltrue([
      strcontains(proxmox_virtual_environment_file.network_data_cloud_config.source_raw[0].data, "to: \"0.0.0.0/0\""),
      strcontains(proxmox_virtual_environment_file.network_data_cloud_config.source_raw[0].data, "via: \"192.0.2.1\""),
      strcontains(proxmox_virtual_environment_file.network_data_cloud_config.source_raw[0].data, "to: \"::/0\""),
      strcontains(proxmox_virtual_environment_file.network_data_cloud_config.source_raw[0].data, "via: \"2001:db8::1\""),
    ])
    error_message = "Dual-stack routes were not rendered into network data."
  }

  assert {
    condition     = nonsensitive(output.proxmox_virtual_environment_vm_ipv6_addresses)[0][0] == "2001:db8::10"
    error_message = "The IPv6 address output does not expose the provider value."
  }
}

run "rejects_address_without_cidr" {
  command = plan

  variables {
    cloud_init = {
      network_data = [{
        addresses = ["2001:db8::10"]
        dhcp4     = false
        dhcp6     = false
      }]
    }
  }

  expect_failures = [var.cloud_init]
}

run "rejects_gateway_with_cidr" {
  command = plan

  variables {
    cloud_init = {
      network_data = [{
        addresses     = ["2001:db8::10/64"]
        default_route = "2001:db8::1/64"
        dhcp4         = false
        dhcp6         = false
      }]
    }
  }

  expect_failures = [var.cloud_init]
}

run "rejects_mixed_route_families" {
  command = plan

  variables {
    cloud_init = {
      network_data = [{
        addresses = ["2001:db8::10/64"]
        dhcp4     = false
        dhcp6     = false
        routes = [{
          to  = "::/0"
          via = "192.0.2.1"
        }]
      }]
    }
  }

  expect_failures = [var.cloud_init]
}
