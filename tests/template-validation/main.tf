locals {
  user_data_cases = {
    minimal = templatefile("${path.module}/../../templates/user-data-cloud-config.tftpl", {
      fqdn     = null
      hostname = null
      packages = []
      user_data = [{
        authorized_keys = []
        groups          = ["sudo"]
        password        = null
        shell           = "/bin/bash"
        ssh_import_ids  = []
        sudoers         = "ALL=(ALL) NOPASSWD:ALL"
        username        = "fixture-user"
      }]
    })

    populated = templatefile("${path.module}/../../templates/user-data-cloud-config.tftpl", {
      fqdn     = "fixture.example.test"
      hostname = "fixture"
      packages = ["curl", "jq"]
      user_data = [{
        authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureOnly fixture@example.test"]
        groups          = ["sudo", "users"]
        password        = "not-a-real-password-hash"
        shell           = "/bin/bash"
        ssh_import_ids  = ["gh:fixture-user"]
        sudoers         = "ALL=(ALL) NOPASSWD:ALL"
        username        = "fixture-user"
      }]
    })
  }

  network_data_cases = {
    dhcp = templatefile("${path.module}/../../templates/network-data-cloud-config.tftpl", {
      network_data = [{
        addresses      = []
        default_route  = null
        dhcp4          = null
        dhcp6          = false
        dns_domains    = []
        dns_servers    = []
        interface_name = "eth0"
        mac_address    = "02:00:00:00:00:01"
        routes         = []
      }]
    })

    dhcp6 = templatefile("${path.module}/../../templates/network-data-cloud-config.tftpl", {
      network_data = [{
        addresses      = []
        default_route  = null
        dhcp4          = false
        dhcp6          = true
        dns_domains    = []
        dns_servers    = []
        interface_name = "eth0"
        mac_address    = "02:00:00:00:00:01"
        routes         = []
      }]
    })

    ipv6_static = templatefile("${path.module}/../../templates/network-data-cloud-config.tftpl", {
      network_data = [{
        addresses      = ["2001:db8::10/64"]
        default_route  = "2001:db8::1"
        dhcp4          = false
        dhcp6          = false
        dns_domains    = ["example.test"]
        dns_servers    = ["2001:db8::53"]
        interface_name = "eth0"
        mac_address    = "02:00:00:00:00:01"
        routes         = []
      }]
    })

    dual_stack = templatefile("${path.module}/../../templates/network-data-cloud-config.tftpl", {
      network_data = [{
        addresses      = ["192.0.2.10/24", "2001:db8::10/64"]
        default_route  = null
        dhcp4          = false
        dhcp6          = false
        dns_domains    = ["example.test"]
        dns_servers    = ["192.0.2.53", "2001:db8::53"]
        interface_name = "eth0"
        mac_address    = "02:00:00:00:00:01"
        routes = [
          { to = "0.0.0.0/0", via = "192.0.2.1" },
          { to = "::/0", via = "2001:db8::1" },
        ]
      }]
    })

    static = templatefile("${path.module}/../../templates/network-data-cloud-config.tftpl", {
      network_data = [
        {
          addresses      = ["192.0.2.10/24"]
          default_route  = "192.0.2.1"
          dhcp4          = false
          dhcp6          = false
          dns_domains    = ["example.test"]
          dns_servers    = ["192.0.2.53"]
          interface_name = "eth0"
          mac_address    = "02:00:00:00:00:01"
          routes         = []
        },
        {
          addresses      = ["2001:db8::10/64"]
          default_route  = "2001:db8::1"
          dhcp4          = false
          dhcp6          = false
          dns_domains    = []
          dns_servers    = ["2001:db8::53"]
          interface_name = "eth1"
          mac_address    = "02:00:00:00:00:02"
          routes         = []
        },
      ]
    })
  }
}
