# Clone a Cloud-init VM

This example clones an existing Cloud-init-capable VM or template. It uses the published module with a constraint for compatible 0.1.x releases starting at 0.1.1. The source VM must already exist; this example does not create or modify it.

Set the [Proxmox provider credentials](https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication) in environment variables, including SSH access for snippet uploads. The `local` datastore must allow snippets and `local-lvm` must allow VM disks. Choose an unused target VM ID.

```shell
export TF_VAR_node_name='pve'
export TF_VAR_source_vm_id='9000'
export TF_VAR_target_vm_id='201'
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
terraform init
terraform plan
terraform apply
```

Set `clone.node_name` and `clone.datastore_id` in `main.tf` if cloning from another node or into another datastore. The source and target VM IDs must differ. Destroying this configuration should remove only the clone and its generated snippets; review the plan before applying or destroying.
