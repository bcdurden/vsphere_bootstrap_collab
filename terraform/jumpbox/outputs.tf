output "jumpbox_ip" {
  value = vsphere_virtual_machine.jumpbox.default_ip_address
}
output "jumpbox_ssh_key" {
    value = tls_private_key.global_key.private_key_pem
    sensitive = true
}
output "jumpbox_key_file" {
    value = local_sensitive_file.ssh_private_key_pem.filename
}