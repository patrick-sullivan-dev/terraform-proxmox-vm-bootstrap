output "proxmox_virtual_environment_vm_ipv4_addresses" {
  description = "The IPv4 addresses of the VM"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
  sensitive   = true
}

output "proxmox_virtual_environment_vm_ipv6_addresses" {
  description = "The IPv6 addresses of the VM"
  value       = proxmox_virtual_environment_vm.this.ipv6_addresses
  sensitive   = true
}

output "proxmox_virtual_environment_vm_mac_addresses" {
  description = "The MAC addresses of the VM"
  value       = proxmox_virtual_environment_vm.this.mac_addresses
  sensitive   = true
}

output "proxmox_virtual_environment_vm_network_interface_names" {
  description = "The network interface names of the VM"
  value       = proxmox_virtual_environment_vm.this.network_interface_names
  sensitive   = true
}

output "proxmox_virtual_environment_vm" {
  description = "The Proxmox VE VM resource"
  value       = proxmox_virtual_environment_vm.this
  sensitive   = true
}

output "vm_hostname" {
  description = "The hostname of the VM"
  value       = var.cloud_init.hostname
  sensitive   = true
}

output "id" {
  description = "The ID of the VM in Proxmox VE"
  value       = var.vm_id
  sensitive   = true
}

output "name" {
  description = "The name of the VM in Proxmox VE"
  value       = var.name
  sensitive   = true
}

output "node_name" {
  description = "The Proxmox VE node name where the VM exists"
  value       = var.node_name
  sensitive   = true
}

output "user_data" {
  description = "The user data used for cloud-init"
  value       = var.cloud_init.user_data
  sensitive   = true
}
